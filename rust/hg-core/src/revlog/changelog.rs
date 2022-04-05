use crate::errors::HgError;
use crate::repo::Repo;
use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::Revision;
use crate::revlog::{Node, NodePrefix};
use crate::utils::hg_path::HgPath;
use itertools::Itertools;
use std::ascii::escape_default;
use std::fmt::{Debug, Formatter};

/// A specialized `Revlog` to work with `changelog` data format.
pub struct Changelog {
    /// The generic `revlog` format.
    pub(crate) revlog: Revlog,
}

impl Changelog {
    /// Open the `changelog` of a repository given by its root.
    pub fn open(repo: &Repo) -> Result<Self, HgError> {
        let revlog = Revlog::open(repo, "00changelog.i", None)?;
        Ok(Self { revlog })
    }

    /// Return the `ChangelogEntry` for the given node ID.
    pub fn data_for_node(
        &self,
        node: NodePrefix,
    ) -> Result<ChangelogRevisionData, RevlogError> {
        let rev = self.revlog.rev_from_node(node)?;
        self.data_for_rev(rev)
    }

    /// Return the `ChangelogEntry` of the given revision number.
    pub fn data_for_rev(
        &self,
        rev: Revision,
    ) -> Result<ChangelogRevisionData, RevlogError> {
        let bytes = self.revlog.get_rev_data(rev)?.into_owned();
        if bytes.is_empty() {
            Ok(ChangelogRevisionData::null())
        } else {
            Ok(ChangelogRevisionData::new(bytes).map_err(|err| {
                RevlogError::Other(HgError::CorruptedRepository(format!(
                    "Invalid changelog data for revision {}: {:?}",
                    rev, err
                )))
            })?)
        }
    }

    pub fn node_from_rev(&self, rev: Revision) -> Option<&Node> {
        self.revlog.node_from_rev(rev)
    }
}

/// `Changelog` entry which knows how to interpret the `changelog` data bytes.
#[derive(PartialEq)]
pub struct ChangelogRevisionData {
    /// The data bytes of the `changelog` entry.
    bytes: Vec<u8>,
    /// The end offset for the hex manifest (not including the newline)
    manifest_end: usize,
    /// The end offset for the user+email (not including the newline)
    user_end: usize,
    /// The end offset for the timestamp+timezone+extras (not including the
    /// newline)
    timestamp_end: usize,
    /// The end offset for the file list (not including the newline)
    files_end: usize,
}

impl ChangelogRevisionData {
    fn new(bytes: Vec<u8>) -> Result<Self, HgError> {
        let mut line_iter = bytes.split(|b| b == &b'\n');
        let manifest_end = line_iter
            .next()
            .expect("Empty iterator from split()?")
            .len();
        let user_slice = line_iter.next().ok_or_else(|| {
            HgError::corrupted("Changeset data truncated after manifest line")
        })?;
        let user_end = manifest_end + 1 + user_slice.len();
        let timestamp_slice = line_iter.next().ok_or_else(|| {
            HgError::corrupted("Changeset data truncated after user line")
        })?;
        let timestamp_end = user_end + 1 + timestamp_slice.len();
        let mut files_end = timestamp_end + 1;
        loop {
            let line = line_iter.next().ok_or_else(|| {
                HgError::corrupted("Changeset data truncated in files list")
            })?;
            if line.is_empty() {
                if files_end == bytes.len() {
                    // The list of files ended with a single newline (there
                    // should be two)
                    return Err(HgError::corrupted(
                        "Changeset data truncated after files list",
                    ));
                }
                files_end -= 1;
                break;
            }
            files_end += line.len() + 1;
        }

        Ok(Self {
            bytes,
            manifest_end,
            user_end,
            timestamp_end,
            files_end,
        })
    }

    fn null() -> Self {
        Self::new(
            b"0000000000000000000000000000000000000000\n\n0 0\n\n".to_vec(),
        )
        .unwrap()
    }

    /// Return an iterator over the lines of the entry.
    pub fn lines(&self) -> impl Iterator<Item = &[u8]> {
        self.bytes.split(|b| b == &b'\n')
    }

    /// Return the node id of the `manifest` referenced by this `changelog`
    /// entry.
    pub fn manifest_node(&self) -> Result<Node, HgError> {
        let manifest_node_hex = &self.bytes[..self.manifest_end];
        Node::from_hex_for_repo(manifest_node_hex)
    }

    /// The full user string (usually a name followed by an email enclosed in
    /// angle brackets)
    pub fn user(&self) -> &[u8] {
        &self.bytes[self.manifest_end + 1..self.user_end]
    }

    /// The full timestamp line (timestamp in seconds, offset in seconds, and
    /// possibly extras)
    // TODO: We should expose this in a more useful way
    pub fn timestamp_line(&self) -> &[u8] {
        &self.bytes[self.user_end + 1..self.timestamp_end]
    }

    /// The files changed in this revision.
    pub fn files(&self) -> impl Iterator<Item = &HgPath> {
        self.bytes[self.timestamp_end + 1..self.files_end]
            .split(|b| b == &b'\n')
            .map(|path| HgPath::new(path))
    }

    /// The change description.
    pub fn description(&self) -> &[u8] {
        &self.bytes[self.files_end + 2..]
    }
}

impl Debug for ChangelogRevisionData {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ChangelogRevisionData")
            .field("bytes", &debug_bytes(&self.bytes))
            .field("manifest", &debug_bytes(&self.bytes[..self.manifest_end]))
            .field(
                "user",
                &debug_bytes(
                    &self.bytes[self.manifest_end + 1..self.user_end],
                ),
            )
            .field(
                "timestamp",
                &debug_bytes(
                    &self.bytes[self.user_end + 1..self.timestamp_end],
                ),
            )
            .field(
                "files",
                &debug_bytes(
                    &self.bytes[self.timestamp_end + 1..self.files_end],
                ),
            )
            .field(
                "description",
                &debug_bytes(&self.bytes[self.files_end + 2..]),
            )
            .finish()
    }
}

fn debug_bytes(bytes: &[u8]) -> String {
    String::from_utf8_lossy(
        &bytes.iter().flat_map(|b| escape_default(*b)).collect_vec(),
    )
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use itertools::Itertools;
    use pretty_assertions::assert_eq;

    #[test]
    fn test_create_changelogrevisiondata_invalid() {
        // Completely empty
        assert!(ChangelogRevisionData::new(b"abcd".to_vec()).is_err());
        // No newline after manifest
        assert!(ChangelogRevisionData::new(b"abcd".to_vec()).is_err());
        // No newline after user
        assert!(ChangelogRevisionData::new(b"abcd\n".to_vec()).is_err());
        // No newline after timestamp
        assert!(ChangelogRevisionData::new(b"abcd\n\n0 0".to_vec()).is_err());
        // Missing newline after files
        assert!(ChangelogRevisionData::new(
            b"abcd\n\n0 0\nfile1\nfile2".to_vec()
        )
        .is_err(),);
        // Only one newline after files
        assert!(ChangelogRevisionData::new(
            b"abcd\n\n0 0\nfile1\nfile2\n".to_vec()
        )
        .is_err(),);
    }

    #[test]
    fn test_create_changelogrevisiondata() {
        let data = ChangelogRevisionData::new(
            b"0123456789abcdef0123456789abcdef01234567
Some One <someone@example.com>
0 0
file1
file2

some
commit
message"
                .to_vec(),
        )
        .unwrap();
        assert_eq!(
            data.manifest_node().unwrap(),
            Node::from_hex("0123456789abcdef0123456789abcdef01234567")
                .unwrap()
        );
        assert_eq!(data.user(), b"Some One <someone@example.com>");
        assert_eq!(data.timestamp_line(), b"0 0");
        assert_eq!(
            data.files().collect_vec(),
            vec![HgPath::new("file1"), HgPath::new("file2")]
        );
        assert_eq!(data.description(), b"some\ncommit\nmessage");
    }
}

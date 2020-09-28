use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::Revision;
use std::path::PathBuf;

/// A specialized `Revlog` to work with `changelog` data format.
pub struct Changelog {
    /// The generic `revlog` format.
    revlog: Revlog,
}

impl Changelog {
    /// Open the `changelog` of a repository given by its root.
    pub fn open(root: &PathBuf) -> Result<Self, RevlogError> {
        let index_file = root.join(".hg/store/00changelog.i");
        let revlog = Revlog::open(&index_file, None)?;
        Ok(Self { revlog })
    }

    /// Return the `ChangelogEntry` a given node id.
    pub fn get_node(
        &self,
        node: &[u8],
    ) -> Result<ChangelogEntry, RevlogError> {
        let rev = self.revlog.get_node_rev(node)?;
        self.get_rev(rev)
    }

    /// Return the `ChangelogEntry` of a given node revision.
    pub fn get_rev(
        &self,
        rev: Revision,
    ) -> Result<ChangelogEntry, RevlogError> {
        let bytes = self.revlog.get_rev_data(rev)?;
        Ok(ChangelogEntry { bytes })
    }
}

/// `Changelog` entry which knows how to interpret the `changelog` data bytes.
#[derive(Debug)]
pub struct ChangelogEntry {
    /// The data bytes of the `changelog` entry.
    bytes: Vec<u8>,
}

impl ChangelogEntry {
    /// Return an iterator over the lines of the entry.
    pub fn lines(&self) -> impl Iterator<Item = &[u8]> {
        self.bytes
            .split(|b| b == &b'\n')
            .filter(|line| !line.is_empty())
    }

    /// Return the node id of the `manifest` referenced by this `changelog`
    /// entry.
    pub fn manifest_node(&self) -> Result<&[u8], RevlogError> {
        self.lines().next().ok_or(RevlogError::Corrupted)
    }
}

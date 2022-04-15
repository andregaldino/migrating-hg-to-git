use crate::errors::HgError;
use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::Revision;
use crate::revlog::{Node, NodePrefix};
use crate::utils::hg_path::HgPath;
use crate::utils::SliceExt;
use crate::vfs::Vfs;

/// A specialized `Revlog` to work with `manifest` data format.
pub struct Manifestlog {
    /// The generic `revlog` format.
    revlog: Revlog,
}

impl Manifestlog {
    /// Open the `manifest` of a repository given by its root.
    pub fn open(store_vfs: &Vfs, use_nodemap: bool) -> Result<Self, HgError> {
        let revlog =
            Revlog::open(store_vfs, "00manifest.i", None, use_nodemap)?;
        Ok(Self { revlog })
    }

    /// Return the `Manifest` for the given node ID.
    ///
    /// Note: this is a node ID in the manifestlog, typically found through
    /// `ChangelogEntry::manifest_node`. It is *not* the node ID of any
    /// changeset.
    ///
    /// See also `Repo::manifest_for_node`
    pub fn data_for_node(
        &self,
        node: NodePrefix,
    ) -> Result<Manifest, RevlogError> {
        let rev = self.revlog.rev_from_node(node)?;
        self.data_for_rev(rev)
    }

    /// Return the `Manifest` of a given revision number.
    ///
    /// Note: this is a revision number in the manifestlog, *not* of any
    /// changeset.
    ///
    /// See also `Repo::manifest_for_rev`
    pub fn data_for_rev(
        &self,
        rev: Revision,
    ) -> Result<Manifest, RevlogError> {
        let bytes = self.revlog.get_rev_data(rev)?.into_owned();
        Ok(Manifest { bytes })
    }
}

/// `Manifestlog` entry which knows how to interpret the `manifest` data bytes.
#[derive(Debug)]
pub struct Manifest {
    /// Format for a manifest: flat sequence of variable-size entries,
    /// sorted by path, each as:
    ///
    /// ```text
    /// <path> \0 <hex_node_id> <flags> \n
    /// ```
    ///
    /// The last entry is also terminated by a newline character.
    /// Flags is one of `b""` (the empty string), `b"x"`, `b"l"`, or `b"t"`.
    bytes: Vec<u8>,
}

impl Manifest {
    pub fn iter(
        &self,
    ) -> impl Iterator<Item = Result<ManifestEntry, HgError>> {
        self.bytes
            .split(|b| b == &b'\n')
            .filter(|line| !line.is_empty())
            .map(ManifestEntry::from_raw)
    }

    /// If the given path is in this manifest, return its filelog node ID
    pub fn find_by_path(
        &self,
        path: &HgPath,
    ) -> Result<Option<ManifestEntry>, HgError> {
        use std::cmp::Ordering::*;
        let path = path.as_bytes();
        // Both boundaries of this `&[u8]` slice are always at the boundary of
        // an entry
        let mut bytes = &*self.bytes;

        // Binary search algorithm derived from `[T]::binary_search_by`
        // <https://github.com/rust-lang/rust/blob/1.57.0/library/core/src/slice/mod.rs#L2221>
        // except we don’t have a slice of entries. Instead we jump to the
        // middle of the byte slice and look around for entry delimiters
        // (newlines).
        while let Some(entry_range) = Self::find_entry_near_middle_of(bytes)? {
            let (entry_path, rest) =
                ManifestEntry::split_path(&bytes[entry_range.clone()])?;
            let cmp = entry_path.cmp(path);
            if cmp == Less {
                let after_newline = entry_range.end + 1;
                bytes = &bytes[after_newline..];
            } else if cmp == Greater {
                bytes = &bytes[..entry_range.start];
            } else {
                return Ok(Some(ManifestEntry::from_path_and_rest(
                    entry_path, rest,
                )));
            }
        }
        Ok(None)
    }

    /// If there is at least one, return the byte range of an entry *excluding*
    /// the final newline.
    fn find_entry_near_middle_of(
        bytes: &[u8],
    ) -> Result<Option<std::ops::Range<usize>>, HgError> {
        let len = bytes.len();
        if len > 0 {
            let middle = bytes.len() / 2;
            // Integer division rounds down, so `middle < len`.
            let (before, after) = bytes.split_at(middle);
            let is_newline = |&byte: &u8| byte == b'\n';
            let entry_start = match before.iter().rposition(is_newline) {
                Some(i) => i + 1,
                None => 0, // We choose the first entry in `bytes`
            };
            let entry_end = match after.iter().position(is_newline) {
                Some(i) => {
                    // No `+ 1` here to exclude this newline from the range
                    middle + i
                }
                None => {
                    // In a well-formed manifest:
                    //
                    // * Since `len > 0`, `bytes` contains at least one entry
                    // * Every entry ends with a newline
                    // * Since `middle < len`, `after` contains at least the
                    //   newline at the end of the last entry of `bytes`.
                    //
                    // We didn’t find a newline, so this manifest is not
                    // well-formed.
                    return Err(HgError::corrupted(
                        "manifest entry without \\n delimiter",
                    ));
                }
            };
            Ok(Some(entry_start..entry_end))
        } else {
            // len == 0
            Ok(None)
        }
    }
}

/// `Manifestlog` entry which knows how to interpret the `manifest` data bytes.
#[derive(Debug)]
pub struct ManifestEntry<'manifest> {
    pub path: &'manifest HgPath,
    pub hex_node_id: &'manifest [u8],

    /// `Some` values are b'x', b'l', or 't'
    pub flags: Option<u8>,
}

impl<'a> ManifestEntry<'a> {
    fn split_path(bytes: &[u8]) -> Result<(&[u8], &[u8]), HgError> {
        bytes.split_2(b'\0').ok_or_else(|| {
            HgError::corrupted("manifest entry without \\0 delimiter")
        })
    }

    fn from_path_and_rest(path: &'a [u8], rest: &'a [u8]) -> Self {
        let (hex_node_id, flags) = match rest.split_last() {
            Some((&b'x', rest)) => (rest, Some(b'x')),
            Some((&b'l', rest)) => (rest, Some(b'l')),
            Some((&b't', rest)) => (rest, Some(b't')),
            _ => (rest, None),
        };
        Self {
            path: HgPath::new(path),
            hex_node_id,
            flags,
        }
    }

    fn from_raw(bytes: &'a [u8]) -> Result<Self, HgError> {
        let (path, rest) = Self::split_path(bytes)?;
        Ok(Self::from_path_and_rest(path, rest))
    }

    pub fn node_id(&self) -> Result<Node, HgError> {
        Node::from_hex_for_repo(self.hex_node_id)
    }
}

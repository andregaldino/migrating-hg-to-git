use crate::errors::HgError;
use crate::repo::Repo;
use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::Revision;
use crate::revlog::{Node, NodePrefix};
use crate::utils::hg_path::HgPath;
use crate::utils::SliceExt;

/// A specialized `Revlog` to work with `manifest` data format.
pub struct Manifestlog {
    /// The generic `revlog` format.
    revlog: Revlog,
}

impl Manifestlog {
    /// Open the `manifest` of a repository given by its root.
    pub fn open(repo: &Repo) -> Result<Self, HgError> {
        let revlog = Revlog::open(repo, "00manifest.i", None)?;
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
        let bytes = self.revlog.get_rev_data(rev)?;
        Ok(Manifest { bytes })
    }
}

/// `Manifestlog` entry which knows how to interpret the `manifest` data bytes.
#[derive(Debug)]
pub struct Manifest {
    bytes: Vec<u8>,
}

impl Manifest {
    pub fn iter(
        &self,
    ) -> impl Iterator<Item = Result<ManifestEntry, HgError>> {
        self.bytes
            .split(|b| b == &b'\n')
            .filter(|line| !line.is_empty())
            .map(|line| {
                let (path, rest) = line.split_2(b'\0').ok_or_else(|| {
                    HgError::corrupted("manifest line should contain \\0")
                })?;
                let path = HgPath::new(path);
                let (hex_node_id, flags) = match rest.split_last() {
                    Some((&b'x', rest)) => (rest, Some(b'x')),
                    Some((&b'l', rest)) => (rest, Some(b'l')),
                    Some((&b't', rest)) => (rest, Some(b't')),
                    _ => (rest, None),
                };
                Ok(ManifestEntry {
                    path,
                    hex_node_id,
                    flags,
                })
            })
    }

    /// If the given path is in this manifest, return its filelog node ID
    pub fn find_file(
        &self,
        path: &HgPath,
    ) -> Result<Option<ManifestEntry>, HgError> {
        // TODO: use binary search instead of linear scan. This may involve
        // building (and caching) an index of the byte indicex of each manifest
        // line.

        // TODO: use try_find when available (if still using linear scan)
        // https://github.com/rust-lang/rust/issues/63178
        for entry in self.iter() {
            let entry = entry?;
            if entry.path == path {
                return Ok(Some(entry));
            }
        }
        Ok(None)
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

impl ManifestEntry<'_> {
    pub fn node_id(&self) -> Result<Node, HgError> {
        Node::from_hex_for_repo(self.hex_node_id)
    }
}

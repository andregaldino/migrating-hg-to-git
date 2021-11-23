use crate::errors::HgError;
use crate::repo::Repo;
use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::Revision;
use crate::revlog::{Node, NodePrefix};
use crate::utils::hg_path::HgPath;

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
    /// Return an iterator over the lines of the entry.
    pub fn lines(&self) -> impl Iterator<Item = &[u8]> {
        self.bytes
            .split(|b| b == &b'\n')
            .filter(|line| !line.is_empty())
    }

    /// Return an iterator over the files of the entry.
    pub fn files(&self) -> impl Iterator<Item = Result<&HgPath, HgError>> {
        self.lines().filter(|line| !line.is_empty()).map(|line| {
            let pos =
                line.iter().position(|x| x == &b'\0').ok_or_else(|| {
                    HgError::corrupted("manifest line should contain \\0")
                })?;
            Ok(HgPath::new(&line[..pos]))
        })
    }

    /// Return an iterator over the files of the entry.
    pub fn files_with_nodes(
        &self,
    ) -> impl Iterator<Item = Result<(&HgPath, &[u8]), HgError>> {
        self.lines().filter(|line| !line.is_empty()).map(|line| {
            let pos =
                line.iter().position(|x| x == &b'\0').ok_or_else(|| {
                    HgError::corrupted("manifest line should contain \\0")
                })?;
            let hash_start = pos + 1;
            let hash_end = hash_start + 40;
            Ok((HgPath::new(&line[..pos]), &line[hash_start..hash_end]))
        })
    }

    /// If the given path is in this manifest, return its filelog node ID
    pub fn find_file(&self, path: &HgPath) -> Result<Option<Node>, HgError> {
        // TODO: use binary search instead of linear scan. This may involve
        // building (and caching) an index of the byte indicex of each manifest
        // line.
        for entry in self.files_with_nodes() {
            let (manifest_path, node) = entry?;
            if manifest_path == path {
                return Ok(Some(Node::from_hex_for_repo(node)?));
            }
        }
        Ok(None)
    }
}

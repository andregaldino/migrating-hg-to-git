use crate::errors::HgError;
use crate::repo::Repo;
use crate::revlog::node::NULL_NODE;
use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::Revision;
use crate::revlog::{Node, NodePrefix};

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
        Ok(ChangelogRevisionData { bytes })
    }

    pub fn node_from_rev(&self, rev: Revision) -> Option<&Node> {
        self.revlog.node_from_rev(rev)
    }
}

/// `Changelog` entry which knows how to interpret the `changelog` data bytes.
#[derive(Debug)]
pub struct ChangelogRevisionData {
    /// The data bytes of the `changelog` entry.
    bytes: Vec<u8>,
}

impl ChangelogRevisionData {
    /// Return an iterator over the lines of the entry.
    pub fn lines(&self) -> impl Iterator<Item = &[u8]> {
        self.bytes
            .split(|b| b == &b'\n')
            .filter(|line| !line.is_empty())
    }

    /// Return the node id of the `manifest` referenced by this `changelog`
    /// entry.
    pub fn manifest_node(&self) -> Result<Node, HgError> {
        match self.lines().next() {
            None => Ok(NULL_NODE),
            Some(x) => Node::from_hex_for_repo(x),
        }
    }
}

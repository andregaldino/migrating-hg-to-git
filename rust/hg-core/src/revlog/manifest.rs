use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::Revision;
use crate::utils::hg_path::HgPath;
use std::path::PathBuf;

/// A specialized `Revlog` to work with `manifest` data format.
pub struct Manifest {
    /// The generic `revlog` format.
    revlog: Revlog,
}

impl Manifest {
    /// Open the `manifest` of a repository given by its root.
    pub fn open(root: &PathBuf) -> Result<Self, RevlogError> {
        let index_file = root.join(".hg/store/00manifest.i");
        let revlog = Revlog::open(&index_file)?;
        Ok(Self { revlog })
    }

    /// Return the `ManifestEntry` of a given node id.
    pub fn get_node(&self, node: &[u8]) -> Result<ManifestEntry, RevlogError> {
        let rev = self.revlog.get_node_rev(node)?;
        self.get_rev(rev)
    }

    /// Return the `ManifestEntry` of a given node revision.
    pub fn get_rev(
        &self,
        rev: Revision,
    ) -> Result<ManifestEntry, RevlogError> {
        let bytes = self.revlog.get_rev_data(rev)?;
        Ok(ManifestEntry { bytes })
    }
}

/// `Manifest` entry which knows how to interpret the `manifest` data bytes.
#[derive(Debug)]
pub struct ManifestEntry {
    bytes: Vec<u8>,
}

impl ManifestEntry {
    /// Return an iterator over the lines of the entry.
    pub fn lines(&self) -> impl Iterator<Item = &[u8]> {
        self.bytes
            .split(|b| b == &b'\n')
            .filter(|line| !line.is_empty())
    }

    /// Return an iterator over the files of the entry.
    pub fn files(&self) -> impl Iterator<Item = &HgPath> {
        self.lines().filter(|line| !line.is_empty()).map(|line| {
            let pos = line
                .iter()
                .position(|x| x == &b'\0')
                .expect("manifest line should contain \\0");
            HgPath::new(&line[..pos])
        })
    }

    /// Return an iterator over the files of the entry.
    pub fn files_with_nodes(&self) -> impl Iterator<Item = (&HgPath, &[u8])> {
        self.lines().filter(|line| !line.is_empty()).map(|line| {
            let pos = line
                .iter()
                .position(|x| x == &b'\0')
                .expect("manifest line should contain \\0");
            let hash_start = pos + 1;
            let hash_end = hash_start + 40;
            (HgPath::new(&line[..pos]), &line[hash_start..hash_end])
        })
    }
}

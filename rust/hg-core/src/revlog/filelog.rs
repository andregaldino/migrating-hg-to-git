use crate::errors::HgError;
use crate::repo::Repo;
use crate::revlog::path_encode::path_encode;
use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::NodePrefix;
use crate::revlog::Revision;
use crate::utils::files::get_path_from_bytes;
use crate::utils::hg_path::HgPath;
use crate::utils::SliceExt;
use std::path::PathBuf;

/// A specialized `Revlog` to work with file data logs.
pub struct Filelog {
    /// The generic `revlog` format.
    revlog: Revlog,
}

impl Filelog {
    pub fn open(repo: &Repo, file_path: &HgPath) -> Result<Self, HgError> {
        let index_path = store_path(file_path, b".i");
        let data_path = store_path(file_path, b".d");
        let revlog = Revlog::open(repo, index_path, Some(&data_path))?;
        Ok(Self { revlog })
    }

    /// The given node ID is that of the file as found in a manifest, not of a
    /// changeset.
    pub fn data_for_node(
        &self,
        file_node: impl Into<NodePrefix>,
    ) -> Result<FilelogEntry, RevlogError> {
        let file_rev = self.revlog.rev_from_node(file_node.into())?;
        self.data_for_rev(file_rev)
    }

    /// The given revision is that of the file as found in a manifest, not of a
    /// changeset.
    pub fn data_for_rev(
        &self,
        file_rev: Revision,
    ) -> Result<FilelogEntry, RevlogError> {
        let data: Vec<u8> = self.revlog.get_rev_data(file_rev)?;
        Ok(FilelogEntry(data.into()))
    }
}

fn store_path(hg_path: &HgPath, suffix: &[u8]) -> PathBuf {
    let encoded_bytes =
        path_encode(&[b"data/", hg_path.as_bytes(), suffix].concat());
    get_path_from_bytes(&encoded_bytes).into()
}

pub struct FilelogEntry(Vec<u8>);

impl FilelogEntry {
    /// Split into metadata and data
    pub fn split(&self) -> Result<(Option<&[u8]>, &[u8]), HgError> {
        const DELIMITER: &[u8; 2] = &[b'\x01', b'\n'];

        if let Some(rest) = self.0.drop_prefix(DELIMITER) {
            if let Some((metadata, data)) = rest.split_2_by_slice(DELIMITER) {
                Ok((Some(metadata), data))
            } else {
                Err(HgError::corrupted(
                    "Missing metadata end delimiter in filelog entry",
                ))
            }
        } else {
            Ok((None, &self.0))
        }
    }

    /// Returns the file contents at this revision, stripped of any metadata
    pub fn data(&self) -> Result<&[u8], HgError> {
        let (_metadata, data) = self.split()?;
        Ok(data)
    }

    /// Consume the entry, and convert it into data, discarding any metadata,
    /// if present.
    pub fn into_data(self) -> Result<Vec<u8>, HgError> {
        if let (Some(_metadata), data) = self.split()? {
            Ok(data.to_owned())
        } else {
            Ok(self.0)
        }
    }
}

use crate::errors::HgError;
use crate::repo::Repo;
use crate::revlog::path_encode::path_encode;
use crate::revlog::revlog::RevlogEntry;
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
        let revlog = Revlog::open(
            &repo.store_vfs(),
            index_path,
            Some(&data_path),
            false,
        )?;
        Ok(Self { revlog })
    }

    /// The given node ID is that of the file as found in a filelog, not of a
    /// changeset.
    pub fn data_for_node(
        &self,
        file_node: impl Into<NodePrefix>,
    ) -> Result<FilelogRevisionData, RevlogError> {
        let file_rev = self.revlog.rev_from_node(file_node.into())?;
        self.data_for_rev(file_rev)
    }

    /// The given revision is that of the file as found in a filelog, not of a
    /// changeset.
    pub fn data_for_rev(
        &self,
        file_rev: Revision,
    ) -> Result<FilelogRevisionData, RevlogError> {
        let data: Vec<u8> = self.revlog.get_rev_data(file_rev)?.into_owned();
        Ok(FilelogRevisionData(data.into()))
    }

    /// The given node ID is that of the file as found in a filelog, not of a
    /// changeset.
    pub fn entry_for_node(
        &self,
        file_node: impl Into<NodePrefix>,
    ) -> Result<FilelogEntry, RevlogError> {
        let file_rev = self.revlog.rev_from_node(file_node.into())?;
        self.entry_for_rev(file_rev)
    }

    /// The given revision is that of the file as found in a filelog, not of a
    /// changeset.
    pub fn entry_for_rev(
        &self,
        file_rev: Revision,
    ) -> Result<FilelogEntry, RevlogError> {
        Ok(FilelogEntry(self.revlog.get_entry(file_rev)?))
    }
}

fn store_path(hg_path: &HgPath, suffix: &[u8]) -> PathBuf {
    let encoded_bytes =
        path_encode(&[b"data/", hg_path.as_bytes(), suffix].concat());
    get_path_from_bytes(&encoded_bytes).into()
}

pub struct FilelogEntry<'a>(RevlogEntry<'a>);

impl FilelogEntry<'_> {
    /// `self.data()` can be expensive, with decompression and delta
    /// resolution.
    ///
    /// *Without* paying this cost, based on revlog index information
    /// including `RevlogEntry::uncompressed_len`:
    ///
    /// * Returns `true` if the length that `self.data().file_data().len()`
    ///   would return is definitely **not equal** to `other_len`.
    /// * Returns `false` if available information is inconclusive.
    pub fn file_data_len_not_equal_to(&self, other_len: u64) -> bool {
        // Relevant code that implement this behavior in Python code:
        // basefilectx.cmp, filelog.size, storageutil.filerevisioncopied,
        // revlog.size, revlog.rawsize

        // Let’s call `file_data_len` what would be returned by
        // `self.data().file_data().len()`.

        if self.0.is_censored() {
            let file_data_len = 0;
            return other_len != file_data_len;
        }

        if self.0.has_length_affecting_flag_processor() {
            // We can’t conclude anything about `file_data_len`.
            return false;
        }

        // Revlog revisions (usually) have metadata for the size of
        // their data after decompression and delta resolution
        // as would be returned by `Revlog::get_rev_data`.
        //
        // For filelogs this is the file’s contents preceded by an optional
        // metadata block.
        let uncompressed_len = if let Some(l) = self.0.uncompressed_len() {
            l as u64
        } else {
            // The field was set to -1, the actual uncompressed len is unknown.
            // We need to decompress to say more.
            return false;
        };
        // `uncompressed_len = file_data_len + optional_metadata_len`,
        // so `file_data_len <= uncompressed_len`.
        if uncompressed_len < other_len {
            // Transitively, `file_data_len < other_len`.
            // So `other_len != file_data_len` definitely.
            return true;
        }

        if uncompressed_len == other_len + 4 {
            // It’s possible that `file_data_len == other_len` with an empty
            // metadata block (2 start marker bytes + 2 end marker bytes).
            // This happens when there wouldn’t otherwise be metadata, but
            // the first 2 bytes of file data happen to match a start marker
            // and would be ambiguous.
            return false;
        }

        if !self.0.has_p1() {
            // There may or may not be copy metadata, so we can’t deduce more
            // about `file_data_len` without computing file data.
            return false;
        }

        // Filelog ancestry is not meaningful in the way changelog ancestry is.
        // It only provides hints to delta generation.
        // p1 and p2 are set to null when making a copy or rename since
        // contents are likely unrelatedto what might have previously existed
        // at the destination path.
        //
        // Conversely, since here p1 is non-null, there is no copy metadata.
        // Note that this reasoning may be invalidated in the presence of
        // merges made by some previous versions of Mercurial that
        // swapped p1 and p2. See <https://bz.mercurial-scm.org/show_bug.cgi?id=6528>
        // and `tests/test-issue6528.t`.
        //
        // Since copy metadata is currently the only kind of metadata
        // kept in revlog data of filelogs,
        // this `FilelogEntry` does not have such metadata:
        let file_data_len = uncompressed_len;

        return file_data_len != other_len;
    }

    pub fn data(&self) -> Result<FilelogRevisionData, HgError> {
        Ok(FilelogRevisionData(self.0.data()?.into_owned()))
    }
}

/// The data for one revision in a filelog, uncompressed and delta-resolved.
pub struct FilelogRevisionData(Vec<u8>);

impl FilelogRevisionData {
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
    pub fn file_data(&self) -> Result<&[u8], HgError> {
        let (_metadata, data) = self.split()?;
        Ok(data)
    }

    /// Consume the entry, and convert it into data, discarding any metadata,
    /// if present.
    pub fn into_file_data(self) -> Result<Vec<u8>, HgError> {
        if let (Some(_metadata), data) = self.split()? {
            Ok(data.to_owned())
        } else {
            Ok(self.0)
        }
    }
}

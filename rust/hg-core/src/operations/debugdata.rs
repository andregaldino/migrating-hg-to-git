// debugdata.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::repo::Repo;
use crate::revlog::revlog::{Revlog, RevlogError};

/// Kind of data to debug
#[derive(Debug, Copy, Clone)]
pub enum DebugDataKind {
    Changelog,
    Manifest,
}

/// Error type for `debug_data`
#[derive(Debug)]
pub enum DebugDataError {
    /// Error when reading a `revlog` file.
    IoError(std::io::Error),
    /// The revision has not been found.
    InvalidRevision,
    /// Found more than one revision whose ID match the requested prefix
    AmbiguousPrefix,
    /// A `revlog` file is corrupted.
    CorruptedRevlog,
    /// The `revlog` format version is not supported.
    UnsuportedRevlogVersion(u16),
    /// The `revlog` data format is not supported.
    UnknowRevlogDataFormat(u8),
}

impl From<std::io::Error> for DebugDataError {
    fn from(err: std::io::Error) -> Self {
        DebugDataError::IoError(err)
    }
}

impl From<RevlogError> for DebugDataError {
    fn from(err: RevlogError) -> Self {
        match err {
            RevlogError::IoError(err) => DebugDataError::IoError(err),
            RevlogError::UnsuportedVersion(version) => {
                DebugDataError::UnsuportedRevlogVersion(version)
            }
            RevlogError::InvalidRevision => DebugDataError::InvalidRevision,
            RevlogError::AmbiguousPrefix => DebugDataError::AmbiguousPrefix,
            RevlogError::Corrupted => DebugDataError::CorruptedRevlog,
            RevlogError::UnknowDataFormat(format) => {
                DebugDataError::UnknowRevlogDataFormat(format)
            }
        }
    }
}

/// Dump the contents data of a revision.
pub fn debug_data(
    repo: &Repo,
    revset: &str,
    kind: DebugDataKind,
) -> Result<Vec<u8>, DebugDataError> {
    let index_file = match kind {
        DebugDataKind::Changelog => "00changelog.i",
        DebugDataKind::Manifest => "00manifest.i",
    };
    let revlog = Revlog::open(repo, index_file, None)?;
    let rev =
        crate::revset::resolve_rev_number_or_hex_prefix(revset, &revlog)?;
    let data = revlog.get_rev_data(rev)?;
    Ok(data)
}

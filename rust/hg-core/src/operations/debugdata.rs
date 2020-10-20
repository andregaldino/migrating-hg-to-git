// debugdata.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use super::find_root;
use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::Revision;

/// Kind of data to debug
#[derive(Debug, Copy, Clone)]
pub enum DebugDataKind {
    Changelog,
    Manifest,
}

/// Kind of error encountered by DebugData
#[derive(Debug)]
pub enum DebugDataErrorKind {
    FindRootError(find_root::FindRootError),
    /// Error when reading a `revlog` file.
    IoError(std::io::Error),
    /// The revision has not been found.
    InvalidRevision,
    /// A `revlog` file is corrupted.
    CorruptedRevlog,
    /// The `revlog` format version is not supported.
    UnsuportedRevlogVersion(u16),
    /// The `revlog` data format is not supported.
    UnknowRevlogDataFormat(u8),
}

/// A DebugData error
#[derive(Debug)]
pub struct DebugDataError {
    /// Kind of error encountered by DebugData
    pub kind: DebugDataErrorKind,
}

impl From<DebugDataErrorKind> for DebugDataError {
    fn from(kind: DebugDataErrorKind) -> Self {
        DebugDataError { kind }
    }
}

impl From<find_root::FindRootError> for DebugDataError {
    fn from(err: find_root::FindRootError) -> Self {
        let kind = DebugDataErrorKind::FindRootError(err);
        DebugDataError { kind }
    }
}

impl From<std::io::Error> for DebugDataError {
    fn from(err: std::io::Error) -> Self {
        let kind = DebugDataErrorKind::IoError(err);
        DebugDataError { kind }
    }
}

impl From<RevlogError> for DebugDataError {
    fn from(err: RevlogError) -> Self {
        match err {
            RevlogError::IoError(err) => DebugDataErrorKind::IoError(err),
            RevlogError::UnsuportedVersion(version) => {
                DebugDataErrorKind::UnsuportedRevlogVersion(version)
            }
            RevlogError::InvalidRevision => {
                DebugDataErrorKind::InvalidRevision
            }
            RevlogError::Corrupted => DebugDataErrorKind::CorruptedRevlog,
            RevlogError::UnknowDataFormat(format) => {
                DebugDataErrorKind::UnknowRevlogDataFormat(format)
            }
        }
        .into()
    }
}

/// Dump the contents data of a revision.
pub struct DebugData<'a> {
    /// Revision or hash of the revision.
    rev: &'a str,
    /// Kind of data to debug.
    kind: DebugDataKind,
}

impl<'a> DebugData<'a> {
    pub fn new(rev: &'a str, kind: DebugDataKind) -> Self {
        DebugData { rev, kind }
    }

    pub fn run(&mut self) -> Result<Vec<u8>, DebugDataError> {
        let rev = self
            .rev
            .parse::<Revision>()
            .or(Err(DebugDataErrorKind::InvalidRevision))?;

        let root = find_root::FindRoot::new().run()?;
        let index_file = match self.kind {
            DebugDataKind::Changelog => root.join(".hg/store/00changelog.i"),
            DebugDataKind::Manifest => root.join(".hg/store/00manifest.i"),
        };
        let revlog = Revlog::open(&index_file)?;
        let data = revlog.get_rev_data(rev)?;

        Ok(data)
    }
}

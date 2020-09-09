// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate::parsers::parse_dirstate;
use crate::utils::hg_path::HgPath;
use crate::{DirstateParseError, EntryState};
use rayon::prelude::*;
use std::convert::From;
use std::fmt;
use std::fs;
use std::ops::Deref;
use std::path::{Path, PathBuf};

/// Kind of error encountered by `ListDirstateTrackedFiles`
#[derive(Debug)]
pub enum ListDirstateTrackedFilesErrorKind {
    /// Error when reading the `dirstate` file
    IoError(std::io::Error),
    /// Error when parsing the `dirstate` file
    ParseError(DirstateParseError),
}

/// A `ListDirstateTrackedFiles` error
#[derive(Debug)]
pub struct ListDirstateTrackedFilesError {
    /// Kind of error encountered by `ListDirstateTrackedFiles`
    pub kind: ListDirstateTrackedFilesErrorKind,
}

impl std::error::Error for ListDirstateTrackedFilesError {}

impl fmt::Display for ListDirstateTrackedFilesError {
    fn fmt(&self, _f: &mut fmt::Formatter<'_>) -> fmt::Result {
        unimplemented!()
    }
}

impl From<ListDirstateTrackedFilesErrorKind>
    for ListDirstateTrackedFilesError
{
    fn from(kind: ListDirstateTrackedFilesErrorKind) -> Self {
        ListDirstateTrackedFilesError { kind }
    }
}

impl From<std::io::Error> for ListDirstateTrackedFilesError {
    fn from(err: std::io::Error) -> Self {
        let kind = ListDirstateTrackedFilesErrorKind::IoError(err);
        ListDirstateTrackedFilesError { kind }
    }
}

/// List files under Mercurial control in the working directory
/// by reading the dirstate
pub struct ListDirstateTrackedFiles {
    /// The `dirstate` content.
    content: Vec<u8>,
}

impl ListDirstateTrackedFiles {
    pub fn new(root: &PathBuf) -> Result<Self, ListDirstateTrackedFilesError> {
        let dirstate = root.join(".hg/dirstate");
        let content = fs::read(&dirstate)?;
        Ok(Self { content })
    }

    pub fn run(
        &mut self,
    ) -> Result<Vec<&HgPath>, ListDirstateTrackedFilesError> {
        let (_, entries, _) = parse_dirstate(&self.content)
            .map_err(ListDirstateTrackedFilesErrorKind::ParseError)?;
        let mut files: Vec<&HgPath> = entries
            .into_iter()
            .filter_map(|(path, entry)| match entry.state {
                EntryState::Removed => None,
                _ => Some(path),
            })
            .collect();
        files.par_sort_unstable();
        Ok(files)
    }
}

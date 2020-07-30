// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use super::find_root;
use crate::dirstate::parsers::parse_dirstate;
use crate::utils::hg_path::HgPath;
use crate::{DirstateParseError, EntryState};
use rayon::prelude::*;
use std::convert::From;
use std::fmt;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Kind of error encoutered by ListTrackedFiles
#[derive(Debug)]
pub enum ListTrackedFilesErrorKind {
    ParseError(DirstateParseError),
}

/// A ListTrackedFiles error
#[derive(Debug)]
pub struct ListTrackedFilesError {
    /// Kind of error encoutered by ListTrackedFiles
    pub kind: ListTrackedFilesErrorKind,
}

impl std::error::Error for ListTrackedFilesError {}

impl fmt::Display for ListTrackedFilesError {
    fn fmt(&self, _f: &mut fmt::Formatter<'_>) -> fmt::Result {
        unimplemented!()
    }
}

impl From<ListTrackedFilesErrorKind> for ListTrackedFilesError {
    fn from(kind: ListTrackedFilesErrorKind) -> Self {
        ListTrackedFilesError { kind }
    }
}

/// List files under Mercurial control in the working directory
pub struct ListTrackedFiles {
    root: PathBuf,
}

impl ListTrackedFiles {
    pub fn new() -> Result<Self, find_root::FindRootError> {
        let root = find_root::FindRoot::new().run()?;
        Ok(ListTrackedFiles { root })
    }

    /// Load the tracked files data from disk
    pub fn load(&self) -> Result<ListDirstateTrackedFiles, io::Error> {
        let dirstate = &self.root.join(".hg/dirstate");
        let content = fs::read(&dirstate)?;
        Ok(ListDirstateTrackedFiles { content })
    }

    /// Returns the repository root directory
    /// TODO I think this is a crutch that creates a dependency that should not
    /// be there. Operations that need the root of the repository should get
    /// it themselves, probably in a lazy fashion. But this would make the
    /// current series even larger, so this is simplified for now.
    pub fn get_root(&self) -> &Path {
        &self.root
    }
}

/// List files under Mercurial control in the working directory
/// by reading the dirstate
pub struct ListDirstateTrackedFiles {
    content: Vec<u8>,
}

impl ListDirstateTrackedFiles {
    pub fn run(&self) -> Result<Vec<&HgPath>, ListTrackedFilesError> {
        let (_, entries, _) = parse_dirstate(&self.content)
            .map_err(ListTrackedFilesErrorKind::ParseError)?;
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

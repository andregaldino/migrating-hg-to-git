// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate::parsers::parse_dirstate;
use crate::repo::Repo;
use crate::revlog::changelog::Changelog;
use crate::revlog::manifest::{Manifest, ManifestEntry};
use crate::revlog::node::Node;
use crate::revlog::revlog::RevlogError;
use crate::utils::hg_path::HgPath;
use crate::{DirstateParseError, EntryState};
use rayon::prelude::*;
use std::convert::From;

/// Error type for `Dirstate` methods
#[derive(Debug, derive_more::From)]
pub enum ListDirstateTrackedFilesError {
    /// Error when reading the `dirstate` file
    IoError(std::io::Error),
    /// Error when parsing the `dirstate` file
    ParseError(DirstateParseError),
}

/// List files under Mercurial control in the working directory
/// by reading the dirstate
pub struct Dirstate {
    /// The `dirstate` content.
    content: Vec<u8>,
}

impl Dirstate {
    pub fn new(repo: &Repo) -> Result<Self, ListDirstateTrackedFilesError> {
        let content = repo.hg_vfs().read("dirstate")?;
        Ok(Self { content })
    }

    pub fn tracked_files(
        &self,
    ) -> Result<Vec<&HgPath>, ListDirstateTrackedFilesError> {
        let (_, entries, _) = parse_dirstate(&self.content)
            .map_err(ListDirstateTrackedFilesError::ParseError)?;
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

/// Error type `list_rev_tracked_files`
#[derive(Debug)]
pub enum ListRevTrackedFilesError {
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

impl From<RevlogError> for ListRevTrackedFilesError {
    fn from(err: RevlogError) -> Self {
        match err {
            RevlogError::IoError(err) => {
                ListRevTrackedFilesError::IoError(err)
            }
            RevlogError::UnsuportedVersion(version) => {
                ListRevTrackedFilesError::UnsuportedRevlogVersion(version)
            }
            RevlogError::InvalidRevision => {
                ListRevTrackedFilesError::InvalidRevision
            }
            RevlogError::AmbiguousPrefix => {
                ListRevTrackedFilesError::AmbiguousPrefix
            }
            RevlogError::Corrupted => {
                ListRevTrackedFilesError::CorruptedRevlog
            }
            RevlogError::UnknowDataFormat(format) => {
                ListRevTrackedFilesError::UnknowRevlogDataFormat(format)
            }
        }
    }
}

/// List files under Mercurial control at a given revision.
pub fn list_rev_tracked_files(
    repo: &Repo,
    revset: &str,
) -> Result<FilesForRev, ListRevTrackedFilesError> {
    let rev = crate::revset::resolve_single(revset, repo)?;
    let changelog = Changelog::open(repo)?;
    let manifest = Manifest::open(repo)?;
    let changelog_entry = changelog.get_rev(rev)?;
    let manifest_node = Node::from_hex(&changelog_entry.manifest_node()?)
        .or(Err(ListRevTrackedFilesError::CorruptedRevlog))?;
    let manifest_entry = manifest.get_node(manifest_node.into())?;
    Ok(FilesForRev(manifest_entry))
}

pub struct FilesForRev(ManifestEntry);

impl FilesForRev {
    pub fn iter(&self) -> impl Iterator<Item = &HgPath> {
        self.0.files()
    }
}

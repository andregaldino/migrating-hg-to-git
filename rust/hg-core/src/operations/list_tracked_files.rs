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
use crate::revlog::node::{Node, NodePrefix};
use crate::revlog::revlog::RevlogError;
use crate::revlog::Revision;
use crate::utils::hg_path::HgPath;
use crate::{DirstateParseError, EntryState};
use rayon::prelude::*;
use std::convert::From;

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

/// Kind of error encountered by `ListRevTrackedFiles`
#[derive(Debug)]
pub enum ListRevTrackedFilesErrorKind {
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

/// A `ListRevTrackedFiles` error
#[derive(Debug)]
pub struct ListRevTrackedFilesError {
    /// Kind of error encountered by `ListRevTrackedFiles`
    pub kind: ListRevTrackedFilesErrorKind,
}

impl From<ListRevTrackedFilesErrorKind> for ListRevTrackedFilesError {
    fn from(kind: ListRevTrackedFilesErrorKind) -> Self {
        ListRevTrackedFilesError { kind }
    }
}

impl From<RevlogError> for ListRevTrackedFilesError {
    fn from(err: RevlogError) -> Self {
        match err {
            RevlogError::IoError(err) => {
                ListRevTrackedFilesErrorKind::IoError(err)
            }
            RevlogError::UnsuportedVersion(version) => {
                ListRevTrackedFilesErrorKind::UnsuportedRevlogVersion(version)
            }
            RevlogError::InvalidRevision => {
                ListRevTrackedFilesErrorKind::InvalidRevision
            }
            RevlogError::AmbiguousPrefix => {
                ListRevTrackedFilesErrorKind::AmbiguousPrefix
            }
            RevlogError::Corrupted => {
                ListRevTrackedFilesErrorKind::CorruptedRevlog
            }
            RevlogError::UnknowDataFormat(format) => {
                ListRevTrackedFilesErrorKind::UnknowRevlogDataFormat(format)
            }
        }
        .into()
    }
}

/// List files under Mercurial control at a given revision.
pub fn list_rev_tracked_files(
    repo: &Repo,
    rev: &str,
) -> Result<FilesForRev, ListRevTrackedFilesError> {
    let changelog = Changelog::open(repo)?;
    let manifest = Manifest::open(repo)?;

    let changelog_entry = match rev.parse::<Revision>() {
        Ok(rev) => changelog.get_rev(rev)?,
        _ => {
            let changelog_node = NodePrefix::from_hex(&rev)
                .or(Err(ListRevTrackedFilesErrorKind::InvalidRevision))?;
            changelog.get_node(changelog_node)?
        }
    };
    let manifest_node = Node::from_hex(&changelog_entry.manifest_node()?)
        .or(Err(ListRevTrackedFilesErrorKind::CorruptedRevlog))?;
    let manifest_entry = manifest.get_node(manifest_node.into())?;
    Ok(FilesForRev(manifest_entry))
}

pub struct FilesForRev(ManifestEntry);

impl FilesForRev {
    pub fn iter(&self) -> impl Iterator<Item = &HgPath> {
        self.0.files()
    }
}

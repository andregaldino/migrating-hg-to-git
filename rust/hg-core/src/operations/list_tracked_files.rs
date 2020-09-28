// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate::parsers::parse_dirstate;
use crate::revlog::changelog::Changelog;
use crate::revlog::manifest::{Manifest, ManifestEntry};
use crate::revlog::revlog::RevlogError;
use crate::revlog::Revision;
use crate::utils::hg_path::HgPath;
use crate::{DirstateParseError, EntryState};
use rayon::prelude::*;
use std::convert::From;
use std::fs;
use std::path::PathBuf;

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

/// Kind of error encountered by `ListRevTrackedFiles`
#[derive(Debug)]
pub enum ListRevTrackedFilesErrorKind {
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
pub struct ListRevTrackedFiles<'a> {
    /// The revision to list the files from.
    rev: &'a str,
    /// The changelog file
    changelog: Changelog,
    /// The manifest file
    manifest: Manifest,
    /// The manifest entry corresponding to the revision.
    ///
    /// Used to hold the owner of the returned references.
    manifest_entry: Option<ManifestEntry>,
}

impl<'a> ListRevTrackedFiles<'a> {
    pub fn new(
        root: &PathBuf,
        rev: &'a str,
    ) -> Result<Self, ListRevTrackedFilesError> {
        let changelog = Changelog::open(&root)?;
        let manifest = Manifest::open(&root)?;

        Ok(Self {
            rev,
            changelog,
            manifest,
            manifest_entry: None,
        })
    }

    pub fn run(
        &mut self,
    ) -> Result<impl Iterator<Item = &HgPath>, ListRevTrackedFilesError> {
        let changelog_entry = match self.rev.parse::<Revision>() {
            Ok(rev) => self.changelog.get_rev(rev)?,
            _ => {
                let changelog_node = hex::decode(&self.rev)
                    .or(Err(ListRevTrackedFilesErrorKind::InvalidRevision))?;
                self.changelog.get_node(&changelog_node)?
            }
        };
        let manifest_node = hex::decode(&changelog_entry.manifest_node()?)
            .or(Err(ListRevTrackedFilesErrorKind::CorruptedRevlog))?;

        self.manifest_entry = Some(self.manifest.get_node(&manifest_node)?);

        if let Some(ref manifest_entry) = self.manifest_entry {
            Ok(manifest_entry.files())
        } else {
            panic!(
                "manifest entry should have been stored in self.manifest_node to ensure its lifetime since references are returned from it"
            )
        }
    }
}

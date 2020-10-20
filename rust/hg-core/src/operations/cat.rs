// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use std::convert::From;
use std::path::PathBuf;

use crate::revlog::changelog::Changelog;
use crate::revlog::manifest::{Manifest, ManifestEntry};
use crate::revlog::path_encode::path_encode;
use crate::revlog::revlog::Revlog;
use crate::revlog::revlog::RevlogError;
use crate::revlog::Revision;
use crate::utils::hg_path::HgPathBuf;

/// Kind of error encountered by `CatRev`
#[derive(Debug)]
pub enum CatRevErrorKind {
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

/// A `CatRev` error
#[derive(Debug)]
pub struct CatRevError {
    /// Kind of error encountered by `CatRev`
    pub kind: CatRevErrorKind,
}

impl From<CatRevErrorKind> for CatRevError {
    fn from(kind: CatRevErrorKind) -> Self {
        CatRevError { kind }
    }
}

impl From<RevlogError> for CatRevError {
    fn from(err: RevlogError) -> Self {
        match err {
            RevlogError::IoError(err) => CatRevErrorKind::IoError(err),
            RevlogError::UnsuportedVersion(version) => {
                CatRevErrorKind::UnsuportedRevlogVersion(version)
            }
            RevlogError::InvalidRevision => CatRevErrorKind::InvalidRevision,
            RevlogError::Corrupted => CatRevErrorKind::CorruptedRevlog,
            RevlogError::UnknowDataFormat(format) => {
                CatRevErrorKind::UnknowRevlogDataFormat(format)
            }
        }
        .into()
    }
}

/// List files under Mercurial control at a given revision.
pub struct CatRev<'a> {
    root: &'a PathBuf,
    /// The revision to cat the files from.
    rev: &'a str,
    /// The files to output.
    files: &'a [HgPathBuf],
    /// The changelog file
    changelog: Changelog,
    /// The manifest file
    manifest: Manifest,
    /// The manifest entry corresponding to the revision.
    ///
    /// Used to hold the owner of the returned references.
    manifest_entry: Option<ManifestEntry>,
}

impl<'a> CatRev<'a> {
    pub fn new(
        root: &'a PathBuf,
        rev: &'a str,
        files: &'a [HgPathBuf],
    ) -> Result<Self, CatRevError> {
        let changelog = Changelog::open(&root)?;
        let manifest = Manifest::open(&root)?;
        let manifest_entry = None;

        Ok(Self {
            root,
            rev,
            files,
            changelog,
            manifest,
            manifest_entry,
        })
    }

    pub fn run(&mut self) -> Result<Vec<u8>, CatRevError> {
        let changelog_entry = match self.rev.parse::<Revision>() {
            Ok(rev) => self.changelog.get_rev(rev)?,
            _ => {
                let changelog_node = hex::decode(&self.rev)
                    .map_err(|_| CatRevErrorKind::InvalidRevision)?;
                self.changelog.get_node(&changelog_node)?
            }
        };
        let manifest_node = hex::decode(&changelog_entry.manifest_node()?)
            .map_err(|_| CatRevErrorKind::CorruptedRevlog)?;

        self.manifest_entry = Some(self.manifest.get_node(&manifest_node)?);
        if let Some(ref manifest_entry) = self.manifest_entry {
            let mut bytes = vec![];

            for (manifest_file, node_bytes) in
                manifest_entry.files_with_nodes()
            {
                for cat_file in self.files.iter() {
                    if cat_file.as_bytes() == manifest_file.as_bytes() {
                        let encoded_bytes =
                            path_encode(manifest_file.as_bytes());
                        let revlog_index_string = format!(
                            ".hg/store/data/{}.i",
                            String::from_utf8_lossy(&encoded_bytes),
                        );
                        let revlog_index_path =
                            self.root.join(&revlog_index_string);
                        let file_log = Revlog::open(&revlog_index_path)?;
                        let file_node = hex::decode(&node_bytes)
                            .map_err(|_| CatRevErrorKind::CorruptedRevlog)?;
                        let file_rev = file_log.get_node_rev(&file_node)?;
                        let data = file_log.get_rev_data(file_rev)?;
                        bytes.extend(data);
                    }
                }
            }

            Ok(bytes)
        } else {
            unreachable!("manifest_entry should have been stored");
        }
    }
}

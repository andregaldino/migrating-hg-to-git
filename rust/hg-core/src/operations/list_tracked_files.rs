// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate::parsers::parse_dirstate;
use crate::errors::{HgError, IoResultExt};
use crate::repo::Repo;
use crate::revlog::changelog::Changelog;
use crate::revlog::manifest::{Manifest, ManifestEntry};
use crate::revlog::node::Node;
use crate::revlog::revlog::RevlogError;
use crate::utils::hg_path::HgPath;
use crate::EntryState;
use rayon::prelude::*;

/// List files under Mercurial control in the working directory
/// by reading the dirstate
pub struct Dirstate {
    /// The `dirstate` content.
    content: Vec<u8>,
}

impl Dirstate {
    pub fn new(repo: &Repo) -> Result<Self, HgError> {
        let content = repo
            .hg_vfs()
            .read("dirstate")
            // TODO: this will be more accurate when we use `HgError` in
            // `Vfs::read`.
            .for_file("dirstate".as_ref())?;
        Ok(Self { content })
    }

    pub fn tracked_files(&self) -> Result<Vec<&HgPath>, HgError> {
        let (_, entries, _) = parse_dirstate(&self.content)?;
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

/// List files under Mercurial control at a given revision.
pub fn list_rev_tracked_files(
    repo: &Repo,
    revset: &str,
) -> Result<FilesForRev, RevlogError> {
    let rev = crate::revset::resolve_single(revset, repo)?;
    let changelog = Changelog::open(repo)?;
    let manifest = Manifest::open(repo)?;
    let changelog_entry = changelog.get_rev(rev)?;
    let manifest_node = Node::from_hex(&changelog_entry.manifest_node()?)
        .map_err(|_| RevlogError::Corrupted)?;
    let manifest_entry = manifest.get_node(manifest_node.into())?;
    Ok(FilesForRev(manifest_entry))
}

pub struct FilesForRev(ManifestEntry);

impl FilesForRev {
    pub fn iter(&self) -> impl Iterator<Item = &HgPath> {
        self.0.files()
    }
}

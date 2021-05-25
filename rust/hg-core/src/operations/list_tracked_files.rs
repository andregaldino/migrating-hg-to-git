// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate::parsers::parse_dirstate_entries;
use crate::dirstate_tree::on_disk::for_each_tracked_path;
use crate::errors::HgError;
use crate::repo::Repo;
use crate::revlog::changelog::Changelog;
use crate::revlog::manifest::{Manifest, ManifestEntry};
use crate::revlog::node::Node;
use crate::revlog::revlog::RevlogError;
use crate::utils::hg_path::HgPath;
use crate::DirstateError;
use rayon::prelude::*;

/// List files under Mercurial control in the working directory
/// by reading the dirstate
pub struct Dirstate {
    /// The `dirstate` content.
    content: Vec<u8>,
    dirstate_v2: bool,
}

impl Dirstate {
    pub fn new(repo: &Repo) -> Result<Self, HgError> {
        Ok(Self {
            content: repo.hg_vfs().read("dirstate")?,
            dirstate_v2: repo.has_dirstate_v2(),
        })
    }

    pub fn tracked_files(&self) -> Result<Vec<&HgPath>, DirstateError> {
        let mut files = Vec::new();
        if !self.content.is_empty() {
            if self.dirstate_v2 {
                for_each_tracked_path(&self.content, |path| files.push(path))?
            } else {
                let _parents = parse_dirstate_entries(
                    &self.content,
                    |path, entry, _copy_source| {
                        if entry.state.is_tracked() {
                            files.push(path)
                        }
                        Ok(())
                    },
                )?;
            }
        }
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
    let manifest_node =
        Node::from_hex_for_repo(&changelog_entry.manifest_node()?)?;
    let manifest_entry = manifest.get_node(manifest_node.into())?;
    Ok(FilesForRev(manifest_entry))
}

pub struct FilesForRev(ManifestEntry);

impl FilesForRev {
    pub fn iter(&self) -> impl Iterator<Item = &HgPath> {
        self.0.files()
    }
}

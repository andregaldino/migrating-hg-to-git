// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate::parsers::parse_dirstate_entries;
use crate::dirstate_tree::on_disk::{for_each_tracked_path, read_docket};
use crate::errors::HgError;
use crate::repo::Repo;
use crate::revlog::manifest::Manifest;
use crate::revlog::revlog::RevlogError;
use crate::utils::hg_path::HgPath;
use crate::DirstateError;
use rayon::prelude::*;

/// List files under Mercurial control in the working directory
/// by reading the dirstate
pub struct Dirstate {
    /// The `dirstate` content.
    content: Vec<u8>,
    v2_metadata: Option<Vec<u8>>,
}

impl Dirstate {
    pub fn new(repo: &Repo) -> Result<Self, HgError> {
        let mut content = repo.hg_vfs().read("dirstate")?;
        let v2_metadata = if repo.has_dirstate_v2() {
            let docket = read_docket(&content)?;
            let meta = docket.tree_metadata().to_vec();
            content = repo.hg_vfs().read(docket.data_filename())?;
            Some(meta)
        } else {
            None
        };
        Ok(Self {
            content,
            v2_metadata,
        })
    }

    pub fn tracked_files(&self) -> Result<Vec<&HgPath>, DirstateError> {
        let mut files = Vec::new();
        if !self.content.is_empty() {
            if let Some(meta) = &self.v2_metadata {
                for_each_tracked_path(&self.content, meta, |path| {
                    files.push(path)
                })?
            } else {
                let _parents = parse_dirstate_entries(
                    &self.content,
                    |path, entry, _copy_source| {
                        if entry.tracked() {
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
    Ok(FilesForRev(repo.manifest_for_rev(rev)?))
}

pub struct FilesForRev(Manifest);

impl FilesForRev {
    pub fn iter(&self) -> impl Iterator<Item = Result<&HgPath, HgError>> {
        self.0.iter().map(|entry| Ok(entry?.path))
    }
}

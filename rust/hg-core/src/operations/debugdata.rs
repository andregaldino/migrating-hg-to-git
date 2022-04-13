// debugdata.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::repo::Repo;
use crate::requirements;
use crate::revlog::revlog::{Revlog, RevlogError};

/// Kind of data to debug
#[derive(Debug, Copy, Clone)]
pub enum DebugDataKind {
    Changelog,
    Manifest,
}

/// Dump the contents data of a revision.
pub fn debug_data(
    repo: &Repo,
    revset: &str,
    kind: DebugDataKind,
) -> Result<Vec<u8>, RevlogError> {
    let index_file = match kind {
        DebugDataKind::Changelog => "00changelog.i",
        DebugDataKind::Manifest => "00manifest.i",
    };
    let use_nodemap = repo
        .requirements()
        .contains(requirements::NODEMAP_REQUIREMENT);
    let revlog =
        Revlog::open(&repo.store_vfs(), index_file, None, use_nodemap)?;
    let rev =
        crate::revset::resolve_rev_number_or_hex_prefix(revset, &revlog)?;
    let data = revlog.get_rev_data(rev)?;
    Ok(data.into_owned())
}

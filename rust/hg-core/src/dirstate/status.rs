// status.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Rust implementation of dirstate.status (dirstate.py).
//! It is currently missing a lot of functionality compared to the Python one
//! and will only be triggered in narrow cases.

use crate::utils::files::HgMetadata;
use crate::utils::hg_path::{hg_path_to_path_buf, HgPathBuf};
use crate::{DirstateEntry, DirstateMap, EntryState};
use rayon::prelude::*;
use std::path::Path;

// Stat all entries in the `DirstateMap` and return their new metadata.
pub fn stat_dmap_entries(
    dmap: &DirstateMap,
    root_dir: impl AsRef<Path> + Sync,
) -> std::io::Result<Vec<(HgPathBuf, Option<HgMetadata>)>> {
    dmap.par_iter()
        .filter_map(
            // Getting file metadata is costly, so we don't do it if the
            // file is already present in the results, hence `filter_map`
            |(filename, _)| -> Option<
                std::io::Result<(HgPathBuf, Option<HgMetadata>)>
            > {
                let meta = match hg_path_to_path_buf(filename) {
                    Ok(p) => root_dir.as_ref().join(p).symlink_metadata(),
                    Err(e) => return Some(Err(e.into())),
                };

                Some(match meta {
                    Ok(ref m)
                        if !(m.file_type().is_file()
                            || m.file_type().is_symlink()) =>
                    {
                        Ok((filename.to_owned(), None))
                    }
                    Ok(m) => Ok((
                        filename.to_owned(),
                        Some(HgMetadata::from_metadata(m)),
                    )),
                    Err(ref e)
                        if e.kind() == std::io::ErrorKind::NotFound
                            || e.raw_os_error() == Some(20) =>
                    {
                        // Rust does not yet have an `ErrorKind` for
                        // `NotADirectory` (errno 20)
                        // It happens if the dirstate contains `foo/bar` and
                        // foo is not a directory
                        Ok((filename.to_owned(), None))
                    }
                    Err(e) => Err(e),
                })
            },
        )
        .collect()
}

pub struct StatusResult {
    pub modified: Vec<HgPathBuf>,
    pub added: Vec<HgPathBuf>,
    pub removed: Vec<HgPathBuf>,
    pub deleted: Vec<HgPathBuf>,
    pub clean: Vec<HgPathBuf>,
    // TODO ignored
    // TODO unknown
}

fn build_response(
    dmap: &DirstateMap,
    list_clean: bool,
    last_normal_time: i64,
    check_exec: bool,
    results: Vec<(HgPathBuf, Option<HgMetadata>)>,
) -> (Vec<HgPathBuf>, StatusResult) {
    let mut lookup = vec![];
    let mut modified = vec![];
    let mut added = vec![];
    let mut removed = vec![];
    let mut deleted = vec![];
    let mut clean = vec![];

    for (filename, metadata_option) in results.into_iter() {
        let DirstateEntry {
            state,
            mode,
            mtime,
            size,
        } = match dmap.get(&filename) {
            None => {
                continue;
            }
            Some(e) => *e,
        };

        match metadata_option {
            None => {
                match state {
                    EntryState::Normal
                    | EntryState::Merged
                    | EntryState::Added => deleted.push(filename),
                    EntryState::Removed => removed.push(filename),
                    _ => {}
                };
            }
            Some(HgMetadata {
                st_mode,
                st_size,
                st_mtime,
                ..
            }) => {
                match state {
                    EntryState::Normal => {
                        // Dates and times that are outside the 31-bit signed
                        // range are compared modulo 2^31. This should prevent
                        // it from behaving badly with very large files or
                        // corrupt dates while still having a high probability
                        // of detecting changes. (issue2608)
                        let range_mask = 0x7fffffff;

                        let size_changed = (size != st_size as i32)
                            && size != (st_size as i32 & range_mask);
                        let mode_changed = (mode ^ st_mode as i32) & 0o100
                            != 0o000
                            && check_exec;
                        if size >= 0
                            && (size_changed || mode_changed)
                            || size == -2  // other parent
                            || dmap.copy_map.contains_key(&filename)
                        {
                            modified.push(filename);
                        } else if mtime != st_mtime as i32
                            && mtime != (st_mtime as i32 & range_mask)
                        {
                            lookup.push(filename);
                        } else if st_mtime == last_normal_time {
                            // the file may have just been marked as normal and
                            // it may have changed in the same second without
                            // changing its size. This can happen if we quickly
                            // do multiple commits. Force lookup, so we don't
                            // miss such a racy file change.
                            lookup.push(filename);
                        } else if list_clean {
                            clean.push(filename);
                        }
                    }
                    EntryState::Merged => modified.push(filename),
                    EntryState::Added => added.push(filename),
                    EntryState::Removed => removed.push(filename),
                    EntryState::Unknown => {}
                }
            }
        }
    }

    (
        lookup,
        StatusResult {
            modified,
            added,
            removed,
            deleted,
            clean,
        },
    )
}

pub fn status(
    dmap: &DirstateMap,
    root_dir: impl AsRef<Path> + Sync + Copy,
    list_clean: bool,
    last_normal_time: i64,
    check_exec: bool,
) -> std::io::Result<(Vec<HgPathBuf>, StatusResult)> {
    let results = stat_dmap_entries(&dmap, root_dir)?;

    Ok(build_response(
        &dmap,
        list_clean,
        last_normal_time,
        check_exec,
        results,
    ))
}

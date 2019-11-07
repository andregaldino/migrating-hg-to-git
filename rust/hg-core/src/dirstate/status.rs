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
use crate::utils::hg_path::{hg_path_to_path_buf, HgPath};
use crate::{CopyMap, DirstateEntry, DirstateMap, EntryState};
use rayon::prelude::*;
use std::path::Path;

/// Marker enum used to dispatch new status entries into the right collections.
/// Is similar to `crate::EntryState`, but represents the transient state of
/// entries during the lifetime of a command.
enum Dispatch {
    Unsure,
    Modified,
    Added,
    Removed,
    Deleted,
    Clean,
    Unknown,
}

/// The file corresponding to the dirstate entry was found on the filesystem.
fn dispatch_found(
    filename: impl AsRef<HgPath>,
    entry: DirstateEntry,
    metadata: HgMetadata,
    copy_map: &CopyMap,
    check_exec: bool,
    list_clean: bool,
    last_normal_time: i64,
) -> Dispatch {
    let DirstateEntry {
        state,
        mode,
        mtime,
        size,
    } = entry;

    let HgMetadata {
        st_mode,
        st_size,
        st_mtime,
        ..
    } = metadata;

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
            let mode_changed =
                (mode ^ st_mode as i32) & 0o100 != 0o000 && check_exec;
            if size >= 0
                            && (size_changed || mode_changed)
                            || size == -2  // other parent
                            || copy_map.contains_key(filename.as_ref())
            {
                Dispatch::Modified
            } else if mtime != st_mtime as i32
                && mtime != (st_mtime as i32 & range_mask)
            {
                Dispatch::Unsure
            } else if st_mtime == last_normal_time {
                // the file may have just been marked as normal and
                // it may have changed in the same second without
                // changing its size. This can happen if we quickly
                // do multiple commits. Force lookup, so we don't
                // miss such a racy file change.
                Dispatch::Unsure
            } else if list_clean {
                Dispatch::Clean
            } else {
                Dispatch::Unknown
            }
        }
        EntryState::Merged => Dispatch::Modified,
        EntryState::Added => Dispatch::Added,
        EntryState::Removed => Dispatch::Removed,
        EntryState::Unknown => Dispatch::Unknown,
    }
}

/// The file corresponding to this Dirstate entry is missing.
fn dispatch_missing(state: EntryState) -> Dispatch {
    match state {
        // File was removed from the filesystem during commands
        EntryState::Normal | EntryState::Merged | EntryState::Added => {
            Dispatch::Deleted
        }
        // File was removed, everything is normal
        EntryState::Removed => Dispatch::Removed,
        // File is unknown to Mercurial, everything is normal
        EntryState::Unknown => Dispatch::Unknown,
    }
}

/// Stat all entries in the `DirstateMap` and mark them for dispatch into
/// the relevant collections.
fn stat_dmap_entries(
    dmap: &DirstateMap,
    root_dir: impl AsRef<Path> + Sync + Send,
    check_exec: bool,
    list_clean: bool,
    last_normal_time: i64,
) -> impl ParallelIterator<Item = std::io::Result<(&HgPath, Dispatch)>> {
    dmap.par_iter().map(move |(filename, entry)| {
        let filename: &HgPath = filename;
        let filename_as_path = hg_path_to_path_buf(filename)?;
        let meta = root_dir.as_ref().join(filename_as_path).symlink_metadata();

        match meta {
            Ok(ref m)
                if !(m.file_type().is_file()
                    || m.file_type().is_symlink()) =>
            {
                Ok((filename, dispatch_missing(entry.state)))
            }
            Ok(m) => Ok((
                filename,
                dispatch_found(
                    filename,
                    *entry,
                    HgMetadata::from_metadata(m),
                    &dmap.copy_map,
                    check_exec,
                    list_clean,
                    last_normal_time,
                ),
            )),
            Err(ref e)
                if e.kind() == std::io::ErrorKind::NotFound
                    || e.raw_os_error() == Some(20) =>
            {
                // Rust does not yet have an `ErrorKind` for
                // `NotADirectory` (errno 20)
                // It happens if the dirstate contains `foo/bar` and
                // foo is not a directory
                Ok((filename, dispatch_missing(entry.state)))
            }
            Err(e) => Err(e),
        }
    })
}

pub struct StatusResult<'a> {
    pub modified: Vec<&'a HgPath>,
    pub added: Vec<&'a HgPath>,
    pub removed: Vec<&'a HgPath>,
    pub deleted: Vec<&'a HgPath>,
    pub clean: Vec<&'a HgPath>,
    // TODO ignored
    // TODO unknown
}

fn build_response(
    results: Vec<(&HgPath, Dispatch)>,
) -> (Vec<&HgPath>, StatusResult) {
    let mut lookup = vec![];
    let mut modified = vec![];
    let mut added = vec![];
    let mut removed = vec![];
    let mut deleted = vec![];
    let mut clean = vec![];

    for (filename, dispatch) in results.into_iter() {
        match dispatch {
            Dispatch::Unknown => {}
            Dispatch::Unsure => lookup.push(filename),
            Dispatch::Modified => modified.push(filename),
            Dispatch::Added => added.push(filename),
            Dispatch::Removed => removed.push(filename),
            Dispatch::Deleted => deleted.push(filename),
            Dispatch::Clean => clean.push(filename),
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
    root_dir: impl AsRef<Path> + Sync + Send + Copy,
    list_clean: bool,
    last_normal_time: i64,
    check_exec: bool,
) -> std::io::Result<(Vec<&HgPath>, StatusResult)> {
    let results: std::io::Result<_> = stat_dmap_entries(
        &dmap,
        root_dir,
        check_exec,
        list_clean,
        last_normal_time,
    )
    .collect();

    Ok(build_response(results?))
}

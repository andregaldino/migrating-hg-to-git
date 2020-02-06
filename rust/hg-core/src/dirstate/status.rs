// status.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Rust implementation of dirstate.status (dirstate.py).
//! It is currently missing a lot of functionality compared to the Python one
//! and will only be triggered in narrow cases.

use crate::{
    dirstate::SIZE_FROM_OTHER_PARENT,
    matchers::Matcher,
    utils::{
        files::HgMetadata,
        hg_path::{
            hg_path_to_path_buf, os_string_to_hg_path_buf, HgPath, HgPathBuf,
        },
    },
    CopyMap, DirstateEntry, DirstateMap, EntryState,
};
use rayon::prelude::*;
use std::collections::HashSet;
use std::fs::{read_dir, DirEntry};
use std::path::Path;

/// Wrong type of file from a `BadMatch`
/// Note: a lot of those don't exist on all platforms.
#[derive(Debug)]
pub enum BadType {
    CharacterDevice,
    BlockDevice,
    FIFO,
    Socket,
    Directory,
    Unknown,
}

/// Was explicitly matched but cannot be found/accessed
#[derive(Debug)]
pub enum BadMatch {
    OsError(i32),
    BadType(BadType),
}

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
    Ignored,
    /// Empty dispatch, the file is not worth listing
    None,
    /// Was explicitly matched but cannot be found/accessed
    Bad(BadMatch),
    Directory {
        /// True if the directory used to be a file in the dmap so we can say
        /// that it's been removed.
        was_file: bool,
    },
}

type IoResult<T> = std::io::Result<T>;

/// Dates and times that are outside the 31-bit signed range are compared
/// modulo 2^31. This should prevent hg from behaving badly with very large
/// files or corrupt dates while still having a high probability of detecting
/// changes. (issue2608)
/// TODO I haven't found a way of having `b` be `Into<i32>`, since `From<u64>`
/// is not defined for `i32`, and there is no `As` trait. This forces the
/// caller to cast `b` as `i32`.
fn mod_compare(a: i32, b: i32) -> bool {
    a & i32::max_value() != b & i32::max_value()
}

/// Return a sorted list containing information about the entries
/// in the directory.
///
/// * `skip_dot_hg` - Return an empty vec if `path` contains a `.hg` directory
fn list_directory(
    path: impl AsRef<Path>,
    skip_dot_hg: bool,
) -> std::io::Result<Vec<(HgPathBuf, DirEntry)>> {
    let mut results = vec![];
    let entries = read_dir(path.as_ref())?;

    for entry in entries {
        let entry = entry?;
        let filename = os_string_to_hg_path_buf(entry.file_name())?;
        let file_type = entry.file_type()?;
        if skip_dot_hg && filename.as_bytes() == b".hg" && file_type.is_dir() {
            return Ok(vec![]);
        } else {
            results.push((HgPathBuf::from(filename), entry))
        }
    }

    results.sort_unstable_by_key(|e| e.0.clone());
    Ok(results)
}

/// The file corresponding to the dirstate entry was found on the filesystem.
fn dispatch_found(
    filename: impl AsRef<HgPath>,
    entry: DirstateEntry,
    metadata: HgMetadata,
    copy_map: &CopyMap,
    options: StatusOptions,
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
            let size_changed = mod_compare(size, st_size as i32);
            let mode_changed =
                (mode ^ st_mode as i32) & 0o100 != 0o000 && options.check_exec;
            let metadata_changed = size >= 0 && (size_changed || mode_changed);
            let other_parent = size == SIZE_FROM_OTHER_PARENT;
            if metadata_changed
                || other_parent
                || copy_map.contains_key(filename.as_ref())
            {
                Dispatch::Modified
            } else if mod_compare(mtime, st_mtime as i32) {
                Dispatch::Unsure
            } else if st_mtime == options.last_normal_time {
                // the file may have just been marked as normal and
                // it may have changed in the same second without
                // changing its size. This can happen if we quickly
                // do multiple commits. Force lookup, so we don't
                // miss such a racy file change.
                Dispatch::Unsure
            } else if options.list_clean {
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

/// Get stat data about the files explicitly specified by match.
/// TODO subrepos
fn walk_explicit<'a>(
    files: &'a HashSet<&HgPath>,
    dmap: &'a DirstateMap,
    root_dir: impl AsRef<Path> + Sync + Send,
    options: StatusOptions,
) -> impl ParallelIterator<Item = IoResult<(&'a HgPath, Dispatch)>> {
    files.par_iter().filter_map(move |filename| {
        // TODO normalization
        let normalized = filename.as_ref();

        let buf = match hg_path_to_path_buf(normalized) {
            Ok(x) => x,
            Err(e) => return Some(Err(e.into())),
        };
        let target = root_dir.as_ref().join(buf);
        let st = target.symlink_metadata();
        match st {
            Ok(meta) => {
                let file_type = meta.file_type();
                if file_type.is_file() || file_type.is_symlink() {
                    if let Some(entry) = dmap.get(normalized) {
                        return Some(Ok((
                            normalized,
                            dispatch_found(
                                &normalized,
                                *entry,
                                HgMetadata::from_metadata(meta),
                                &dmap.copy_map,
                                options,
                            ),
                        )));
                    }
                } else {
                    if dmap.contains_key(normalized) {
                        return Some(Ok((normalized, Dispatch::Removed)));
                    }
                }
            }
            Err(_) => {
                if let Some(entry) = dmap.get(normalized) {
                    return Some(Ok((
                        normalized,
                        dispatch_missing(entry.state),
                    )));
                }
            }
        };
        None
    })
}

#[derive(Debug, Copy, Clone)]
pub struct StatusOptions {
    /// Remember the most recent modification timeslot for status, to make
    /// sure we won't miss future size-preserving file content modifications
    /// that happen within the same timeslot.
    pub last_normal_time: i64,
    /// Whether we are on a filesystem with UNIX-like exec flags
    pub check_exec: bool,
    pub list_clean: bool,
}

/// Stat all entries in the `DirstateMap` and mark them for dispatch into
/// the relevant collections.
fn stat_dmap_entries(
    dmap: &DirstateMap,
    root_dir: impl AsRef<Path> + Sync + Send,
    options: StatusOptions,
) -> impl ParallelIterator<Item = IoResult<(&HgPath, Dispatch)>> {
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
                    options,
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

pub struct DirstateStatus<'a> {
    pub modified: Vec<&'a HgPath>,
    pub added: Vec<&'a HgPath>,
    pub removed: Vec<&'a HgPath>,
    pub deleted: Vec<&'a HgPath>,
    pub clean: Vec<&'a HgPath>,
    pub ignored: Vec<&'a HgPath>,
    pub unknown: Vec<&'a HgPath>,
    pub bad: Vec<(&'a HgPath, BadMatch)>,
}

fn build_response<'a>(
    results: impl IntoIterator<Item = IoResult<(&'a HgPath, Dispatch)>>,
) -> IoResult<(Vec<&'a HgPath>, DirstateStatus<'a>)> {
    let mut lookup = vec![];
    let mut modified = vec![];
    let mut added = vec![];
    let mut removed = vec![];
    let mut deleted = vec![];
    let mut clean = vec![];
    let mut ignored = vec![];
    let mut unknown = vec![];
    let mut bad = vec![];

    for res in results.into_iter() {
        let (filename, dispatch) = res?;
        match dispatch {
            Dispatch::Unknown => unknown.push(filename),
            Dispatch::Unsure => lookup.push(filename),
            Dispatch::Modified => modified.push(filename),
            Dispatch::Added => added.push(filename),
            Dispatch::Removed => removed.push(filename),
            Dispatch::Deleted => deleted.push(filename),
            Dispatch::Clean => clean.push(filename),
            Dispatch::Ignored => ignored.push(filename),
            Dispatch::None => {}
            Dispatch::Bad(reason) => bad.push((filename, reason)),
            Dispatch::Directory { .. } => {}
        }
    }

    Ok((
        lookup,
        DirstateStatus {
            modified,
            added,
            removed,
            deleted,
            clean,
            ignored,
            unknown,
            bad,
        },
    ))
}

pub fn status<'a: 'c, 'b: 'c, 'c>(
    dmap: &'a DirstateMap,
    matcher: &'b impl Matcher,
    root_dir: impl AsRef<Path> + Sync + Send + Copy,
    options: StatusOptions,
) -> IoResult<(Vec<&'c HgPath>, DirstateStatus<'c>)> {
    let files = matcher.file_set();
    let mut results = vec![];
    if let Some(files) = files {
        results.par_extend(walk_explicit(&files, &dmap, root_dir, options));
    }

    if !matcher.is_exact() {
        let stat_results = stat_dmap_entries(&dmap, root_dir, options);
        results.par_extend(stat_results);
    }

    build_response(results)
}

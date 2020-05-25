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
    filepatterns::PatternFileWarning,
    matchers::{get_ignore_function, Matcher, VisitChildrenSet},
    utils::{
        files::{find_dirs, HgMetadata},
        hg_path::{
            hg_path_to_path_buf, os_string_to_hg_path_buf, HgPath, HgPathBuf,
            HgPathError,
        },
        path_auditor::PathAuditor,
    },
    CopyMap, DirstateEntry, DirstateMap, EntryState, FastHashMap,
    PatternError,
};
use lazy_static::lazy_static;
use micro_timer::timed;
use rayon::prelude::*;
use std::{
    borrow::Cow,
    collections::HashSet,
    fs::{read_dir, DirEntry},
    io::ErrorKind,
    ops::Deref,
    path::{Path, PathBuf},
};

/// Wrong type of file from a `BadMatch`
/// Note: a lot of those don't exist on all platforms.
#[derive(Debug, Copy, Clone)]
pub enum BadType {
    CharacterDevice,
    BlockDevice,
    FIFO,
    Socket,
    Directory,
    Unknown,
}

impl ToString for BadType {
    fn to_string(&self) -> String {
        match self {
            BadType::CharacterDevice => "character device",
            BadType::BlockDevice => "block device",
            BadType::FIFO => "fifo",
            BadType::Socket => "socket",
            BadType::Directory => "directory",
            BadType::Unknown => "unknown",
        }
        .to_string()
    }
}

/// Was explicitly matched but cannot be found/accessed
#[derive(Debug, Copy, Clone)]
pub enum BadMatch {
    OsError(i32),
    BadType(BadType),
}

/// Marker enum used to dispatch new status entries into the right collections.
/// Is similar to `crate::EntryState`, but represents the transient state of
/// entries during the lifetime of a command.
#[derive(Debug, Copy, Clone)]
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
/// `Box<dyn Trait>` is syntactic sugar for `Box<dyn Trait, 'static>`, so add
/// an explicit lifetime here to not fight `'static` bounds "out of nowhere".
type IgnoreFnType<'a> = Box<dyn for<'r> Fn(&'r HgPath) -> bool + Sync + 'a>;

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
                Dispatch::None
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

lazy_static! {
    static ref DEFAULT_WORK: HashSet<&'static HgPath> = {
        let mut h = HashSet::new();
        h.insert(HgPath::new(b""));
        h
    };
}

/// Get stat data about the files explicitly specified by match.
/// TODO subrepos
#[timed]
fn walk_explicit<'a>(
    files: Option<&'a HashSet<&HgPath>>,
    dmap: &'a DirstateMap,
    root_dir: impl AsRef<Path> + Sync + Send + 'a,
    options: StatusOptions,
    traversed_sender: crossbeam::Sender<HgPathBuf>,
) -> impl ParallelIterator<Item = IoResult<(&'a HgPath, Dispatch)>> {
    files
        .unwrap_or(&DEFAULT_WORK)
        .par_iter()
        .map(move |filename| {
            // TODO normalization
            let normalized = filename.as_ref();

            let buf = match hg_path_to_path_buf(normalized) {
                Ok(x) => x,
                Err(e) => return Some(Err(e.into())),
            };
            let target = root_dir.as_ref().join(buf);
            let st = target.symlink_metadata();
            let in_dmap = dmap.get(normalized);
            match st {
                Ok(meta) => {
                    let file_type = meta.file_type();
                    return if file_type.is_file() || file_type.is_symlink() {
                        if let Some(entry) = in_dmap {
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
                        Some(Ok((normalized, Dispatch::Unknown)))
                    } else {
                        if file_type.is_dir() {
                            if options.collect_traversed_dirs {
                                // The receiver always outlives the sender,
                                // so unwrap.
                                traversed_sender
                                    .send(normalized.to_owned())
                                    .unwrap()
                            }
                            Some(Ok((
                                normalized,
                                Dispatch::Directory {
                                    was_file: in_dmap.is_some(),
                                },
                            )))
                        } else {
                            Some(Ok((
                                normalized,
                                Dispatch::Bad(BadMatch::BadType(
                                    // TODO do more than unknown
                                    // Support for all `BadType` variant
                                    // varies greatly between platforms.
                                    // So far, no tests check the type and
                                    // this should be good enough for most
                                    // users.
                                    BadType::Unknown,
                                )),
                            )))
                        }
                    };
                }
                Err(_) => {
                    if let Some(entry) = in_dmap {
                        return Some(Ok((
                            normalized,
                            dispatch_missing(entry.state),
                        )));
                    }
                }
            };
            None
        })
        .flatten()
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
    pub list_unknown: bool,
    pub list_ignored: bool,
    /// Whether to collect traversed dirs for applying a callback later.
    /// Used by `hg purge` for example.
    pub collect_traversed_dirs: bool,
}

/// Dispatch a single entry (file, folder, symlink...) found during `traverse`.
/// If the entry is a folder that needs to be traversed, it will be handled
/// in a separate thread.
fn handle_traversed_entry<'a>(
    scope: &rayon::Scope<'a>,
    files_sender: &'a crossbeam::Sender<IoResult<(HgPathBuf, Dispatch)>>,
    matcher: &'a (impl Matcher + Sync),
    root_dir: impl AsRef<Path> + Sync + Send + Copy + 'a,
    dmap: &'a DirstateMap,
    old_results: &'a FastHashMap<Cow<HgPath>, Dispatch>,
    ignore_fn: &'a IgnoreFnType,
    dir_ignore_fn: &'a IgnoreFnType,
    options: StatusOptions,
    filename: HgPathBuf,
    dir_entry: DirEntry,
    traversed_sender: crossbeam::Sender<HgPathBuf>,
) -> IoResult<()> {
    let file_type = dir_entry.file_type()?;
    let entry_option = dmap.get(&filename);

    if filename.as_bytes() == b".hg" {
        // Could be a directory or a symlink
        return Ok(());
    }

    if file_type.is_dir() {
        handle_traversed_dir(
            scope,
            files_sender,
            matcher,
            root_dir,
            dmap,
            old_results,
            ignore_fn,
            dir_ignore_fn,
            options,
            entry_option,
            filename,
            traversed_sender,
        );
    } else if file_type.is_file() || file_type.is_symlink() {
        if let Some(entry) = entry_option {
            if matcher.matches_everything() || matcher.matches(&filename) {
                let metadata = dir_entry.metadata()?;
                files_sender
                    .send(Ok((
                        filename.to_owned(),
                        dispatch_found(
                            &filename,
                            *entry,
                            HgMetadata::from_metadata(metadata),
                            &dmap.copy_map,
                            options,
                        ),
                    )))
                    .unwrap();
            }
        } else if (matcher.matches_everything() || matcher.matches(&filename))
            && !ignore_fn(&filename)
        {
            if (options.list_ignored || matcher.exact_match(&filename))
                && dir_ignore_fn(&filename)
            {
                if options.list_ignored {
                    files_sender
                        .send(Ok((filename.to_owned(), Dispatch::Ignored)))
                        .unwrap();
                }
            } else {
                if options.list_unknown {
                    files_sender
                        .send(Ok((filename.to_owned(), Dispatch::Unknown)))
                        .unwrap();
                }
            }
        } else if ignore_fn(&filename) && options.list_ignored {
            files_sender
                .send(Ok((filename.to_owned(), Dispatch::Ignored)))
                .unwrap();
        }
    } else if let Some(entry) = entry_option {
        // Used to be a file or a folder, now something else.
        if matcher.matches_everything() || matcher.matches(&filename) {
            files_sender
                .send(Ok((filename.to_owned(), dispatch_missing(entry.state))))
                .unwrap();
        }
    }

    Ok(())
}

/// A directory was found in the filesystem and needs to be traversed
fn handle_traversed_dir<'a>(
    scope: &rayon::Scope<'a>,
    files_sender: &'a crossbeam::Sender<IoResult<(HgPathBuf, Dispatch)>>,
    matcher: &'a (impl Matcher + Sync),
    root_dir: impl AsRef<Path> + Sync + Send + Copy + 'a,
    dmap: &'a DirstateMap,
    old_results: &'a FastHashMap<Cow<HgPath>, Dispatch>,
    ignore_fn: &'a IgnoreFnType,
    dir_ignore_fn: &'a IgnoreFnType,
    options: StatusOptions,
    entry_option: Option<&'a DirstateEntry>,
    directory: HgPathBuf,
    traversed_sender: crossbeam::Sender<HgPathBuf>,
) {
    scope.spawn(move |_| {
        // Nested `if` until `rust-lang/rust#53668` is stable
        if let Some(entry) = entry_option {
            // Used to be a file, is now a folder
            if matcher.matches_everything() || matcher.matches(&directory) {
                files_sender
                    .send(Ok((
                        directory.to_owned(),
                        dispatch_missing(entry.state),
                    )))
                    .unwrap();
            }
        }
        // Do we need to traverse it?
        if !ignore_fn(&directory) || options.list_ignored {
            traverse_dir(
                files_sender,
                matcher,
                root_dir,
                dmap,
                directory,
                &old_results,
                ignore_fn,
                dir_ignore_fn,
                options,
                traversed_sender,
            )
            .unwrap_or_else(|e| files_sender.send(Err(e)).unwrap())
        }
    });
}

/// Decides whether the directory needs to be listed, and if so handles the
/// entries in a separate thread.
fn traverse_dir<'a>(
    files_sender: &crossbeam::Sender<IoResult<(HgPathBuf, Dispatch)>>,
    matcher: &'a (impl Matcher + Sync),
    root_dir: impl AsRef<Path> + Sync + Send + Copy,
    dmap: &'a DirstateMap,
    directory: impl AsRef<HgPath>,
    old_results: &FastHashMap<Cow<'a, HgPath>, Dispatch>,
    ignore_fn: &IgnoreFnType,
    dir_ignore_fn: &IgnoreFnType,
    options: StatusOptions,
    traversed_sender: crossbeam::Sender<HgPathBuf>,
) -> IoResult<()> {
    let directory = directory.as_ref();

    if options.collect_traversed_dirs {
        // The receiver always outlives the sender, so unwrap.
        traversed_sender.send(directory.to_owned()).unwrap()
    }

    let visit_entries = match matcher.visit_children_set(directory) {
        VisitChildrenSet::Empty => return Ok(()),
        VisitChildrenSet::This | VisitChildrenSet::Recursive => None,
        VisitChildrenSet::Set(set) => Some(set),
    };
    let buf = hg_path_to_path_buf(directory)?;
    let dir_path = root_dir.as_ref().join(buf);

    let skip_dot_hg = !directory.as_bytes().is_empty();
    let entries = match list_directory(dir_path, skip_dot_hg) {
        Err(e) => match e.kind() {
            ErrorKind::NotFound | ErrorKind::PermissionDenied => {
                files_sender
                    .send(Ok((
                        directory.to_owned(),
                        Dispatch::Bad(BadMatch::OsError(
                            // Unwrapping here is OK because the error always
                            // is a real os error
                            e.raw_os_error().unwrap(),
                        )),
                    )))
                    .unwrap();
                return Ok(());
            }
            _ => return Err(e),
        },
        Ok(entries) => entries,
    };

    rayon::scope(|scope| -> IoResult<()> {
        for (filename, dir_entry) in entries {
            if let Some(ref set) = visit_entries {
                if !set.contains(filename.deref()) {
                    continue;
                }
            }
            // TODO normalize
            let filename = if directory.is_empty() {
                filename.to_owned()
            } else {
                directory.join(&filename)
            };

            if !old_results.contains_key(filename.deref()) {
                handle_traversed_entry(
                    scope,
                    files_sender,
                    matcher,
                    root_dir,
                    dmap,
                    old_results,
                    ignore_fn,
                    dir_ignore_fn,
                    options,
                    filename,
                    dir_entry,
                    traversed_sender.clone(),
                )?;
            }
        }
        Ok(())
    })
}

/// Walk the working directory recursively to look for changes compared to the
/// current `DirstateMap`.
///
/// This takes a mutable reference to the results to account for the `extend`
/// in timings
#[timed]
fn traverse<'a>(
    matcher: &'a (impl Matcher + Sync),
    root_dir: impl AsRef<Path> + Sync + Send + Copy,
    dmap: &'a DirstateMap,
    path: impl AsRef<HgPath>,
    old_results: &FastHashMap<Cow<'a, HgPath>, Dispatch>,
    ignore_fn: &IgnoreFnType,
    dir_ignore_fn: &IgnoreFnType,
    options: StatusOptions,
    results: &mut Vec<(Cow<'a, HgPath>, Dispatch)>,
    traversed_sender: crossbeam::Sender<HgPathBuf>,
) -> IoResult<()> {
    let root_dir = root_dir.as_ref();

    // The traversal is done in parallel, so use a channel to gather entries.
    // `crossbeam::Sender` is `Sync`, while `mpsc::Sender` is not.
    let (files_transmitter, files_receiver) = crossbeam::channel::unbounded();

    traverse_dir(
        &files_transmitter,
        matcher,
        root_dir,
        &dmap,
        path,
        &old_results,
        &ignore_fn,
        &dir_ignore_fn,
        options,
        traversed_sender,
    )?;

    // Disconnect the channel so the receiver stops waiting
    drop(files_transmitter);

    // TODO don't collect. Find a way of replicating the behavior of
    // `itertools::process_results`, but for `rayon::ParallelIterator`
    let new_results: IoResult<Vec<(Cow<'a, HgPath>, Dispatch)>> =
        files_receiver
            .into_iter()
            .map(|item| {
                let (f, d) = item?;
                Ok((Cow::Owned(f), d))
            })
            .collect();

    results.par_extend(new_results?);

    Ok(())
}

/// Stat all entries in the `DirstateMap` and mark them for dispatch.
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
                if e.kind() == ErrorKind::NotFound
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

/// This takes a mutable reference to the results to account for the `extend`
/// in timings
#[timed]
fn extend_from_dmap<'a>(
    dmap: &'a DirstateMap,
    root_dir: impl AsRef<Path> + Sync + Send,
    options: StatusOptions,
    results: &mut Vec<(Cow<'a, HgPath>, Dispatch)>,
) {
    results.par_extend(
        stat_dmap_entries(dmap, root_dir, options)
            .flatten()
            .map(|(filename, dispatch)| (Cow::Borrowed(filename), dispatch)),
    );
}

#[derive(Debug)]
pub struct DirstateStatus<'a> {
    pub modified: Vec<Cow<'a, HgPath>>,
    pub added: Vec<Cow<'a, HgPath>>,
    pub removed: Vec<Cow<'a, HgPath>>,
    pub deleted: Vec<Cow<'a, HgPath>>,
    pub clean: Vec<Cow<'a, HgPath>>,
    pub ignored: Vec<Cow<'a, HgPath>>,
    pub unknown: Vec<Cow<'a, HgPath>>,
    pub bad: Vec<(Cow<'a, HgPath>, BadMatch)>,
    /// Only filled if `collect_traversed_dirs` is `true`
    pub traversed: Vec<HgPathBuf>,
}

#[timed]
fn build_response<'a>(
    results: impl IntoIterator<Item = (Cow<'a, HgPath>, Dispatch)>,
    traversed: Vec<HgPathBuf>,
) -> (Vec<Cow<'a, HgPath>>, DirstateStatus<'a>) {
    let mut lookup = vec![];
    let mut modified = vec![];
    let mut added = vec![];
    let mut removed = vec![];
    let mut deleted = vec![];
    let mut clean = vec![];
    let mut ignored = vec![];
    let mut unknown = vec![];
    let mut bad = vec![];

    for (filename, dispatch) in results.into_iter() {
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

    (
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
            traversed,
        },
    )
}

#[derive(Debug)]
pub enum StatusError {
    IO(std::io::Error),
    Path(HgPathError),
    Pattern(PatternError),
}

pub type StatusResult<T> = Result<T, StatusError>;

impl From<PatternError> for StatusError {
    fn from(e: PatternError) -> Self {
        StatusError::Pattern(e)
    }
}
impl From<HgPathError> for StatusError {
    fn from(e: HgPathError) -> Self {
        StatusError::Path(e)
    }
}
impl From<std::io::Error> for StatusError {
    fn from(e: std::io::Error) -> Self {
        StatusError::IO(e)
    }
}

impl ToString for StatusError {
    fn to_string(&self) -> String {
        match self {
            StatusError::IO(e) => e.to_string(),
            StatusError::Path(e) => e.to_string(),
            StatusError::Pattern(e) => e.to_string(),
        }
    }
}

/// This takes a mutable reference to the results to account for the `extend`
/// in timings
#[timed]
fn handle_unknowns<'a>(
    dmap: &'a DirstateMap,
    matcher: &(impl Matcher + Sync),
    root_dir: impl AsRef<Path> + Sync + Send + Copy,
    options: StatusOptions,
    results: &mut Vec<(Cow<'a, HgPath>, Dispatch)>,
) -> IoResult<()> {
    let to_visit: Vec<(&HgPath, &DirstateEntry)> = if results.is_empty()
        && matcher.matches_everything()
    {
        dmap.iter().map(|(f, e)| (f.deref(), e)).collect()
    } else {
        // Only convert to a hashmap if needed.
        let old_results: FastHashMap<_, _> = results.iter().cloned().collect();
        dmap.iter()
            .filter_map(move |(f, e)| {
                if !old_results.contains_key(f.deref()) && matcher.matches(f) {
                    Some((f.deref(), e))
                } else {
                    None
                }
            })
            .collect()
    };

    // We walked all dirs under the roots that weren't ignored, and
    // everything that matched was stat'ed and is already in results.
    // The rest must thus be ignored or under a symlink.
    let path_auditor = PathAuditor::new(root_dir);

    // TODO don't collect. Find a way of replicating the behavior of
    // `itertools::process_results`, but for `rayon::ParallelIterator`
    let new_results: IoResult<Vec<_>> = to_visit
        .into_par_iter()
        .filter_map(|(filename, entry)| -> Option<IoResult<_>> {
            // Report ignored items in the dmap as long as they are not
            // under a symlink directory.
            if path_auditor.check(filename) {
                // TODO normalize for case-insensitive filesystems
                let buf = match hg_path_to_path_buf(filename) {
                    Ok(x) => x,
                    Err(e) => return Some(Err(e.into())),
                };
                Some(Ok((
                    Cow::Borrowed(filename),
                    match root_dir.as_ref().join(&buf).symlink_metadata() {
                        // File was just ignored, no links, and exists
                        Ok(meta) => {
                            let metadata = HgMetadata::from_metadata(meta);
                            dispatch_found(
                                filename,
                                *entry,
                                metadata,
                                &dmap.copy_map,
                                options,
                            )
                        }
                        // File doesn't exist
                        Err(_) => dispatch_missing(entry.state),
                    },
                )))
            } else {
                // It's either missing or under a symlink directory which
                // we, in this case, report as missing.
                Some(Ok((
                    Cow::Borrowed(filename),
                    dispatch_missing(entry.state),
                )))
            }
        })
        .collect();

    results.par_extend(new_results?);

    Ok(())
}

/// Get the status of files in the working directory.
///
/// This is the current entry-point for `hg-core` and is realistically unusable
/// outside of a Python context because its arguments need to provide a lot of
/// information that will not be necessary in the future.
#[timed]
pub fn status<'a: 'c, 'b: 'c, 'c>(
    dmap: &'a DirstateMap,
    matcher: &'b (impl Matcher + Sync),
    root_dir: impl AsRef<Path> + Sync + Send + Copy + 'c,
    ignore_files: Vec<PathBuf>,
    options: StatusOptions,
) -> StatusResult<(
    (Vec<Cow<'c, HgPath>>, DirstateStatus<'c>),
    Vec<PatternFileWarning>,
)> {
    // Needs to outlive `dir_ignore_fn` since it's captured.
    let ignore_fn: IgnoreFnType;

    // Only involve real ignore mechanism if we're listing unknowns or ignored.
    let (dir_ignore_fn, warnings): (IgnoreFnType, _) = if options.list_ignored
        || options.list_unknown
    {
        let (ignore, warnings) = get_ignore_function(ignore_files, root_dir)?;

        ignore_fn = ignore;
        let dir_ignore_fn = Box::new(|dir: &_| {
            // Is the path or one of its ancestors ignored?
            if ignore_fn(dir) {
                true
            } else {
                for p in find_dirs(dir) {
                    if ignore_fn(p) {
                        return true;
                    }
                }
                false
            }
        });
        (dir_ignore_fn, warnings)
    } else {
        ignore_fn = Box::new(|&_| true);
        (Box::new(|&_| true), vec![])
    };

    let files = matcher.file_set();

    // `crossbeam::Sender` is `Sync`, while `mpsc::Sender` is not.
    let (traversed_sender, traversed_recv) = crossbeam::channel::unbounded();

    // Step 1: check the files explicitly mentioned by the user
    let explicit = walk_explicit(
        files,
        &dmap,
        root_dir,
        options,
        traversed_sender.clone(),
    );

    // Collect results into a `Vec` because we do very few lookups in most
    // cases.
    let (work, mut results): (Vec<_>, Vec<_>) = explicit
        .filter_map(Result::ok)
        .map(|(filename, dispatch)| (Cow::Borrowed(filename), dispatch))
        .partition(|(_, dispatch)| match dispatch {
            Dispatch::Directory { .. } => true,
            _ => false,
        });

    if !work.is_empty() {
        // Hashmaps are quite a bit slower to build than vecs, so only build it
        // if needed.
        let old_results = results.iter().cloned().collect();

        // Step 2: recursively check the working directory for changes if
        // needed
        for (dir, dispatch) in work {
            match dispatch {
                Dispatch::Directory { was_file } => {
                    if was_file {
                        results.push((dir.to_owned(), Dispatch::Removed));
                    }
                    if options.list_ignored
                        || options.list_unknown && !dir_ignore_fn(&dir)
                    {
                        traverse(
                            matcher,
                            root_dir,
                            &dmap,
                            &dir,
                            &old_results,
                            &ignore_fn,
                            &dir_ignore_fn,
                            options,
                            &mut results,
                            traversed_sender.clone(),
                        )?;
                    }
                }
                _ => unreachable!("There can only be directories in `work`"),
            }
        }
    }

    if !matcher.is_exact() {
        // Step 3: Check the remaining files from the dmap.
        // If a dmap file is not in results yet, it was either
        // a) not matched b) ignored, c) missing, or d) under a
        // symlink directory.

        if options.list_unknown {
            handle_unknowns(dmap, matcher, root_dir, options, &mut results)?;
        } else {
            // We may not have walked the full directory tree above, so stat
            // and check everything we missed.
            extend_from_dmap(&dmap, root_dir, options, &mut results);
        }
    }

    // Close the channel
    drop(traversed_sender);
    let traversed_dirs = traversed_recv.into_iter().collect();

    Ok((build_response(results, traversed_dirs), warnings))
}

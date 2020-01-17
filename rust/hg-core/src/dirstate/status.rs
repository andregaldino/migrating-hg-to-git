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
use rayon::prelude::*;
use std::collections::VecDeque;
use std::{
    borrow::Cow,
    collections::HashSet,
    fs::{read_dir, DirEntry},
    io::ErrorKind,
    ops::Deref,
    path::Path,
};

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
#[derive(Debug)]
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
fn walk_explicit<'a>(
    files: Option<&'a HashSet<&HgPath>>,
    dmap: &'a DirstateMap,
    root_dir: impl AsRef<Path> + Sync + Send + 'a,
    options: StatusOptions,
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
}

/// Dispatch a single file found during `traverse`.
/// If `file` is a folder that needs to be traversed, it will be pushed into
/// `work`.
fn traverse_worker<'a>(
    work: &mut VecDeque<HgPathBuf>,
    matcher: &impl Matcher,
    dmap: &DirstateMap,
    filename: impl AsRef<HgPath>,
    dir_entry: &DirEntry,
    ignore_fn: &impl for<'r> Fn(&'r HgPath) -> bool,
    dir_ignore_fn: &impl for<'r> Fn(&'r HgPath) -> bool,
    options: StatusOptions,
) -> Option<IoResult<(Cow<'a, HgPath>, Dispatch)>> {
    let file_type = match dir_entry.file_type() {
        Ok(x) => x,
        Err(e) => return Some(Err(e.into())),
    };
    let filename = filename.as_ref();
    let entry_option = dmap.get(filename);

    if file_type.is_dir() {
        // Do we need to traverse it?
        if !ignore_fn(&filename) || options.list_ignored {
            work.push_front(filename.to_owned());
        }
        // Nested `if` until `rust-lang/rust#53668` is stable
        if let Some(entry) = entry_option {
            // Used to be a file, is now a folder
            if matcher.matches_everything() || matcher.matches(&filename) {
                return Some(Ok((
                    Cow::Owned(filename.to_owned()),
                    dispatch_missing(entry.state),
                )));
            }
        }
    } else if file_type.is_file() || file_type.is_symlink() {
        if let Some(entry) = entry_option {
            if matcher.matches_everything() || matcher.matches(&filename) {
                let metadata = match dir_entry.metadata() {
                    Ok(x) => x,
                    Err(e) => return Some(Err(e.into())),
                };
                return Some(Ok((
                    Cow::Owned(filename.to_owned()),
                    dispatch_found(
                        &filename,
                        *entry,
                        HgMetadata::from_metadata(metadata),
                        &dmap.copy_map,
                        options,
                    ),
                )));
            }
        } else if (matcher.matches_everything() || matcher.matches(&filename))
            && !ignore_fn(&filename)
        {
            if (options.list_ignored || matcher.exact_match(&filename))
                && dir_ignore_fn(&filename)
            {
                if options.list_ignored {
                    return Some(Ok((
                        Cow::Owned(filename.to_owned()),
                        Dispatch::Ignored,
                    )));
                }
            } else {
                return Some(Ok((
                    Cow::Owned(filename.to_owned()),
                    Dispatch::Unknown,
                )));
            }
        }
    } else if let Some(entry) = entry_option {
        // Used to be a file or a folder, now something else.
        if matcher.matches_everything() || matcher.matches(&filename) {
            return Some(Ok((
                Cow::Owned(filename.to_owned()),
                dispatch_missing(entry.state),
            )));
        }
    }
    None
}

/// Walk the working directory recursively to look for changes compared to the
/// current `DirstateMap`.
fn traverse<'a>(
    matcher: &(impl Matcher + Sync),
    root_dir: impl AsRef<Path>,
    dmap: &DirstateMap,
    path: impl AsRef<HgPath>,
    old_results: FastHashMap<Cow<'a, HgPath>, Dispatch>,
    ignore_fn: &(impl for<'r> Fn(&'r HgPath) -> bool + Sync),
    dir_ignore_fn: &(impl for<'r> Fn(&'r HgPath) -> bool + Sync),
    options: StatusOptions,
) -> IoResult<FastHashMap<Cow<'a, HgPath>, Dispatch>> {
    let root_dir = root_dir.as_ref();
    let mut new_results = FastHashMap::default();

    let mut work = VecDeque::new();
    work.push_front(path.as_ref().to_owned());

    while let Some(ref directory) = work.pop_front() {
        if directory.as_bytes() == b".hg" {
            continue;
        }
        let visit_entries = match matcher.visit_children_set(directory) {
            VisitChildrenSet::Empty => continue,
            VisitChildrenSet::This | VisitChildrenSet::Recursive => None,
            VisitChildrenSet::Set(set) => Some(set),
        };
        let buf = hg_path_to_path_buf(directory)?;
        let dir_path = root_dir.join(buf);

        let skip_dot_hg = !directory.as_bytes().is_empty();
        let entries = match list_directory(dir_path, skip_dot_hg) {
            Err(e) => match e.kind() {
                ErrorKind::NotFound | ErrorKind::PermissionDenied => {
                    new_results.insert(
                        Cow::Owned(directory.to_owned()),
                        Dispatch::Bad(BadMatch::OsError(
                            // Unwrapping here is OK because the error always
                            // is a real os error
                            e.raw_os_error().unwrap(),
                        )),
                    );
                    continue;
                }
                _ => return Err(e),
            },
            Ok(entries) => entries,
        };

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
                if let Some((res, dispatch)) = traverse_worker(
                    &mut work,
                    matcher,
                    &dmap,
                    &filename,
                    &dir_entry,
                    &ignore_fn,
                    &dir_ignore_fn,
                    options,
                )
                .transpose()?
                {
                    new_results.insert(res, dispatch);
                }
            }
        }
    }

    new_results.extend(old_results.into_iter());

    Ok(new_results)
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

pub struct DirstateStatus<'a> {
    pub modified: Vec<Cow<'a, HgPath>>,
    pub added: Vec<Cow<'a, HgPath>>,
    pub removed: Vec<Cow<'a, HgPath>>,
    pub deleted: Vec<Cow<'a, HgPath>>,
    pub clean: Vec<Cow<'a, HgPath>>,
    pub ignored: Vec<Cow<'a, HgPath>>,
    pub unknown: Vec<Cow<'a, HgPath>>,
    pub bad: Vec<(Cow<'a, HgPath>, BadMatch)>,
}

fn build_response<'a>(
    results: impl IntoIterator<Item = (Cow<'a, HgPath>, Dispatch)>,
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
        },
    )
}

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

/// Get the status of files in the working directory.
///
/// This is the current entry-point for `hg-core` and is realistically unusable
/// outside of a Python context because its arguments need to provide a lot of
/// information that will not be necessary in the future.
pub fn status<'a: 'c, 'b: 'c, 'c>(
    dmap: &'a DirstateMap,
    matcher: &'b (impl Matcher + Sync),
    root_dir: impl AsRef<Path> + Sync + Send + Copy + 'c,
    ignore_files: &[impl AsRef<Path> + 'c],
    options: StatusOptions,
) -> StatusResult<(
    (Vec<Cow<'c, HgPath>>, DirstateStatus<'c>),
    Vec<PatternFileWarning>,
)> {
    let (ignore_fn, warnings) = get_ignore_function(&ignore_files, root_dir)?;

    // Is the path or one of its ancestors ignored?
    let dir_ignore_fn = |dir: &_| {
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
    };

    let files = matcher.file_set();

    // Step 1: check the files explicitly mentioned by the user
    let explicit = walk_explicit(files, &dmap, root_dir, options);
    let (work, mut results): (Vec<_>, FastHashMap<_, _>) = explicit
        .filter_map(Result::ok)
        .map(|(filename, dispatch)| (Cow::Borrowed(filename), dispatch))
        .partition(|(_, dispatch)| match dispatch {
            Dispatch::Directory { .. } => true,
            _ => false,
        });

    // Step 2: recursively check the working directory for changes if needed
    for (dir, dispatch) in work {
        match dispatch {
            Dispatch::Directory { was_file } => {
                if was_file {
                    results.insert(dir.to_owned(), Dispatch::Removed);
                }
                if options.list_ignored
                    || options.list_unknown && !dir_ignore_fn(&dir)
                {
                    results = traverse(
                        matcher,
                        root_dir,
                        &dmap,
                        &dir,
                        results,
                        &ignore_fn,
                        &dir_ignore_fn,
                        options,
                    )?;
                }
            }
            _ => unreachable!("There can only be directories in `work`"),
        }
    }

    if !matcher.is_exact() {
        // Step 3: Check the remaining files from the dmap.
        // If a dmap file is not in results yet, it was either
        // a) not matched b) ignored, c) missing, or d) under a
        // symlink directory.

        if options.list_unknown {
            let to_visit: Box<dyn Iterator<Item = (&HgPath, &DirstateEntry)>> =
                if results.is_empty() && matcher.matches_everything() {
                    Box::new(dmap.iter().map(|(f, e)| (f.deref(), e)))
                } else {
                    Box::new(dmap.iter().filter_map(|(f, e)| {
                        if !results.contains_key(f.deref())
                            && matcher.matches(f)
                        {
                            Some((f.deref(), e))
                        } else {
                            None
                        }
                    }))
                };
            let mut to_visit: Vec<_> = to_visit.collect();
            to_visit.sort_by(|a, b| a.0.cmp(&b.0));

            // We walked all dirs under the roots that weren't ignored, and
            // everything that matched was stat'ed and is already in results.
            // The rest must thus be ignored or under a symlink.
            let mut path_auditor = PathAuditor::new(root_dir);

            for (ref filename, entry) in to_visit {
                // Report ignored items in the dmap as long as they are not
                // under a symlink directory.
                if path_auditor.check(filename) {
                    // TODO normalize for case-insensitive filesystems
                    let buf = hg_path_to_path_buf(filename)?;
                    results.insert(
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
                    );
                } else {
                    // It's either missing or under a symlink directory which
                    // we, in this case, report as missing.
                    results.insert(
                        Cow::Borrowed(filename),
                        dispatch_missing(entry.state),
                    );
                }
            }
        } else {
            // We may not have walked the full directory tree above, so stat
            // and check everything we missed.
            let stat_results = stat_dmap_entries(&dmap, root_dir, options);
            results.par_extend(stat_results.flatten().map(
                |(filename, dispatch)| (Cow::Borrowed(filename), dispatch),
            ));
        }
    }

    let results = results.into_iter().filter_map(|(filename, dispatch)| {
        match dispatch {
            Dispatch::Bad(_) => return Some((filename, dispatch)),
            _ => {}
        };
        // TODO do this in //, not at the end
        if !dmap.contains_key(filename.deref()) {
            if (options.list_ignored || matcher.exact_match(&filename))
                && dir_ignore_fn(&filename)
            {
                if options.list_ignored {
                    return Some((filename.to_owned(), Dispatch::Ignored));
                }
            } else {
                if !ignore_fn(&filename) {
                    return Some((filename.to_owned(), Dispatch::Unknown));
                }
            }
            return None;
        }
        Some((filename, dispatch))
    });

    Ok((build_response(results), warnings))
}

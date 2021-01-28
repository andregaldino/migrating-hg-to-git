// status.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Rust implementation of dirstate.status (dirstate.py).
//! It is currently missing a lot of functionality compared to the Python one
//! and will only be triggered in narrow cases.

#[cfg(feature = "dirstate-tree")]
use crate::dirstate::dirstate_tree::iter::StatusShortcut;
#[cfg(not(feature = "dirstate-tree"))]
use crate::utils::path_auditor::PathAuditor;
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
    fmt,
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

impl fmt::Display for BadType {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(match self {
            BadType::CharacterDevice => "character device",
            BadType::BlockDevice => "block device",
            BadType::FIFO => "fifo",
            BadType::Socket => "socket",
            BadType::Directory => "directory",
            BadType::Unknown => "unknown",
        })
    }
}

/// Was explicitly matched but cannot be found/accessed
#[derive(Debug, Copy, Clone)]
pub enum BadMatch {
    OsError(i32),
    BadType(BadType),
}

/// Enum used to dispatch new status entries into the right collections.
/// Is similar to `crate::EntryState`, but represents the transient state of
/// entries during the lifetime of a command.
#[derive(Debug, Copy, Clone)]
pub enum Dispatch {
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

/// We have a good mix of owned (from directory traversal) and borrowed (from
/// the dirstate/explicit) paths, this comes up a lot.
pub type HgPathCow<'a> = Cow<'a, HgPath>;

/// A path with its computed ``Dispatch`` information
type DispatchedPath<'a> = (HgPathCow<'a>, Dispatch);

/// The conversion from `HgPath` to a real fs path failed.
/// `22` is the error code for "Invalid argument"
const INVALID_PATH_DISPATCH: Dispatch = Dispatch::Bad(BadMatch::OsError(22));

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
            results.push((filename, entry))
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
            } else if mod_compare(mtime, st_mtime as i32)
                || st_mtime == options.last_normal_time
            {
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

fn dispatch_os_error(e: &std::io::Error) -> Dispatch {
    Dispatch::Bad(BadMatch::OsError(
        e.raw_os_error().expect("expected real OS error"),
    ))
}

lazy_static! {
    static ref DEFAULT_WORK: HashSet<&'static HgPath> = {
        let mut h = HashSet::new();
        h.insert(HgPath::new(b""));
        h
    };
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

#[derive(Debug)]
pub struct DirstateStatus<'a> {
    pub modified: Vec<HgPathCow<'a>>,
    pub added: Vec<HgPathCow<'a>>,
    pub removed: Vec<HgPathCow<'a>>,
    pub deleted: Vec<HgPathCow<'a>>,
    pub clean: Vec<HgPathCow<'a>>,
    pub ignored: Vec<HgPathCow<'a>>,
    pub unknown: Vec<HgPathCow<'a>>,
    pub bad: Vec<(HgPathCow<'a>, BadMatch)>,
    /// Only filled if `collect_traversed_dirs` is `true`
    pub traversed: Vec<HgPathBuf>,
}

#[derive(Debug, derive_more::From)]
pub enum StatusError {
    /// Generic IO error
    IO(std::io::Error),
    /// An invalid path that cannot be represented in Mercurial was found
    Path(HgPathError),
    /// An invalid "ignore" pattern was found
    Pattern(PatternError),
}

pub type StatusResult<T> = Result<T, StatusError>;

impl fmt::Display for StatusError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            StatusError::IO(error) => error.fmt(f),
            StatusError::Path(error) => error.fmt(f),
            StatusError::Pattern(error) => error.fmt(f),
        }
    }
}

/// Gives information about which files are changed in the working directory
/// and how, compared to the revision we're based on
pub struct Status<'a, M: Matcher + Sync> {
    dmap: &'a DirstateMap,
    pub(crate) matcher: &'a M,
    root_dir: PathBuf,
    pub(crate) options: StatusOptions,
    ignore_fn: IgnoreFnType<'a>,
}

impl<'a, M> Status<'a, M>
where
    M: Matcher + Sync,
{
    pub fn new(
        dmap: &'a DirstateMap,
        matcher: &'a M,
        root_dir: PathBuf,
        ignore_files: Vec<PathBuf>,
        options: StatusOptions,
    ) -> StatusResult<(Self, Vec<PatternFileWarning>)> {
        // Needs to outlive `dir_ignore_fn` since it's captured.

        let (ignore_fn, warnings): (IgnoreFnType, _) =
            if options.list_ignored || options.list_unknown {
                get_ignore_function(ignore_files, &root_dir)?
            } else {
                (Box::new(|&_| true), vec![])
            };

        Ok((
            Self {
                dmap,
                matcher,
                root_dir,
                options,
                ignore_fn,
            },
            warnings,
        ))
    }

    /// Is the path ignored?
    pub fn is_ignored(&self, path: impl AsRef<HgPath>) -> bool {
        (self.ignore_fn)(path.as_ref())
    }

    /// Is the path or one of its ancestors ignored?
    pub fn dir_ignore(&self, dir: impl AsRef<HgPath>) -> bool {
        // Only involve ignore mechanism if we're listing unknowns or ignored.
        if self.options.list_ignored || self.options.list_unknown {
            if self.is_ignored(&dir) {
                true
            } else {
                for p in find_dirs(dir.as_ref()) {
                    if self.is_ignored(p) {
                        return true;
                    }
                }
                false
            }
        } else {
            true
        }
    }

    /// Get stat data about the files explicitly specified by the matcher.
    /// Returns a tuple of the directories that need to be traversed and the
    /// files with their corresponding `Dispatch`.
    /// TODO subrepos
    #[timed]
    pub fn walk_explicit(
        &self,
        traversed_sender: crossbeam_channel::Sender<HgPathBuf>,
    ) -> (Vec<DispatchedPath<'a>>, Vec<DispatchedPath<'a>>) {
        self.matcher
            .file_set()
            .unwrap_or(&DEFAULT_WORK)
            .par_iter()
            .flat_map(|&filename| -> Option<_> {
                // TODO normalization
                let normalized = filename;

                let buf = match hg_path_to_path_buf(normalized) {
                    Ok(x) => x,
                    Err(_) => {
                        return Some((
                            Cow::Borrowed(normalized),
                            INVALID_PATH_DISPATCH,
                        ))
                    }
                };
                let target = self.root_dir.join(buf);
                let st = target.symlink_metadata();
                let in_dmap = self.dmap.get(normalized);
                match st {
                    Ok(meta) => {
                        let file_type = meta.file_type();
                        return if file_type.is_file() || file_type.is_symlink()
                        {
                            if let Some(entry) = in_dmap {
                                return Some((
                                    Cow::Borrowed(normalized),
                                    dispatch_found(
                                        &normalized,
                                        *entry,
                                        HgMetadata::from_metadata(meta),
                                        &self.dmap.copy_map,
                                        self.options,
                                    ),
                                ));
                            }
                            Some((
                                Cow::Borrowed(normalized),
                                Dispatch::Unknown,
                            ))
                        } else if file_type.is_dir() {
                            if self.options.collect_traversed_dirs {
                                traversed_sender
                                    .send(normalized.to_owned())
                                    .expect("receiver should outlive sender");
                            }
                            Some((
                                Cow::Borrowed(normalized),
                                Dispatch::Directory {
                                    was_file: in_dmap.is_some(),
                                },
                            ))
                        } else {
                            Some((
                                Cow::Borrowed(normalized),
                                Dispatch::Bad(BadMatch::BadType(
                                    // TODO do more than unknown
                                    // Support for all `BadType` variant
                                    // varies greatly between platforms.
                                    // So far, no tests check the type and
                                    // this should be good enough for most
                                    // users.
                                    BadType::Unknown,
                                )),
                            ))
                        };
                    }
                    Err(_) => {
                        if let Some(entry) = in_dmap {
                            return Some((
                                Cow::Borrowed(normalized),
                                dispatch_missing(entry.state),
                            ));
                        }
                    }
                };
                None
            })
            .partition(|(_, dispatch)| match dispatch {
                Dispatch::Directory { .. } => true,
                _ => false,
            })
    }

    /// Walk the working directory recursively to look for changes compared to
    /// the current `DirstateMap`.
    ///
    /// This takes a mutable reference to the results to account for the
    /// `extend` in timings
    #[timed]
    pub fn traverse(
        &self,
        path: impl AsRef<HgPath>,
        old_results: &FastHashMap<HgPathCow<'a>, Dispatch>,
        results: &mut Vec<DispatchedPath<'a>>,
        traversed_sender: crossbeam_channel::Sender<HgPathBuf>,
    ) {
        // The traversal is done in parallel, so use a channel to gather
        // entries. `crossbeam_channel::Sender` is `Sync`, while `mpsc::Sender`
        // is not.
        let (files_transmitter, files_receiver) =
            crossbeam_channel::unbounded();

        self.traverse_dir(
            &files_transmitter,
            path,
            &old_results,
            traversed_sender,
        );

        // Disconnect the channel so the receiver stops waiting
        drop(files_transmitter);

        let new_results = files_receiver
            .into_iter()
            .par_bridge()
            .map(|(f, d)| (Cow::Owned(f), d));

        results.par_extend(new_results);
    }

    /// Dispatch a single entry (file, folder, symlink...) found during
    /// `traverse`. If the entry is a folder that needs to be traversed, it
    /// will be handled in a separate thread.
    fn handle_traversed_entry<'b>(
        &'a self,
        scope: &rayon::Scope<'b>,
        files_sender: &'b crossbeam_channel::Sender<(HgPathBuf, Dispatch)>,
        old_results: &'a FastHashMap<Cow<HgPath>, Dispatch>,
        filename: HgPathBuf,
        dir_entry: DirEntry,
        traversed_sender: crossbeam_channel::Sender<HgPathBuf>,
    ) -> IoResult<()>
    where
        'a: 'b,
    {
        let file_type = dir_entry.file_type()?;
        let entry_option = self.dmap.get(&filename);

        if filename.as_bytes() == b".hg" {
            // Could be a directory or a symlink
            return Ok(());
        }

        if file_type.is_dir() {
            self.handle_traversed_dir(
                scope,
                files_sender,
                old_results,
                entry_option,
                filename,
                traversed_sender,
            );
        } else if file_type.is_file() || file_type.is_symlink() {
            if let Some(entry) = entry_option {
                if self.matcher.matches_everything()
                    || self.matcher.matches(&filename)
                {
                    let metadata = dir_entry.metadata()?;
                    files_sender
                        .send((
                            filename.to_owned(),
                            dispatch_found(
                                &filename,
                                *entry,
                                HgMetadata::from_metadata(metadata),
                                &self.dmap.copy_map,
                                self.options,
                            ),
                        ))
                        .unwrap();
                }
            } else if (self.matcher.matches_everything()
                || self.matcher.matches(&filename))
                && !self.is_ignored(&filename)
            {
                if (self.options.list_ignored
                    || self.matcher.exact_match(&filename))
                    && self.dir_ignore(&filename)
                {
                    if self.options.list_ignored {
                        files_sender
                            .send((filename.to_owned(), Dispatch::Ignored))
                            .unwrap();
                    }
                } else if self.options.list_unknown {
                    files_sender
                        .send((filename.to_owned(), Dispatch::Unknown))
                        .unwrap();
                }
            } else if self.is_ignored(&filename) && self.options.list_ignored {
                files_sender
                    .send((filename.to_owned(), Dispatch::Ignored))
                    .unwrap();
            }
        } else if let Some(entry) = entry_option {
            // Used to be a file or a folder, now something else.
            if self.matcher.matches_everything()
                || self.matcher.matches(&filename)
            {
                files_sender
                    .send((filename.to_owned(), dispatch_missing(entry.state)))
                    .unwrap();
            }
        }

        Ok(())
    }

    /// A directory was found in the filesystem and needs to be traversed
    fn handle_traversed_dir<'b>(
        &'a self,
        scope: &rayon::Scope<'b>,
        files_sender: &'b crossbeam_channel::Sender<(HgPathBuf, Dispatch)>,
        old_results: &'a FastHashMap<Cow<HgPath>, Dispatch>,
        entry_option: Option<&'a DirstateEntry>,
        directory: HgPathBuf,
        traversed_sender: crossbeam_channel::Sender<HgPathBuf>,
    ) where
        'a: 'b,
    {
        scope.spawn(move |_| {
            // Nested `if` until `rust-lang/rust#53668` is stable
            if let Some(entry) = entry_option {
                // Used to be a file, is now a folder
                if self.matcher.matches_everything()
                    || self.matcher.matches(&directory)
                {
                    files_sender
                        .send((
                            directory.to_owned(),
                            dispatch_missing(entry.state),
                        ))
                        .unwrap();
                }
            }
            // Do we need to traverse it?
            if !self.is_ignored(&directory) || self.options.list_ignored {
                self.traverse_dir(
                    files_sender,
                    directory,
                    &old_results,
                    traversed_sender,
                )
            }
        });
    }

    /// Decides whether the directory needs to be listed, and if so handles the
    /// entries in a separate thread.
    fn traverse_dir(
        &self,
        files_sender: &crossbeam_channel::Sender<(HgPathBuf, Dispatch)>,
        directory: impl AsRef<HgPath>,
        old_results: &FastHashMap<Cow<HgPath>, Dispatch>,
        traversed_sender: crossbeam_channel::Sender<HgPathBuf>,
    ) {
        let directory = directory.as_ref();

        if self.options.collect_traversed_dirs {
            traversed_sender
                .send(directory.to_owned())
                .expect("receiver should outlive sender");
        }

        let visit_entries = match self.matcher.visit_children_set(directory) {
            VisitChildrenSet::Empty => return,
            VisitChildrenSet::This | VisitChildrenSet::Recursive => None,
            VisitChildrenSet::Set(set) => Some(set),
        };
        let buf = match hg_path_to_path_buf(directory) {
            Ok(b) => b,
            Err(_) => {
                files_sender
                    .send((directory.to_owned(), INVALID_PATH_DISPATCH))
                    .expect("receiver should outlive sender");
                return;
            }
        };
        let dir_path = self.root_dir.join(buf);

        let skip_dot_hg = !directory.as_bytes().is_empty();
        let entries = match list_directory(dir_path, skip_dot_hg) {
            Err(e) => {
                files_sender
                    .send((directory.to_owned(), dispatch_os_error(&e)))
                    .expect("receiver should outlive sender");
                return;
            }
            Ok(entries) => entries,
        };

        rayon::scope(|scope| {
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
                    match self.handle_traversed_entry(
                        scope,
                        files_sender,
                        old_results,
                        filename,
                        dir_entry,
                        traversed_sender.clone(),
                    ) {
                        Err(e) => {
                            files_sender
                                .send((
                                    directory.to_owned(),
                                    dispatch_os_error(&e),
                                ))
                                .expect("receiver should outlive sender");
                        }
                        Ok(_) => {}
                    }
                }
            }
        })
    }

    /// Add the files in the dirstate to the results.
    ///
    /// This takes a mutable reference to the results to account for the
    /// `extend` in timings
    #[cfg(feature = "dirstate-tree")]
    #[timed]
    pub fn extend_from_dmap(&self, results: &mut Vec<DispatchedPath<'a>>) {
        results.par_extend(
            self.dmap
                .fs_iter(self.root_dir.clone())
                .par_bridge()
                .filter(|(path, _)| self.matcher.matches(path))
                .map(move |(filename, shortcut)| {
                    let entry = match shortcut {
                        StatusShortcut::Entry(e) => e,
                        StatusShortcut::Dispatch(d) => {
                            return (Cow::Owned(filename), d)
                        }
                    };
                    let filename_as_path = match hg_path_to_path_buf(&filename)
                    {
                        Ok(f) => f,
                        Err(_) => {
                            return (
                                Cow::Owned(filename),
                                INVALID_PATH_DISPATCH,
                            )
                        }
                    };
                    let meta = self
                        .root_dir
                        .join(filename_as_path)
                        .symlink_metadata();

                    match meta {
                        Ok(m)
                            if !(m.file_type().is_file()
                                || m.file_type().is_symlink()) =>
                        {
                            (
                                Cow::Owned(filename),
                                dispatch_missing(entry.state),
                            )
                        }
                        Ok(m) => {
                            let dispatch = dispatch_found(
                                &filename,
                                entry,
                                HgMetadata::from_metadata(m),
                                &self.dmap.copy_map,
                                self.options,
                            );
                            (Cow::Owned(filename), dispatch)
                        }
                        Err(e)
                            if e.kind() == ErrorKind::NotFound
                                || e.raw_os_error() == Some(20) =>
                        {
                            // Rust does not yet have an `ErrorKind` for
                            // `NotADirectory` (errno 20)
                            // It happens if the dirstate contains `foo/bar`
                            // and foo is not a
                            // directory
                            (
                                Cow::Owned(filename),
                                dispatch_missing(entry.state),
                            )
                        }
                        Err(e) => {
                            (Cow::Owned(filename), dispatch_os_error(&e))
                        }
                    }
                }),
        );
    }

    /// Add the files in the dirstate to the results.
    ///
    /// This takes a mutable reference to the results to account for the
    /// `extend` in timings
    #[cfg(not(feature = "dirstate-tree"))]
    #[timed]
    pub fn extend_from_dmap(&self, results: &mut Vec<DispatchedPath<'a>>) {
        results.par_extend(self.dmap.par_iter().map(
            move |(filename, entry)| {
                let filename: &HgPath = filename;
                let filename_as_path = match hg_path_to_path_buf(filename) {
                    Ok(f) => f,
                    Err(_) => {
                        return (
                            Cow::Borrowed(filename),
                            INVALID_PATH_DISPATCH,
                        )
                    }
                };
                let meta =
                    self.root_dir.join(filename_as_path).symlink_metadata();
                match meta {
                    Ok(m)
                        if !(m.file_type().is_file()
                            || m.file_type().is_symlink()) =>
                    {
                        (
                            Cow::Borrowed(filename),
                            dispatch_missing(entry.state),
                        )
                    }
                    Ok(m) => (
                        Cow::Borrowed(filename),
                        dispatch_found(
                            filename,
                            *entry,
                            HgMetadata::from_metadata(m),
                            &self.dmap.copy_map,
                            self.options,
                        ),
                    ),
                    Err(e)
                        if e.kind() == ErrorKind::NotFound
                            || e.raw_os_error() == Some(20) =>
                    {
                        // Rust does not yet have an `ErrorKind` for
                        // `NotADirectory` (errno 20)
                        // It happens if the dirstate contains `foo/bar`
                        // and foo is not a
                        // directory
                        (
                            Cow::Borrowed(filename),
                            dispatch_missing(entry.state),
                        )
                    }
                    Err(e) => (Cow::Borrowed(filename), dispatch_os_error(&e)),
                }
            },
        ));
    }

    /// Checks all files that are in the dirstate but were not found during the
    /// working directory traversal. This means that the rest must
    /// be either ignored, under a symlink or under a new nested repo.
    ///
    /// This takes a mutable reference to the results to account for the
    /// `extend` in timings
    #[cfg(not(feature = "dirstate-tree"))]
    #[timed]
    pub fn handle_unknowns(&self, results: &mut Vec<DispatchedPath<'a>>) {
        let to_visit: Vec<(&HgPath, &DirstateEntry)> =
            if results.is_empty() && self.matcher.matches_everything() {
                self.dmap.iter().map(|(f, e)| (f.deref(), e)).collect()
            } else {
                // Only convert to a hashmap if needed.
                let old_results: FastHashMap<_, _> =
                    results.iter().cloned().collect();
                self.dmap
                    .iter()
                    .filter_map(move |(f, e)| {
                        if !old_results.contains_key(f.deref())
                            && self.matcher.matches(f)
                        {
                            Some((f.deref(), e))
                        } else {
                            None
                        }
                    })
                    .collect()
            };

        let path_auditor = PathAuditor::new(&self.root_dir);

        let new_results = to_visit.into_par_iter().filter_map(
            |(filename, entry)| -> Option<_> {
                // Report ignored items in the dmap as long as they are not
                // under a symlink directory.
                if path_auditor.check(filename) {
                    // TODO normalize for case-insensitive filesystems
                    let buf = match hg_path_to_path_buf(filename) {
                        Ok(x) => x,
                        Err(_) => {
                            return Some((
                                Cow::Owned(filename.to_owned()),
                                INVALID_PATH_DISPATCH,
                            ));
                        }
                    };
                    Some((
                        Cow::Owned(filename.to_owned()),
                        match self.root_dir.join(&buf).symlink_metadata() {
                            // File was just ignored, no links, and exists
                            Ok(meta) => {
                                let metadata = HgMetadata::from_metadata(meta);
                                dispatch_found(
                                    filename,
                                    *entry,
                                    metadata,
                                    &self.dmap.copy_map,
                                    self.options,
                                )
                            }
                            // File doesn't exist
                            Err(_) => dispatch_missing(entry.state),
                        },
                    ))
                } else {
                    // It's either missing or under a symlink directory which
                    // we, in this case, report as missing.
                    Some((
                        Cow::Owned(filename.to_owned()),
                        dispatch_missing(entry.state),
                    ))
                }
            },
        );

        results.par_extend(new_results);
    }
}

#[timed]
pub fn build_response<'a>(
    results: impl IntoIterator<Item = DispatchedPath<'a>>,
    traversed: Vec<HgPathBuf>,
) -> (Vec<HgPathCow<'a>>, DirstateStatus<'a>) {
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

/// Get the status of files in the working directory.
///
/// This is the current entry-point for `hg-core` and is realistically unusable
/// outside of a Python context because its arguments need to provide a lot of
/// information that will not be necessary in the future.
#[timed]
pub fn status<'a>(
    dmap: &'a DirstateMap,
    matcher: &'a (impl Matcher + Sync),
    root_dir: PathBuf,
    ignore_files: Vec<PathBuf>,
    options: StatusOptions,
) -> StatusResult<(
    (Vec<HgPathCow<'a>>, DirstateStatus<'a>),
    Vec<PatternFileWarning>,
)> {
    let (status, warnings) =
        Status::new(dmap, matcher, root_dir, ignore_files, options)?;

    Ok((status.run()?, warnings))
}

use crate::dirstate::entry::TruncatedTimestamp;
use crate::dirstate::status::IgnoreFnType;
use crate::dirstate::status::StatusPath;
use crate::dirstate_tree::dirstate_map::BorrowedPath;
use crate::dirstate_tree::dirstate_map::ChildNodesRef;
use crate::dirstate_tree::dirstate_map::DirstateMap;
use crate::dirstate_tree::dirstate_map::NodeData;
use crate::dirstate_tree::dirstate_map::NodeRef;
use crate::dirstate_tree::on_disk::DirstateV2ParseError;
use crate::matchers::get_ignore_function;
use crate::matchers::Matcher;
use crate::utils::files::get_bytes_from_os_string;
use crate::utils::files::get_path_from_bytes;
use crate::utils::hg_path::HgPath;
use crate::BadMatch;
use crate::DirstateStatus;
use crate::EntryState;
use crate::HgPathBuf;
use crate::HgPathCow;
use crate::PatternFileWarning;
use crate::StatusError;
use crate::StatusOptions;
use micro_timer::timed;
use rayon::prelude::*;
use sha1::{Digest, Sha1};
use std::borrow::Cow;
use std::io;
use std::path::Path;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::SystemTime;

/// Returns the status of the working directory compared to its parent
/// changeset.
///
/// This algorithm is based on traversing the filesystem tree (`fs` in function
/// and variable names) and dirstate tree at the same time. The core of this
/// traversal is the recursive `traverse_fs_directory_and_dirstate` function
/// and its use of `itertools::merge_join_by`. When reaching a path that only
/// exists in one of the two trees, depending on information requested by
/// `options` we may need to traverse the remaining subtree.
#[timed]
pub fn status<'tree, 'on_disk: 'tree>(
    dmap: &'tree mut DirstateMap<'on_disk>,
    matcher: &(dyn Matcher + Sync),
    root_dir: PathBuf,
    ignore_files: Vec<PathBuf>,
    options: StatusOptions,
) -> Result<(DirstateStatus<'on_disk>, Vec<PatternFileWarning>), StatusError> {
    let (ignore_fn, warnings, patterns_changed): (IgnoreFnType, _, _) =
        if options.list_ignored || options.list_unknown {
            let mut hasher = Sha1::new();
            let (ignore_fn, warnings) = get_ignore_function(
                ignore_files,
                &root_dir,
                &mut |pattern_bytes| hasher.update(pattern_bytes),
            )?;
            let new_hash = *hasher.finalize().as_ref();
            let changed = new_hash != dmap.ignore_patterns_hash;
            dmap.ignore_patterns_hash = new_hash;
            (ignore_fn, warnings, Some(changed))
        } else {
            (Box::new(|&_| true), vec![], None)
        };

    let filesystem_time_at_status_start = filesystem_now(&root_dir).ok();
    let outcome = DirstateStatus {
        filesystem_time_at_status_start,
        ..Default::default()
    };
    let common = StatusCommon {
        dmap,
        options,
        matcher,
        ignore_fn,
        outcome: Mutex::new(outcome),
        ignore_patterns_have_changed: patterns_changed,
        new_cachable_directories: Default::default(),
        outated_cached_directories: Default::default(),
        filesystem_time_at_status_start,
    };
    let is_at_repo_root = true;
    let hg_path = &BorrowedPath::OnDisk(HgPath::new(""));
    let has_ignored_ancestor = false;
    let root_cached_mtime = None;
    let root_dir_metadata = None;
    // If the path we have for the repository root is a symlink, do follow it.
    // (As opposed to symlinks within the working directory which are not
    // followed, using `std::fs::symlink_metadata`.)
    common.traverse_fs_directory_and_dirstate(
        has_ignored_ancestor,
        dmap.root.as_ref(),
        hg_path,
        &root_dir,
        root_dir_metadata,
        root_cached_mtime,
        is_at_repo_root,
    )?;
    let mut outcome = common.outcome.into_inner().unwrap();
    let new_cachable = common.new_cachable_directories.into_inner().unwrap();
    let outdated = common.outated_cached_directories.into_inner().unwrap();

    outcome.dirty = common.ignore_patterns_have_changed == Some(true)
        || !outdated.is_empty()
        || !new_cachable.is_empty();

    // Remove outdated mtimes before adding new mtimes, in case a given
    // directory is both
    for path in &outdated {
        let node = dmap.get_or_insert(path)?;
        if let NodeData::CachedDirectory { .. } = &node.data {
            node.data = NodeData::None
        }
    }
    for (path, mtime) in &new_cachable {
        let node = dmap.get_or_insert(path)?;
        match &node.data {
            NodeData::Entry(_) => {} // Don’t overwrite an entry
            NodeData::CachedDirectory { .. } | NodeData::None => {
                node.data = NodeData::CachedDirectory { mtime: *mtime }
            }
        }
    }

    Ok((outcome, warnings))
}

/// Bag of random things needed by various parts of the algorithm. Reduces the
/// number of parameters passed to functions.
struct StatusCommon<'a, 'tree, 'on_disk: 'tree> {
    dmap: &'tree DirstateMap<'on_disk>,
    options: StatusOptions,
    matcher: &'a (dyn Matcher + Sync),
    ignore_fn: IgnoreFnType<'a>,
    outcome: Mutex<DirstateStatus<'on_disk>>,
    new_cachable_directories:
        Mutex<Vec<(Cow<'on_disk, HgPath>, TruncatedTimestamp)>>,
    outated_cached_directories: Mutex<Vec<Cow<'on_disk, HgPath>>>,

    /// Whether ignore files like `.hgignore` have changed since the previous
    /// time a `status()` call wrote their hash to the dirstate. `None` means
    /// we don’t know as this run doesn’t list either ignored or uknown files
    /// and therefore isn’t reading `.hgignore`.
    ignore_patterns_have_changed: Option<bool>,

    /// The current time at the start of the `status()` algorithm, as measured
    /// and possibly truncated by the filesystem.
    filesystem_time_at_status_start: Option<SystemTime>,
}

enum Outcome {
    Modified,
    Added,
    Removed,
    Deleted,
    Clean,
    Ignored,
    Unknown,
    Unsure,
}

impl<'a, 'tree, 'on_disk> StatusCommon<'a, 'tree, 'on_disk> {
    fn push_outcome(
        &self,
        which: Outcome,
        dirstate_node: &NodeRef<'tree, 'on_disk>,
    ) -> Result<(), DirstateV2ParseError> {
        let path = dirstate_node
            .full_path_borrowed(self.dmap.on_disk)?
            .detach_from_tree();
        let copy_source = if self.options.list_copies {
            dirstate_node
                .copy_source_borrowed(self.dmap.on_disk)?
                .map(|source| source.detach_from_tree())
        } else {
            None
        };
        self.push_outcome_common(which, path, copy_source);
        Ok(())
    }

    fn push_outcome_without_copy_source(
        &self,
        which: Outcome,
        path: &BorrowedPath<'_, 'on_disk>,
    ) {
        self.push_outcome_common(which, path.detach_from_tree(), None)
    }

    fn push_outcome_common(
        &self,
        which: Outcome,
        path: HgPathCow<'on_disk>,
        copy_source: Option<HgPathCow<'on_disk>>,
    ) {
        let mut outcome = self.outcome.lock().unwrap();
        let vec = match which {
            Outcome::Modified => &mut outcome.modified,
            Outcome::Added => &mut outcome.added,
            Outcome::Removed => &mut outcome.removed,
            Outcome::Deleted => &mut outcome.deleted,
            Outcome::Clean => &mut outcome.clean,
            Outcome::Ignored => &mut outcome.ignored,
            Outcome::Unknown => &mut outcome.unknown,
            Outcome::Unsure => &mut outcome.unsure,
        };
        vec.push(StatusPath { path, copy_source });
    }

    fn read_dir(
        &self,
        hg_path: &HgPath,
        fs_path: &Path,
        is_at_repo_root: bool,
    ) -> Result<Vec<DirEntry>, ()> {
        DirEntry::read_dir(fs_path, is_at_repo_root)
            .map_err(|error| self.io_error(error, hg_path))
    }

    fn io_error(&self, error: std::io::Error, hg_path: &HgPath) {
        let errno = error.raw_os_error().expect("expected real OS error");
        self.outcome
            .lock()
            .unwrap()
            .bad
            .push((hg_path.to_owned().into(), BadMatch::OsError(errno)))
    }

    fn check_for_outdated_directory_cache(
        &self,
        dirstate_node: &NodeRef<'tree, 'on_disk>,
    ) -> Result<(), DirstateV2ParseError> {
        if self.ignore_patterns_have_changed == Some(true)
            && dirstate_node.cached_directory_mtime()?.is_some()
        {
            self.outated_cached_directories.lock().unwrap().push(
                dirstate_node
                    .full_path_borrowed(self.dmap.on_disk)?
                    .detach_from_tree(),
            )
        }
        Ok(())
    }

    /// If this returns true, we can get accurate results by only using
    /// `symlink_metadata` for child nodes that exist in the dirstate and don’t
    /// need to call `read_dir`.
    fn can_skip_fs_readdir(
        &self,
        directory_metadata: Option<&std::fs::Metadata>,
        cached_directory_mtime: Option<TruncatedTimestamp>,
    ) -> bool {
        if !self.options.list_unknown && !self.options.list_ignored {
            // All states that we care about listing have corresponding
            // dirstate entries.
            // This happens for example with `hg status -mard`.
            return true;
        }
        if !self.options.list_ignored
            && self.ignore_patterns_have_changed == Some(false)
        {
            if let Some(cached_mtime) = cached_directory_mtime {
                // The dirstate contains a cached mtime for this directory, set
                // by a previous run of the `status` algorithm which found this
                // directory eligible for `read_dir` caching.
                if let Some(meta) = directory_metadata {
                    if cached_mtime
                        .likely_equal_to_mtime_of(meta)
                        .unwrap_or(false)
                    {
                        // The mtime of that directory has not changed
                        // since then, which means that the results of
                        // `read_dir` should also be unchanged.
                        return true;
                    }
                }
            }
        }
        false
    }

    /// Returns whether all child entries of the filesystem directory have a
    /// corresponding dirstate node or are ignored.
    fn traverse_fs_directory_and_dirstate(
        &self,
        has_ignored_ancestor: bool,
        dirstate_nodes: ChildNodesRef<'tree, 'on_disk>,
        directory_hg_path: &BorrowedPath<'tree, 'on_disk>,
        directory_fs_path: &Path,
        directory_metadata: Option<&std::fs::Metadata>,
        cached_directory_mtime: Option<TruncatedTimestamp>,
        is_at_repo_root: bool,
    ) -> Result<bool, DirstateV2ParseError> {
        if self.can_skip_fs_readdir(directory_metadata, cached_directory_mtime)
        {
            dirstate_nodes
                .par_iter()
                .map(|dirstate_node| {
                    let fs_path = directory_fs_path.join(get_path_from_bytes(
                        dirstate_node.base_name(self.dmap.on_disk)?.as_bytes(),
                    ));
                    match std::fs::symlink_metadata(&fs_path) {
                        Ok(fs_metadata) => self.traverse_fs_and_dirstate(
                            &fs_path,
                            &fs_metadata,
                            dirstate_node,
                            has_ignored_ancestor,
                        ),
                        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                            self.traverse_dirstate_only(dirstate_node)
                        }
                        Err(error) => {
                            let hg_path =
                                dirstate_node.full_path(self.dmap.on_disk)?;
                            Ok(self.io_error(error, hg_path))
                        }
                    }
                })
                .collect::<Result<_, _>>()?;

            // We don’t know, so conservatively say this isn’t the case
            let children_all_have_dirstate_node_or_are_ignored = false;

            return Ok(children_all_have_dirstate_node_or_are_ignored);
        }

        let mut fs_entries = if let Ok(entries) = self.read_dir(
            directory_hg_path,
            directory_fs_path,
            is_at_repo_root,
        ) {
            entries
        } else {
            // Treat an unreadable directory (typically because of insufficient
            // permissions) like an empty directory. `self.read_dir` has
            // already called `self.io_error` so a warning will be emitted.
            Vec::new()
        };

        // `merge_join_by` requires both its input iterators to be sorted:

        let dirstate_nodes = dirstate_nodes.sorted();
        // `sort_unstable_by_key` doesn’t allow keys borrowing from the value:
        // https://github.com/rust-lang/rust/issues/34162
        fs_entries.sort_unstable_by(|e1, e2| e1.base_name.cmp(&e2.base_name));

        // Propagate here any error that would happen inside the comparison
        // callback below
        for dirstate_node in &dirstate_nodes {
            dirstate_node.base_name(self.dmap.on_disk)?;
        }
        itertools::merge_join_by(
            dirstate_nodes,
            &fs_entries,
            |dirstate_node, fs_entry| {
                // This `unwrap` never panics because we already propagated
                // those errors above
                dirstate_node
                    .base_name(self.dmap.on_disk)
                    .unwrap()
                    .cmp(&fs_entry.base_name)
            },
        )
        .par_bridge()
        .map(|pair| {
            use itertools::EitherOrBoth::*;
            let has_dirstate_node_or_is_ignored;
            match pair {
                Both(dirstate_node, fs_entry) => {
                    self.traverse_fs_and_dirstate(
                        &fs_entry.full_path,
                        &fs_entry.metadata,
                        dirstate_node,
                        has_ignored_ancestor,
                    )?;
                    has_dirstate_node_or_is_ignored = true
                }
                Left(dirstate_node) => {
                    self.traverse_dirstate_only(dirstate_node)?;
                    has_dirstate_node_or_is_ignored = true;
                }
                Right(fs_entry) => {
                    has_dirstate_node_or_is_ignored = self.traverse_fs_only(
                        has_ignored_ancestor,
                        directory_hg_path,
                        fs_entry,
                    )
                }
            }
            Ok(has_dirstate_node_or_is_ignored)
        })
        .try_reduce(|| true, |a, b| Ok(a && b))
    }

    fn traverse_fs_and_dirstate(
        &self,
        fs_path: &Path,
        fs_metadata: &std::fs::Metadata,
        dirstate_node: NodeRef<'tree, 'on_disk>,
        has_ignored_ancestor: bool,
    ) -> Result<(), DirstateV2ParseError> {
        self.check_for_outdated_directory_cache(&dirstate_node)?;
        let hg_path = &dirstate_node.full_path_borrowed(self.dmap.on_disk)?;
        let file_type = fs_metadata.file_type();
        let file_or_symlink = file_type.is_file() || file_type.is_symlink();
        if !file_or_symlink {
            // If we previously had a file here, it was removed (with
            // `hg rm` or similar) or deleted before it could be
            // replaced by a directory or something else.
            self.mark_removed_or_deleted_if_file(&dirstate_node)?;
        }
        if file_type.is_dir() {
            if self.options.collect_traversed_dirs {
                self.outcome
                    .lock()
                    .unwrap()
                    .traversed
                    .push(hg_path.detach_from_tree())
            }
            let is_ignored = has_ignored_ancestor || (self.ignore_fn)(hg_path);
            let is_at_repo_root = false;
            let children_all_have_dirstate_node_or_are_ignored = self
                .traverse_fs_directory_and_dirstate(
                    is_ignored,
                    dirstate_node.children(self.dmap.on_disk)?,
                    hg_path,
                    fs_path,
                    Some(fs_metadata),
                    dirstate_node.cached_directory_mtime()?,
                    is_at_repo_root,
                )?;
            self.maybe_save_directory_mtime(
                children_all_have_dirstate_node_or_are_ignored,
                fs_metadata,
                dirstate_node,
            )?
        } else {
            if file_or_symlink && self.matcher.matches(hg_path) {
                if let Some(state) = dirstate_node.state()? {
                    match state {
                        EntryState::Added => {
                            self.push_outcome(Outcome::Added, &dirstate_node)?
                        }
                        EntryState::Removed => self
                            .push_outcome(Outcome::Removed, &dirstate_node)?,
                        EntryState::Merged => self
                            .push_outcome(Outcome::Modified, &dirstate_node)?,
                        EntryState::Normal => self
                            .handle_normal_file(&dirstate_node, fs_metadata)?,
                    }
                } else {
                    // `node.entry.is_none()` indicates a "directory"
                    // node, but the filesystem has a file
                    self.mark_unknown_or_ignored(
                        has_ignored_ancestor,
                        hg_path,
                    );
                }
            }

            for child_node in dirstate_node.children(self.dmap.on_disk)?.iter()
            {
                self.traverse_dirstate_only(child_node)?
            }
        }
        Ok(())
    }

    fn maybe_save_directory_mtime(
        &self,
        children_all_have_dirstate_node_or_are_ignored: bool,
        directory_metadata: &std::fs::Metadata,
        dirstate_node: NodeRef<'tree, 'on_disk>,
    ) -> Result<(), DirstateV2ParseError> {
        if children_all_have_dirstate_node_or_are_ignored {
            // All filesystem directory entries from `read_dir` have a
            // corresponding node in the dirstate, so we can reconstitute the
            // names of those entries without calling `read_dir` again.
            if let (Some(status_start), Ok(directory_mtime)) = (
                &self.filesystem_time_at_status_start,
                directory_metadata.modified(),
            ) {
                // Although the Rust standard library’s `SystemTime` type
                // has nanosecond precision, the times reported for a
                // directory’s (or file’s) modified time may have lower
                // resolution based on the filesystem (for example ext3
                // only stores integer seconds), kernel (see
                // https://stackoverflow.com/a/14393315/1162888), etc.
                if &directory_mtime >= status_start {
                    // The directory was modified too recently, don’t cache its
                    // `read_dir` results.
                    //
                    // A timeline like this is possible:
                    //
                    // 1. A change to this directory (direct child was
                    //    added or removed) cause its mtime to be set
                    //    (possibly truncated) to `directory_mtime`
                    // 2. This `status` algorithm calls `read_dir`
                    // 3. An other change is made to the same directory is
                    //    made so that calling `read_dir` agin would give
                    //    different results, but soon enough after 1. that
                    //    the mtime stays the same
                    //
                    // On a system where the time resolution poor, this
                    // scenario is not unlikely if all three steps are caused
                    // by the same script.
                } else {
                    // We’ve observed (through `status_start`) that time has
                    // “progressed” since `directory_mtime`, so any further
                    // change to this directory is extremely likely to cause a
                    // different mtime.
                    //
                    // Having the same mtime again is not entirely impossible
                    // since the system clock is not monotonous. It could jump
                    // backward to some point before `directory_mtime`, then a
                    // directory change could potentially happen during exactly
                    // the wrong tick.
                    //
                    // We deem this scenario (unlike the previous one) to be
                    // unlikely enough in practice.
                    let truncated = TruncatedTimestamp::from(directory_mtime);
                    let is_up_to_date = if let Some(cached) =
                        dirstate_node.cached_directory_mtime()?
                    {
                        cached.likely_equal(truncated)
                    } else {
                        false
                    };
                    if !is_up_to_date {
                        let hg_path = dirstate_node
                            .full_path_borrowed(self.dmap.on_disk)?
                            .detach_from_tree();
                        self.new_cachable_directories
                            .lock()
                            .unwrap()
                            .push((hg_path, truncated))
                    }
                }
            }
        }
        Ok(())
    }

    /// A file with `EntryState::Normal` in the dirstate was found in the
    /// filesystem
    fn handle_normal_file(
        &self,
        dirstate_node: &NodeRef<'tree, 'on_disk>,
        fs_metadata: &std::fs::Metadata,
    ) -> Result<(), DirstateV2ParseError> {
        // Keep the low 31 bits
        fn truncate_u64(value: u64) -> i32 {
            (value & 0x7FFF_FFFF) as i32
        }

        let entry = dirstate_node
            .entry()?
            .expect("handle_normal_file called with entry-less node");
        let mode_changed =
            || self.options.check_exec && entry.mode_changed(fs_metadata);
        let size = entry.size();
        let size_changed = size != truncate_u64(fs_metadata.len());
        if size >= 0 && size_changed && fs_metadata.file_type().is_symlink() {
            // issue6456: Size returned may be longer due to encryption
            // on EXT-4 fscrypt. TODO maybe only do it on EXT4?
            self.push_outcome(Outcome::Unsure, dirstate_node)?
        } else if dirstate_node.has_copy_source()
            || entry.is_from_other_parent()
            || (size >= 0 && (size_changed || mode_changed()))
        {
            self.push_outcome(Outcome::Modified, dirstate_node)?
        } else {
            let mtime_looks_clean;
            if let Some(dirstate_mtime) = entry.truncated_mtime() {
                let fs_mtime = TruncatedTimestamp::for_mtime_of(fs_metadata)
                    .expect("OS/libc does not support mtime?");
                // There might be a change in the future if for example the
                // internal clock become off while process run, but this is a
                // case where the issues the user would face
                // would be a lot worse and there is nothing we
                // can really do.
                mtime_looks_clean = fs_mtime.likely_equal(dirstate_mtime)
            } else {
                // No mtime in the dirstate entry
                mtime_looks_clean = false
            };
            if !mtime_looks_clean {
                self.push_outcome(Outcome::Unsure, dirstate_node)?
            } else if self.options.list_clean {
                self.push_outcome(Outcome::Clean, dirstate_node)?
            }
        }
        Ok(())
    }

    /// A node in the dirstate tree has no corresponding filesystem entry
    fn traverse_dirstate_only(
        &self,
        dirstate_node: NodeRef<'tree, 'on_disk>,
    ) -> Result<(), DirstateV2ParseError> {
        self.check_for_outdated_directory_cache(&dirstate_node)?;
        self.mark_removed_or_deleted_if_file(&dirstate_node)?;
        dirstate_node
            .children(self.dmap.on_disk)?
            .par_iter()
            .map(|child_node| self.traverse_dirstate_only(child_node))
            .collect()
    }

    /// A node in the dirstate tree has no corresponding *file* on the
    /// filesystem
    ///
    /// Does nothing on a "directory" node
    fn mark_removed_or_deleted_if_file(
        &self,
        dirstate_node: &NodeRef<'tree, 'on_disk>,
    ) -> Result<(), DirstateV2ParseError> {
        if let Some(state) = dirstate_node.state()? {
            let path = dirstate_node.full_path(self.dmap.on_disk)?;
            if self.matcher.matches(path) {
                if let EntryState::Removed = state {
                    self.push_outcome(Outcome::Removed, dirstate_node)?
                } else {
                    self.push_outcome(Outcome::Deleted, &dirstate_node)?
                }
            }
        }
        Ok(())
    }

    /// Something in the filesystem has no corresponding dirstate node
    ///
    /// Returns whether that path is ignored
    fn traverse_fs_only(
        &self,
        has_ignored_ancestor: bool,
        directory_hg_path: &HgPath,
        fs_entry: &DirEntry,
    ) -> bool {
        let hg_path = directory_hg_path.join(&fs_entry.base_name);
        let file_type = fs_entry.metadata.file_type();
        let file_or_symlink = file_type.is_file() || file_type.is_symlink();
        if file_type.is_dir() {
            let is_ignored =
                has_ignored_ancestor || (self.ignore_fn)(&hg_path);
            let traverse_children = if is_ignored {
                // Descendants of an ignored directory are all ignored
                self.options.list_ignored
            } else {
                // Descendants of an unknown directory may be either unknown or
                // ignored
                self.options.list_unknown || self.options.list_ignored
            };
            if traverse_children {
                let is_at_repo_root = false;
                if let Ok(children_fs_entries) = self.read_dir(
                    &hg_path,
                    &fs_entry.full_path,
                    is_at_repo_root,
                ) {
                    children_fs_entries.par_iter().for_each(|child_fs_entry| {
                        self.traverse_fs_only(
                            is_ignored,
                            &hg_path,
                            child_fs_entry,
                        );
                    })
                }
            }
            if self.options.collect_traversed_dirs {
                self.outcome.lock().unwrap().traversed.push(hg_path.into())
            }
            is_ignored
        } else {
            if file_or_symlink {
                if self.matcher.matches(&hg_path) {
                    self.mark_unknown_or_ignored(
                        has_ignored_ancestor,
                        &BorrowedPath::InMemory(&hg_path),
                    )
                } else {
                    // We haven’t computed whether this path is ignored. It
                    // might not be, and a future run of status might have a
                    // different matcher that matches it. So treat it as not
                    // ignored. That is, inhibit readdir caching of the parent
                    // directory.
                    false
                }
            } else {
                // This is neither a directory, a plain file, or a symlink.
                // Treat it like an ignored file.
                true
            }
        }
    }

    /// Returns whether that path is ignored
    fn mark_unknown_or_ignored(
        &self,
        has_ignored_ancestor: bool,
        hg_path: &BorrowedPath<'_, 'on_disk>,
    ) -> bool {
        let is_ignored = has_ignored_ancestor || (self.ignore_fn)(&hg_path);
        if is_ignored {
            if self.options.list_ignored {
                self.push_outcome_without_copy_source(
                    Outcome::Ignored,
                    hg_path,
                )
            }
        } else {
            if self.options.list_unknown {
                self.push_outcome_without_copy_source(
                    Outcome::Unknown,
                    hg_path,
                )
            }
        }
        is_ignored
    }
}

struct DirEntry {
    base_name: HgPathBuf,
    full_path: PathBuf,
    metadata: std::fs::Metadata,
}

impl DirEntry {
    /// Returns **unsorted** entries in the given directory, with name and
    /// metadata.
    ///
    /// If a `.hg` sub-directory is encountered:
    ///
    /// * At the repository root, ignore that sub-directory
    /// * Elsewhere, we’re listing the content of a sub-repo. Return an empty
    ///   list instead.
    fn read_dir(path: &Path, is_at_repo_root: bool) -> io::Result<Vec<Self>> {
        let mut results = Vec::new();
        for entry in path.read_dir()? {
            let entry = entry?;
            let metadata = entry.metadata()?;
            let name = get_bytes_from_os_string(entry.file_name());
            // FIXME don't do this when cached
            if name == b".hg" {
                if is_at_repo_root {
                    // Skip the repo’s own .hg (might be a symlink)
                    continue;
                } else if metadata.is_dir() {
                    // A .hg sub-directory at another location means a subrepo,
                    // skip it entirely.
                    return Ok(Vec::new());
                }
            }
            results.push(DirEntry {
                base_name: name.into(),
                full_path: entry.path(),
                metadata,
            })
        }
        Ok(results)
    }
}

/// Return the `mtime` of a temporary file newly-created in the `.hg` directory
/// of the give repository.
///
/// This is similar to `SystemTime::now()`, with the result truncated to the
/// same time resolution as other files’ modification times. Using `.hg`
/// instead of the system’s default temporary directory (such as `/tmp`) makes
/// it more likely the temporary file is in the same disk partition as contents
/// of the working directory, which can matter since different filesystems may
/// store timestamps with different resolutions.
///
/// This may fail, typically if we lack write permissions. In that case we
/// should continue the `status()` algoritm anyway and consider the current
/// date/time to be unknown.
fn filesystem_now(repo_root: &Path) -> Result<SystemTime, io::Error> {
    tempfile::tempfile_in(repo_root.join(".hg"))?
        .metadata()?
        .modified()
}

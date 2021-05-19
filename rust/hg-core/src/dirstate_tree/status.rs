use crate::dirstate::status::IgnoreFnType;
use crate::dirstate_tree::dirstate_map::ChildNodes;
use crate::dirstate_tree::dirstate_map::DirstateMap;
use crate::dirstate_tree::dirstate_map::Node;
use crate::matchers::get_ignore_function;
use crate::matchers::Matcher;
use crate::utils::files::get_bytes_from_os_string;
use crate::utils::hg_path::HgPath;
use crate::BadMatch;
use crate::DirstateStatus;
use crate::EntryState;
use crate::HgPathBuf;
use crate::PatternFileWarning;
use crate::StatusError;
use crate::StatusOptions;
use micro_timer::timed;
use rayon::prelude::*;
use std::borrow::Cow;
use std::io;
use std::path::Path;
use std::path::PathBuf;
use std::sync::Mutex;

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
pub fn status<'tree>(
    dmap: &'tree mut DirstateMap,
    matcher: &(dyn Matcher + Sync),
    root_dir: PathBuf,
    ignore_files: Vec<PathBuf>,
    options: StatusOptions,
) -> Result<(DirstateStatus<'tree>, Vec<PatternFileWarning>), StatusError> {
    let (ignore_fn, warnings): (IgnoreFnType, _) =
        if options.list_ignored || options.list_unknown {
            get_ignore_function(ignore_files, &root_dir)?
        } else {
            (Box::new(|&_| true), vec![])
        };

    let common = StatusCommon {
        options,
        matcher,
        ignore_fn,
        outcome: Mutex::new(DirstateStatus::default()),
    };
    let is_at_repo_root = true;
    let hg_path = HgPath::new("");
    let has_ignored_ancestor = false;
    common.traverse_fs_directory_and_dirstate(
        has_ignored_ancestor,
        &dmap.root,
        hg_path,
        &root_dir,
        is_at_repo_root,
    );
    Ok((common.outcome.into_inner().unwrap(), warnings))
}

/// Bag of random things needed by various parts of the algorithm. Reduces the
/// number of parameters passed to functions.
struct StatusCommon<'tree, 'a> {
    options: StatusOptions,
    matcher: &'a (dyn Matcher + Sync),
    ignore_fn: IgnoreFnType<'a>,
    outcome: Mutex<DirstateStatus<'tree>>,
}

impl<'tree, 'a> StatusCommon<'tree, 'a> {
    fn read_dir(
        &self,
        hg_path: &HgPath,
        fs_path: &Path,
        is_at_repo_root: bool,
    ) -> Result<Vec<DirEntry>, ()> {
        DirEntry::read_dir(fs_path, is_at_repo_root).map_err(|error| {
            let errno = error.raw_os_error().expect("expected real OS error");
            self.outcome
                .lock()
                .unwrap()
                .bad
                .push((hg_path.to_owned().into(), BadMatch::OsError(errno)))
        })
    }

    fn traverse_fs_directory_and_dirstate(
        &self,
        has_ignored_ancestor: bool,
        dirstate_nodes: &'tree ChildNodes,
        directory_hg_path: &'tree HgPath,
        directory_fs_path: &Path,
        is_at_repo_root: bool,
    ) {
        let mut fs_entries = if let Ok(entries) = self.read_dir(
            directory_hg_path,
            directory_fs_path,
            is_at_repo_root,
        ) {
            entries
        } else {
            return;
        };

        // `merge_join_by` requires both its input iterators to be sorted:

        let dirstate_nodes = Node::sorted(dirstate_nodes);
        // `sort_unstable_by_key` doesn’t allow keys borrowing from the value:
        // https://github.com/rust-lang/rust/issues/34162
        fs_entries.sort_unstable_by(|e1, e2| e1.base_name.cmp(&e2.base_name));

        itertools::merge_join_by(
            dirstate_nodes,
            &fs_entries,
            |(full_path, _node), fs_entry| {
                full_path.base_name().cmp(&fs_entry.base_name)
            },
        )
        .par_bridge()
        .for_each(|pair| {
            use itertools::EitherOrBoth::*;
            match pair {
                Both((hg_path, dirstate_node), fs_entry) => {
                    self.traverse_fs_and_dirstate(
                        fs_entry,
                        hg_path.full_path(),
                        dirstate_node,
                        has_ignored_ancestor,
                    );
                }
                Left((hg_path, dirstate_node)) => self.traverse_dirstate_only(
                    hg_path.full_path(),
                    dirstate_node,
                ),
                Right(fs_entry) => self.traverse_fs_only(
                    has_ignored_ancestor,
                    directory_hg_path,
                    fs_entry,
                ),
            }
        })
    }

    fn traverse_fs_and_dirstate(
        &self,
        fs_entry: &DirEntry,
        hg_path: &'tree HgPath,
        dirstate_node: &'tree Node,
        has_ignored_ancestor: bool,
    ) {
        let file_type = fs_entry.metadata.file_type();
        let file_or_symlink = file_type.is_file() || file_type.is_symlink();
        if !file_or_symlink {
            // If we previously had a file here, it was removed (with
            // `hg rm` or similar) or deleted before it could be
            // replaced by a directory or something else.
            self.mark_removed_or_deleted_if_file(
                hg_path,
                dirstate_node.state(),
            );
        }
        if file_type.is_dir() {
            if self.options.collect_traversed_dirs {
                self.outcome.lock().unwrap().traversed.push(hg_path.into())
            }
            let is_ignored = has_ignored_ancestor || (self.ignore_fn)(hg_path);
            let is_at_repo_root = false;
            self.traverse_fs_directory_and_dirstate(
                is_ignored,
                &dirstate_node.children,
                hg_path,
                &fs_entry.full_path,
                is_at_repo_root,
            );
        } else {
            if file_or_symlink && self.matcher.matches(hg_path) {
                let full_path = Cow::from(hg_path);
                if let Some(entry) = &dirstate_node.entry {
                    match entry.state {
                        EntryState::Added => {
                            self.outcome.lock().unwrap().added.push(full_path)
                        }
                        EntryState::Removed => self
                            .outcome
                            .lock()
                            .unwrap()
                            .removed
                            .push(full_path),
                        EntryState::Merged => self
                            .outcome
                            .lock()
                            .unwrap()
                            .modified
                            .push(full_path),
                        EntryState::Normal => {
                            self.handle_normal_file(
                                full_path,
                                dirstate_node,
                                entry,
                                fs_entry,
                            );
                        }
                        // This variant is not used in DirstateMap
                        // nodes
                        EntryState::Unknown => unreachable!(),
                    }
                } else {
                    // `node.entry.is_none()` indicates a "directory"
                    // node, but the filesystem has a file
                    self.mark_unknown_or_ignored(
                        has_ignored_ancestor,
                        full_path,
                    )
                }
            }

            for (child_hg_path, child_node) in &dirstate_node.children {
                self.traverse_dirstate_only(
                    child_hg_path.full_path(),
                    child_node,
                )
            }
        }
    }

    /// A file with `EntryState::Normal` in the dirstate was found in the
    /// filesystem
    fn handle_normal_file(
        &self,
        full_path: Cow<'tree, HgPath>,
        dirstate_node: &Node,
        entry: &crate::DirstateEntry,
        fs_entry: &DirEntry,
    ) {
        // Keep the low 31 bits
        fn truncate_u64(value: u64) -> i32 {
            (value & 0x7FFF_FFFF) as i32
        }
        fn truncate_i64(value: i64) -> i32 {
            (value & 0x7FFF_FFFF) as i32
        }

        let mode_changed = || {
            self.options.check_exec && entry.mode_changed(&fs_entry.metadata)
        };
        let size_changed = entry.size != truncate_u64(fs_entry.metadata.len());
        if entry.size >= 0
            && size_changed
            && fs_entry.metadata.file_type().is_symlink()
        {
            // issue6456: Size returned may be longer due to encryption
            // on EXT-4 fscrypt. TODO maybe only do it on EXT4?
            self.outcome.lock().unwrap().unsure.push(full_path)
        } else if dirstate_node.copy_source.is_some()
            || entry.is_from_other_parent()
            || (entry.size >= 0 && (size_changed || mode_changed()))
        {
            self.outcome.lock().unwrap().modified.push(full_path)
        } else {
            let mtime = mtime_seconds(&fs_entry.metadata);
            if truncate_i64(mtime) != entry.mtime
                || mtime == self.options.last_normal_time
            {
                self.outcome.lock().unwrap().unsure.push(full_path)
            } else if self.options.list_clean {
                self.outcome.lock().unwrap().clean.push(full_path)
            }
        }
    }

    /// A node in the dirstate tree has no corresponding filesystem entry
    fn traverse_dirstate_only(
        &self,
        hg_path: &'tree HgPath,
        dirstate_node: &'tree Node,
    ) {
        self.mark_removed_or_deleted_if_file(hg_path, dirstate_node.state());
        dirstate_node.children.par_iter().for_each(
            |(child_hg_path, child_node)| {
                self.traverse_dirstate_only(
                    child_hg_path.full_path(),
                    child_node,
                )
            },
        )
    }

    /// A node in the dirstate tree has no corresponding *file* on the
    /// filesystem
    ///
    /// Does nothing on a "directory" node
    fn mark_removed_or_deleted_if_file(
        &self,
        hg_path: &'tree HgPath,
        dirstate_node_state: Option<EntryState>,
    ) {
        if let Some(state) = dirstate_node_state {
            if self.matcher.matches(hg_path) {
                if let EntryState::Removed = state {
                    self.outcome.lock().unwrap().removed.push(hg_path.into())
                } else {
                    self.outcome.lock().unwrap().deleted.push(hg_path.into())
                }
            }
        }
    }

    /// Something in the filesystem has no corresponding dirstate node
    fn traverse_fs_only(
        &self,
        has_ignored_ancestor: bool,
        directory_hg_path: &HgPath,
        fs_entry: &DirEntry,
    ) {
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
                        )
                    })
                }
            }
            if self.options.collect_traversed_dirs {
                self.outcome.lock().unwrap().traversed.push(hg_path.into())
            }
        } else if file_or_symlink && self.matcher.matches(&hg_path) {
            self.mark_unknown_or_ignored(has_ignored_ancestor, hg_path.into())
        }
    }

    fn mark_unknown_or_ignored(
        &self,
        has_ignored_ancestor: bool,
        hg_path: Cow<'tree, HgPath>,
    ) {
        let is_ignored = has_ignored_ancestor || (self.ignore_fn)(&hg_path);
        if is_ignored {
            if self.options.list_ignored {
                self.outcome.lock().unwrap().ignored.push(hg_path)
            }
        } else {
            if self.options.list_unknown {
                self.outcome.lock().unwrap().unknown.push(hg_path)
            }
        }
    }
}

#[cfg(unix)] // TODO
fn mtime_seconds(metadata: &std::fs::Metadata) -> i64 {
    // Going through `Metadata::modified()` would be portable, but would take
    // care to construct a `SystemTime` value with sub-second precision just
    // for us to throw that away here.
    use std::os::unix::fs::MetadataExt;
    metadata.mtime()
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

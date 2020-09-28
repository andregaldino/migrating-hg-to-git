// iter.rs
//
// Copyright 2020, Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use super::node::{Node, NodeKind};
use super::tree::Tree;
use crate::dirstate::dirstate_tree::node::Directory;
use crate::dirstate::status::Dispatch;
use crate::utils::hg_path::{hg_path_to_path_buf, HgPath, HgPathBuf};
use crate::DirstateEntry;
use std::borrow::Cow;
use std::collections::VecDeque;
use std::iter::{FromIterator, FusedIterator};
use std::path::PathBuf;

impl FromIterator<(HgPathBuf, DirstateEntry)> for Tree {
    fn from_iter<T: IntoIterator<Item = (HgPathBuf, DirstateEntry)>>(
        iter: T,
    ) -> Self {
        let mut tree = Self::new();
        for (path, entry) in iter {
            tree.insert(path, entry);
        }
        tree
    }
}

/// Iterator of all entries in the dirstate tree.
///
/// It has no particular ordering.
pub struct Iter<'a> {
    to_visit: VecDeque<(Cow<'a, [u8]>, &'a Node)>,
}

impl<'a> Iter<'a> {
    pub fn new(node: &'a Node) -> Iter<'a> {
        let mut to_visit = VecDeque::new();
        to_visit.push_back((Cow::Borrowed(&b""[..]), node));
        Self { to_visit }
    }
}

impl<'a> Iterator for Iter<'a> {
    type Item = (HgPathBuf, DirstateEntry);

    fn next(&mut self) -> Option<Self::Item> {
        while let Some((base_path, node)) = self.to_visit.pop_front() {
            match &node.kind {
                NodeKind::Directory(dir) => {
                    add_children_to_visit(
                        &mut self.to_visit,
                        &base_path,
                        &dir,
                    );
                    if let Some(file) = &dir.was_file {
                        return Some((
                            HgPathBuf::from_bytes(&base_path),
                            file.entry,
                        ));
                    }
                }
                NodeKind::File(file) => {
                    if let Some(dir) = &file.was_directory {
                        add_children_to_visit(
                            &mut self.to_visit,
                            &base_path,
                            &dir,
                        );
                    }
                    return Some((
                        HgPathBuf::from_bytes(&base_path),
                        file.entry,
                    ));
                }
            }
        }
        None
    }
}

impl<'a> FusedIterator for Iter<'a> {}

/// Iterator of all entries in the dirstate tree, with a special filesystem
/// handling for the directories containing said entries.
///
/// It checks every directory on-disk to see if it has become a symlink, to
/// prevent a potential security issue.
/// Using this information, it may dispatch `status` information early: it
/// returns canonical paths along with `Shortcut`s, which are either a
/// `DirstateEntry` or a `Dispatch`, if the fate of said path has already been
/// determined.
///
/// Like `Iter`, it has no particular ordering.
pub struct FsIter<'a> {
    root_dir: PathBuf,
    to_visit: VecDeque<(Cow<'a, [u8]>, &'a Node)>,
    shortcuts: VecDeque<(HgPathBuf, StatusShortcut)>,
}

impl<'a> FsIter<'a> {
    pub fn new(node: &'a Node, root_dir: PathBuf) -> FsIter<'a> {
        let mut to_visit = VecDeque::new();
        to_visit.push_back((Cow::Borrowed(&b""[..]), node));
        Self {
            root_dir,
            to_visit,
            shortcuts: Default::default(),
        }
    }

    /// Mercurial tracks symlinks but *not* what they point to.
    /// If a directory is moved and symlinked:
    ///
    /// ```bash
    /// $ mkdir foo
    /// $ touch foo/a
    /// $ # commit...
    /// $ mv foo bar
    /// $ ln -s bar foo
    /// ```
    /// We need to dispatch the new symlink as `Unknown` and all the
    /// descendents of the directory it replace as `Deleted`.
    fn dispatch_symlinked_directory(
        &mut self,
        path: impl AsRef<HgPath>,
        node: &Node,
    ) {
        let path = path.as_ref();
        self.shortcuts.push_back((
            path.to_owned(),
            StatusShortcut::Dispatch(Dispatch::Unknown),
        ));
        for (file, _) in node.iter() {
            self.shortcuts.push_back((
                path.join(&file),
                StatusShortcut::Dispatch(Dispatch::Deleted),
            ));
        }
    }

    /// Returns `true` if the canonical `path` of a directory corresponds to a
    /// symlink on disk. It means it was moved and symlinked after the last
    /// dirstate update.
    ///
    /// # Special cases
    ///
    /// Returns `false` for the repository root.
    /// Returns `false` on io error, error handling is outside of the iterator.
    fn directory_became_symlink(&mut self, path: &HgPath) -> bool {
        if path.is_empty() {
            return false;
        }
        let filename_as_path = match hg_path_to_path_buf(&path) {
            Ok(p) => p,
            _ => return false,
        };
        let meta = self.root_dir.join(filename_as_path).symlink_metadata();
        match meta {
            Ok(ref m) if m.file_type().is_symlink() => true,
            _ => false,
        }
    }
}

/// Returned by `FsIter`, since the `Dispatch` of any given entry may already
/// be determined during the iteration. This is necessary for performance
/// reasons, since hierarchical information is needed to `Dispatch` an entire
/// subtree efficiently.
#[derive(Debug, Copy, Clone)]
pub enum StatusShortcut {
    /// A entry in the dirstate for further inspection
    Entry(DirstateEntry),
    /// The result of the status of the corresponding file
    Dispatch(Dispatch),
}

impl<'a> Iterator for FsIter<'a> {
    type Item = (HgPathBuf, StatusShortcut);

    fn next(&mut self) -> Option<Self::Item> {
        // If any paths have already been `Dispatch`-ed, return them
        if let Some(res) = self.shortcuts.pop_front() {
            return Some(res);
        }

        while let Some((base_path, node)) = self.to_visit.pop_front() {
            match &node.kind {
                NodeKind::Directory(dir) => {
                    let canonical_path = HgPath::new(&base_path);
                    if self.directory_became_symlink(canonical_path) {
                        // Potential security issue, don't do a normal
                        // traversal, force the results.
                        self.dispatch_symlinked_directory(
                            canonical_path,
                            &node,
                        );
                        continue;
                    }
                    add_children_to_visit(
                        &mut self.to_visit,
                        &base_path,
                        &dir,
                    );
                    if let Some(file) = &dir.was_file {
                        return Some((
                            HgPathBuf::from_bytes(&base_path),
                            StatusShortcut::Entry(file.entry),
                        ));
                    }
                }
                NodeKind::File(file) => {
                    if let Some(dir) = &file.was_directory {
                        add_children_to_visit(
                            &mut self.to_visit,
                            &base_path,
                            &dir,
                        );
                    }
                    return Some((
                        HgPathBuf::from_bytes(&base_path),
                        StatusShortcut::Entry(file.entry),
                    ));
                }
            }
        }

        None
    }
}

impl<'a> FusedIterator for FsIter<'a> {}

fn join_path<'a, 'b>(path: &'a [u8], other: &'b [u8]) -> Cow<'b, [u8]> {
    if path.is_empty() {
        other.into()
    } else {
        [path, &b"/"[..], other].concat().into()
    }
}

/// Adds all children of a given directory `dir` to the visit queue `to_visit`
/// prefixed by a `base_path`.
fn add_children_to_visit<'a>(
    to_visit: &mut VecDeque<(Cow<'a, [u8]>, &'a Node)>,
    base_path: &[u8],
    dir: &'a Directory,
) {
    to_visit.extend(dir.children.iter().map(|(path, child)| {
        let full_path = join_path(&base_path, &path);
        (full_path, child)
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::utils::hg_path::HgPath;
    use crate::{EntryState, FastHashMap};
    use std::collections::HashSet;

    #[test]
    fn test_iteration() {
        let mut tree = Tree::new();

        assert_eq!(
            tree.insert(
                HgPathBuf::from_bytes(b"foo/bar"),
                DirstateEntry {
                    state: EntryState::Merged,
                    mode: 41,
                    mtime: 42,
                    size: 43,
                }
            ),
            None
        );

        assert_eq!(
            tree.insert(
                HgPathBuf::from_bytes(b"foo2"),
                DirstateEntry {
                    state: EntryState::Merged,
                    mode: 40,
                    mtime: 41,
                    size: 42,
                }
            ),
            None
        );

        assert_eq!(
            tree.insert(
                HgPathBuf::from_bytes(b"foo/baz"),
                DirstateEntry {
                    state: EntryState::Normal,
                    mode: 0,
                    mtime: 0,
                    size: 0,
                }
            ),
            None
        );

        assert_eq!(
            tree.insert(
                HgPathBuf::from_bytes(b"foo/bap/nested"),
                DirstateEntry {
                    state: EntryState::Normal,
                    mode: 0,
                    mtime: 0,
                    size: 0,
                }
            ),
            None
        );

        assert_eq!(tree.len(), 4);

        let results: HashSet<_> =
            tree.iter().map(|(c, _)| c.to_owned()).collect();
        dbg!(&results);
        assert!(results.contains(HgPath::new(b"foo2")));
        assert!(results.contains(HgPath::new(b"foo/bar")));
        assert!(results.contains(HgPath::new(b"foo/baz")));
        assert!(results.contains(HgPath::new(b"foo/bap/nested")));

        let mut iter = tree.iter();
        assert!(iter.next().is_some());
        assert!(iter.next().is_some());
        assert!(iter.next().is_some());
        assert!(iter.next().is_some());
        assert_eq!(None, iter.next());
        assert_eq!(None, iter.next());
        drop(iter);

        assert_eq!(
            tree.insert(
                HgPathBuf::from_bytes(b"foo/bap/nested/a"),
                DirstateEntry {
                    state: EntryState::Normal,
                    mode: 0,
                    mtime: 0,
                    size: 0,
                }
            ),
            None
        );

        let results: FastHashMap<_, _> = tree.iter().collect();
        assert!(results.contains_key(HgPath::new(b"foo2")));
        assert!(results.contains_key(HgPath::new(b"foo/bar")));
        assert!(results.contains_key(HgPath::new(b"foo/baz")));
        // Is a dir but `was_file`, so it's listed as a removed file
        assert!(results.contains_key(HgPath::new(b"foo/bap/nested")));
        assert!(results.contains_key(HgPath::new(b"foo/bap/nested/a")));

        // insert removed file (now directory) after nested file
        assert_eq!(
            tree.insert(
                HgPathBuf::from_bytes(b"a/a"),
                DirstateEntry {
                    state: EntryState::Normal,
                    mode: 0,
                    mtime: 0,
                    size: 0,
                }
            ),
            None
        );

        // `insert` returns `None` for a directory
        assert_eq!(
            tree.insert(
                HgPathBuf::from_bytes(b"a"),
                DirstateEntry {
                    state: EntryState::Removed,
                    mode: 0,
                    mtime: 0,
                    size: 0,
                }
            ),
            None
        );

        let results: FastHashMap<_, _> = tree.iter().collect();
        assert!(results.contains_key(HgPath::new(b"a")));
        assert!(results.contains_key(HgPath::new(b"a/a")));
    }
}

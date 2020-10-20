// tree.rs
//
// Copyright 2020, Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use super::iter::Iter;
use super::node::{Directory, Node, NodeKind};
use crate::dirstate::dirstate_tree::iter::FsIter;
use crate::dirstate::dirstate_tree::node::{InsertResult, RemoveResult};
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::DirstateEntry;
use std::path::PathBuf;

/// A specialized tree to represent the Mercurial dirstate.
///
/// # Advantages over a flat structure
///
/// The dirstate is inherently hierarchical, since it's a representation of the
/// file structure of the project. The current dirstate format is flat, and
/// while that affords us potentially great (unordered) iteration speeds, the
/// need to retrieve a given path is great enough that you need some kind of
/// hashmap or tree in a lot of cases anyway.
///
/// Going with a tree allows us to be smarter:
///   - Skipping an ignored directory means we don't visit its entire subtree
///   - Security auditing does not need to reconstruct paths backwards to check
///     for symlinked directories, this can be done during the iteration in a
///     very efficient fashion
///   - We don't need to build the directory information in another struct,
///     simplifying the code a lot, reducing the memory footprint and
///     potentially going faster depending on the implementation.
///   - We can use it to store a (platform-dependent) caching mechanism [1]
///   - And probably other types of optimizations.
///
/// Only the first two items in this list are implemented as of this commit.
///
/// [1]: https://www.mercurial-scm.org/wiki/DirsCachePlan
///
///
/// # Structure
///
/// It's a prefix (radix) tree with no fixed arity, with a granularity of a
/// folder, allowing it to mimic a filesystem hierarchy:
///
/// ```text
/// foo/bar
/// foo/baz
/// test
/// ```
/// Will be represented (simplified) by:
///
/// ```text
/// Directory(root):
///   - File("test")
///   - Directory("foo"):
///     - File("bar")
///     - File("baz")
/// ```
///
/// Moreover, it is special-cased for storing the dirstate and as such handles
/// cases that a simple `HashMap` would handle, but while preserving the
/// hierarchy.
/// For example:
///
/// ```shell
/// $ touch foo
/// $ hg add foo
/// $ hg commit -m "foo"
/// $ hg remove foo
/// $ rm foo
/// $ mkdir foo
/// $ touch foo/a
/// $ hg add foo/a
/// $ hg status
///   R foo
///   A foo/a
/// ```
/// To represent this in a tree, one needs to keep track of whether any given
/// file was a directory and whether any given directory was a file at the last
/// dirstate update. This tree stores that information, but only in the right
/// circumstances by respecting the high-level rules that prevent nonsensical
/// structures to exist:
///     - a file can only be added as a child of another file if the latter is
///       marked as `Removed`
///     - a file cannot replace a folder unless all its descendents are removed
///
/// This second rule is not checked by the tree for performance reasons, and
/// because high-level logic already prevents that state from happening.
///
/// # Ordering
///
/// It makes no guarantee of ordering for now.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Tree {
    pub root: Node,
    files_count: usize,
}

impl Tree {
    pub fn new() -> Self {
        Self {
            root: Node {
                kind: NodeKind::Directory(Directory {
                    was_file: None,
                    children: Default::default(),
                }),
            },
            files_count: 0,
        }
    }

    /// How many files (not directories) are stored in the tree, including ones
    /// marked as `Removed`.
    pub fn len(&self) -> usize {
        self.files_count
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Inserts a file in the tree and returns the previous entry if any.
    pub fn insert(
        &mut self,
        path: impl AsRef<HgPath>,
        kind: DirstateEntry,
    ) -> Option<DirstateEntry> {
        let old = self.insert_node(path, kind);
        match old?.kind {
            NodeKind::Directory(_) => None,
            NodeKind::File(f) => Some(f.entry),
        }
    }

    /// Low-level insertion method that returns the previous node (directories
    /// included).
    fn insert_node(
        &mut self,
        path: impl AsRef<HgPath>,
        kind: DirstateEntry,
    ) -> Option<Node> {
        let InsertResult {
            did_insert,
            old_entry,
        } = self.root.insert(path.as_ref().as_bytes(), kind);
        self.files_count += if did_insert { 1 } else { 0 };
        old_entry
    }

    /// Returns a reference to a node if it exists.
    pub fn get_node(&self, path: impl AsRef<HgPath>) -> Option<&Node> {
        self.root.get(path.as_ref().as_bytes())
    }

    /// Returns a reference to the entry corresponding to `path` if it exists.
    pub fn get(&self, path: impl AsRef<HgPath>) -> Option<&DirstateEntry> {
        if let Some(node) = self.get_node(&path) {
            return match &node.kind {
                NodeKind::Directory(d) => {
                    d.was_file.as_ref().map(|f| &f.entry)
                }
                NodeKind::File(f) => Some(&f.entry),
            };
        }
        None
    }

    /// Returns `true` if an entry is found for the given `path`.
    pub fn contains_key(&self, path: impl AsRef<HgPath>) -> bool {
        self.get(path).is_some()
    }

    /// Returns a mutable reference to the entry corresponding to `path` if it
    /// exists.
    pub fn get_mut(
        &mut self,
        path: impl AsRef<HgPath>,
    ) -> Option<&mut DirstateEntry> {
        if let Some(kind) = self.root.get_mut(path.as_ref().as_bytes()) {
            return match kind {
                NodeKind::Directory(d) => {
                    d.was_file.as_mut().map(|f| &mut f.entry)
                }
                NodeKind::File(f) => Some(&mut f.entry),
            };
        }
        None
    }

    /// Returns an iterator over the paths and corresponding entries in the
    /// tree.
    pub fn iter(&self) -> Iter {
        Iter::new(&self.root)
    }

    /// Returns an iterator of all entries in the tree, with a special
    /// filesystem handling for the directories containing said entries. See
    /// the documentation of `FsIter` for more.
    pub fn fs_iter(&self, root_dir: PathBuf) -> FsIter {
        FsIter::new(&self.root, root_dir)
    }

    /// Remove the entry at `path` and returns it, if it exists.
    pub fn remove(
        &mut self,
        path: impl AsRef<HgPath>,
    ) -> Option<DirstateEntry> {
        let RemoveResult { old_entry, .. } =
            self.root.remove(path.as_ref().as_bytes());
        self.files_count = self
            .files_count
            .checked_sub(if old_entry.is_some() { 1 } else { 0 })
            .expect("removed too many files");
        old_entry
    }
}

impl<P: AsRef<HgPath>> Extend<(P, DirstateEntry)> for Tree {
    fn extend<T: IntoIterator<Item = (P, DirstateEntry)>>(&mut self, iter: T) {
        for (path, entry) in iter {
            self.insert(path, entry);
        }
    }
}

impl<'a> IntoIterator for &'a Tree {
    type Item = (HgPathBuf, DirstateEntry);
    type IntoIter = Iter<'a>;

    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dirstate::dirstate_tree::node::File;
    use crate::{EntryState, FastHashMap};
    use pretty_assertions::assert_eq;

    impl Node {
        /// Shortcut for getting children of a node in tests.
        fn children(&self) -> Option<&FastHashMap<Vec<u8>, Node>> {
            match &self.kind {
                NodeKind::Directory(d) => Some(&d.children),
                NodeKind::File(_) => None,
            }
        }
    }

    #[test]
    fn test_dirstate_tree() {
        let mut tree = Tree::new();

        assert_eq!(
            tree.insert_node(
                HgPath::new(b"we/p"),
                DirstateEntry {
                    state: EntryState::Normal,
                    mode: 0,
                    mtime: 0,
                    size: 0
                }
            ),
            None
        );
        dbg!(&tree);
        assert!(tree.get_node(HgPath::new(b"we")).is_some());
        let entry = DirstateEntry {
            state: EntryState::Merged,
            mode: 41,
            mtime: 42,
            size: 43,
        };
        assert_eq!(tree.insert_node(HgPath::new(b"foo/bar"), entry), None);
        assert_eq!(
            tree.get_node(HgPath::new(b"foo/bar")),
            Some(&Node {
                kind: NodeKind::File(File {
                    was_directory: None,
                    entry
                })
            })
        );
        // We didn't override the first entry we made
        assert!(tree.get_node(HgPath::new(b"we")).is_some(),);
        // Inserting the same key again
        assert_eq!(
            tree.insert_node(HgPath::new(b"foo/bar"), entry),
            Some(Node {
                kind: NodeKind::File(File {
                    was_directory: None,
                    entry
                }),
            })
        );
        // Inserting the two levels deep
        assert_eq!(tree.insert_node(HgPath::new(b"foo/bar/baz"), entry), None);
        // Getting a file "inside a file" should return `None`
        assert_eq!(tree.get_node(HgPath::new(b"foo/bar/baz/bap"),), None);

        assert_eq!(
            tree.insert_node(HgPath::new(b"wasdir/subfile"), entry),
            None,
        );
        let removed_entry = DirstateEntry {
            state: EntryState::Removed,
            mode: 0,
            mtime: 0,
            size: 0,
        };
        assert!(tree
            .insert_node(HgPath::new(b"wasdir"), removed_entry)
            .is_some());

        assert_eq!(
            tree.get_node(HgPath::new(b"wasdir")),
            Some(&Node {
                kind: NodeKind::File(File {
                    was_directory: Some(Box::new(Directory {
                        was_file: None,
                        children: [(
                            b"subfile".to_vec(),
                            Node {
                                kind: NodeKind::File(File {
                                    was_directory: None,
                                    entry,
                                })
                            }
                        )]
                        .to_vec()
                        .into_iter()
                        .collect()
                    })),
                    entry: removed_entry
                })
            })
        );

        assert!(tree.get(HgPath::new(b"wasdir/subfile")).is_some())
    }

    #[test]
    fn test_insert_removed() {
        let mut tree = Tree::new();
        let entry = DirstateEntry {
            state: EntryState::Merged,
            mode: 1,
            mtime: 2,
            size: 3,
        };
        let removed_entry = DirstateEntry {
            state: EntryState::Removed,
            mode: 10,
            mtime: 20,
            size: 30,
        };
        assert_eq!(tree.insert_node(HgPath::new(b"foo"), entry), None);
        assert_eq!(
            tree.insert_node(HgPath::new(b"foo/a"), removed_entry),
            None
        );
        // The insert should not turn `foo` into a directory as `foo` is not
        // `Removed`.
        match tree.get_node(HgPath::new(b"foo")).unwrap().kind {
            NodeKind::Directory(_) => panic!("should be a file"),
            NodeKind::File(_) => {}
        }

        let mut tree = Tree::new();
        let entry = DirstateEntry {
            state: EntryState::Merged,
            mode: 1,
            mtime: 2,
            size: 3,
        };
        let removed_entry = DirstateEntry {
            state: EntryState::Removed,
            mode: 10,
            mtime: 20,
            size: 30,
        };
        // The insert *should* turn `foo` into a directory as it is `Removed`.
        assert_eq!(tree.insert_node(HgPath::new(b"foo"), removed_entry), None);
        assert_eq!(tree.insert_node(HgPath::new(b"foo/a"), entry), None);
        match tree.get_node(HgPath::new(b"foo")).unwrap().kind {
            NodeKind::Directory(_) => {}
            NodeKind::File(_) => panic!("should be a directory"),
        }
    }

    #[test]
    fn test_get() {
        let mut tree = Tree::new();
        let entry = DirstateEntry {
            state: EntryState::Merged,
            mode: 1,
            mtime: 2,
            size: 3,
        };
        assert_eq!(tree.insert_node(HgPath::new(b"a/b/c"), entry), None);
        assert_eq!(tree.files_count, 1);
        assert_eq!(tree.get(HgPath::new(b"a/b/c")), Some(&entry));
        assert_eq!(tree.get(HgPath::new(b"a/b")), None);
        assert_eq!(tree.get(HgPath::new(b"a")), None);
        assert_eq!(tree.get(HgPath::new(b"a/b/c/d")), None);
        let entry2 = DirstateEntry {
            state: EntryState::Removed,
            mode: 0,
            mtime: 5,
            size: 1,
        };
        // was_directory
        assert_eq!(tree.insert(HgPath::new(b"a/b"), entry2), None);
        assert_eq!(tree.files_count, 2);
        assert_eq!(tree.get(HgPath::new(b"a/b")), Some(&entry2));
        assert_eq!(tree.get(HgPath::new(b"a/b/c")), Some(&entry));

        let mut tree = Tree::new();

        // was_file
        assert_eq!(tree.insert_node(HgPath::new(b"a"), entry), None);
        assert_eq!(tree.files_count, 1);
        assert_eq!(tree.insert_node(HgPath::new(b"a/b"), entry2), None);
        assert_eq!(tree.files_count, 2);
        assert_eq!(tree.get(HgPath::new(b"a/b")), Some(&entry2));
    }

    #[test]
    fn test_get_mut() {
        let mut tree = Tree::new();
        let mut entry = DirstateEntry {
            state: EntryState::Merged,
            mode: 1,
            mtime: 2,
            size: 3,
        };
        assert_eq!(tree.insert_node(HgPath::new(b"a/b/c"), entry), None);
        assert_eq!(tree.files_count, 1);
        assert_eq!(tree.get_mut(HgPath::new(b"a/b/c")), Some(&mut entry));
        assert_eq!(tree.get_mut(HgPath::new(b"a/b")), None);
        assert_eq!(tree.get_mut(HgPath::new(b"a")), None);
        assert_eq!(tree.get_mut(HgPath::new(b"a/b/c/d")), None);
        let mut entry2 = DirstateEntry {
            state: EntryState::Removed,
            mode: 0,
            mtime: 5,
            size: 1,
        };
        // was_directory
        assert_eq!(tree.insert(HgPath::new(b"a/b"), entry2), None);
        assert_eq!(tree.files_count, 2);
        assert_eq!(tree.get_mut(HgPath::new(b"a/b")), Some(&mut entry2));
        assert_eq!(tree.get_mut(HgPath::new(b"a/b/c")), Some(&mut entry));

        let mut tree = Tree::new();

        // was_file
        assert_eq!(tree.insert_node(HgPath::new(b"a"), entry), None);
        assert_eq!(tree.files_count, 1);
        assert_eq!(tree.insert_node(HgPath::new(b"a/b"), entry2), None);
        assert_eq!(tree.files_count, 2);
        assert_eq!(tree.get_mut(HgPath::new(b"a/b")), Some(&mut entry2));
    }

    #[test]
    fn test_remove() {
        let mut tree = Tree::new();
        assert_eq!(tree.files_count, 0);
        assert_eq!(tree.remove(HgPath::new(b"foo")), None);
        assert_eq!(tree.files_count, 0);

        let entry = DirstateEntry {
            state: EntryState::Normal,
            mode: 0,
            mtime: 0,
            size: 0,
        };
        assert_eq!(tree.insert_node(HgPath::new(b"a/b/c"), entry), None);
        assert_eq!(tree.files_count, 1);

        assert_eq!(tree.remove(HgPath::new(b"a/b/c")), Some(entry));
        assert_eq!(tree.files_count, 0);

        assert_eq!(tree.insert_node(HgPath::new(b"a/b/x"), entry), None);
        assert_eq!(tree.insert_node(HgPath::new(b"a/b/y"), entry), None);
        assert_eq!(tree.insert_node(HgPath::new(b"a/b/z"), entry), None);
        assert_eq!(tree.insert_node(HgPath::new(b"x"), entry), None);
        assert_eq!(tree.insert_node(HgPath::new(b"y"), entry), None);
        assert_eq!(tree.files_count, 5);

        assert_eq!(tree.remove(HgPath::new(b"a/b/x")), Some(entry));
        assert_eq!(tree.files_count, 4);
        assert_eq!(tree.remove(HgPath::new(b"a/b/x")), None);
        assert_eq!(tree.files_count, 4);
        assert_eq!(tree.remove(HgPath::new(b"a/b/y")), Some(entry));
        assert_eq!(tree.files_count, 3);
        assert_eq!(tree.remove(HgPath::new(b"a/b/z")), Some(entry));
        assert_eq!(tree.files_count, 2);

        assert_eq!(tree.remove(HgPath::new(b"x")), Some(entry));
        assert_eq!(tree.files_count, 1);
        assert_eq!(tree.remove(HgPath::new(b"y")), Some(entry));
        assert_eq!(tree.files_count, 0);

        // `a` should have been cleaned up, no more files anywhere in its
        // descendents
        assert_eq!(tree.get_node(HgPath::new(b"a")), None);
        assert_eq!(tree.root.children().unwrap().len(), 0);

        let removed_entry = DirstateEntry {
            state: EntryState::Removed,
            ..entry
        };
        assert_eq!(tree.insert(HgPath::new(b"a"), removed_entry), None);
        assert_eq!(tree.insert_node(HgPath::new(b"a/b/x"), entry), None);
        assert_eq!(tree.files_count, 2);
        dbg!(&tree);
        assert_eq!(tree.remove(HgPath::new(b"a")), Some(removed_entry));
        assert_eq!(tree.files_count, 1);
        dbg!(&tree);
        assert_eq!(tree.remove(HgPath::new(b"a/b/x")), Some(entry));
        assert_eq!(tree.files_count, 0);

        // The entire tree should have been cleaned up, no more files anywhere
        // in its descendents
        assert_eq!(tree.root.children().unwrap().len(), 0);

        let removed_entry = DirstateEntry {
            state: EntryState::Removed,
            ..entry
        };
        assert_eq!(tree.insert(HgPath::new(b"a"), entry), None);
        assert_eq!(
            tree.insert_node(HgPath::new(b"a/b/x"), removed_entry),
            None
        );
        assert_eq!(tree.files_count, 2);
        dbg!(&tree);
        assert_eq!(tree.remove(HgPath::new(b"a")), Some(entry));
        assert_eq!(tree.files_count, 1);
        dbg!(&tree);
        assert_eq!(tree.remove(HgPath::new(b"a/b/x")), Some(removed_entry));
        assert_eq!(tree.files_count, 0);

        dbg!(&tree);
        // The entire tree should have been cleaned up, no more files anywhere
        // in its descendents
        assert_eq!(tree.root.children().unwrap().len(), 0);

        assert_eq!(tree.insert(HgPath::new(b"d"), entry), None);
        assert_eq!(tree.insert(HgPath::new(b"d/d/d"), entry), None);
        assert_eq!(tree.files_count, 2);

        // Deleting the nested file should not delete the top directory as it
        // used to be a file
        assert_eq!(tree.remove(HgPath::new(b"d/d/d")), Some(entry));
        assert_eq!(tree.files_count, 1);
        assert!(tree.get_node(HgPath::new(b"d")).is_some());
        assert!(tree.remove(HgPath::new(b"d")).is_some());
        assert_eq!(tree.files_count, 0);

        // Deleting the nested file should not delete the top file (other way
        // around from the last case)
        assert_eq!(tree.insert(HgPath::new(b"a/a"), entry), None);
        assert_eq!(tree.files_count, 1);
        assert_eq!(tree.insert(HgPath::new(b"a"), entry), None);
        assert_eq!(tree.files_count, 2);
        dbg!(&tree);
        assert_eq!(tree.remove(HgPath::new(b"a/a")), Some(entry));
        assert_eq!(tree.files_count, 1);
        dbg!(&tree);
        assert!(tree.get_node(HgPath::new(b"a")).is_some());
        assert!(tree.get_node(HgPath::new(b"a/a")).is_none());
    }

    #[test]
    fn test_was_directory() {
        let mut tree = Tree::new();

        let entry = DirstateEntry {
            state: EntryState::Removed,
            mode: 0,
            mtime: 0,
            size: 0,
        };
        assert_eq!(tree.insert_node(HgPath::new(b"a/b/c"), entry), None);
        assert_eq!(tree.files_count, 1);

        assert!(tree.insert_node(HgPath::new(b"a"), entry).is_some());
        let new_a = tree.root.children().unwrap().get(&b"a".to_vec()).unwrap();

        match &new_a.kind {
            NodeKind::Directory(_) => panic!(),
            NodeKind::File(f) => {
                let dir = f.was_directory.clone().unwrap();
                let c = dir
                    .children
                    .get(&b"b".to_vec())
                    .unwrap()
                    .children()
                    .unwrap()
                    .get(&b"c".to_vec())
                    .unwrap();

                assert_eq!(
                    match &c.kind {
                        NodeKind::Directory(_) => panic!(),
                        NodeKind::File(f) => f.entry,
                    },
                    entry
                );
            }
        }
        assert_eq!(tree.files_count, 2);
        dbg!(&tree);
        assert_eq!(tree.remove(HgPath::new(b"a/b/c")), Some(entry));
        assert_eq!(tree.files_count, 1);
        dbg!(&tree);
        let a = tree.get_node(HgPath::new(b"a")).unwrap();
        match &a.kind {
            NodeKind::Directory(_) => panic!(),
            NodeKind::File(f) => {
                // Directory in `was_directory` was emptied, should be removed
                assert_eq!(f.was_directory, None);
            }
        }
    }
    #[test]
    fn test_extend() {
        let insertions = [
            (
                HgPathBuf::from_bytes(b"d"),
                DirstateEntry {
                    state: EntryState::Added,
                    mode: 0,
                    mtime: -1,
                    size: -1,
                },
            ),
            (
                HgPathBuf::from_bytes(b"b"),
                DirstateEntry {
                    state: EntryState::Normal,
                    mode: 33188,
                    mtime: 1599647984,
                    size: 2,
                },
            ),
            (
                HgPathBuf::from_bytes(b"a/a"),
                DirstateEntry {
                    state: EntryState::Normal,
                    mode: 33188,
                    mtime: 1599647984,
                    size: 2,
                },
            ),
            (
                HgPathBuf::from_bytes(b"d/d/d"),
                DirstateEntry {
                    state: EntryState::Removed,
                    mode: 0,
                    mtime: 0,
                    size: 0,
                },
            ),
        ]
        .to_vec();
        let mut tree = Tree::new();

        tree.extend(insertions.clone().into_iter());

        for (path, _) in &insertions {
            assert!(tree.contains_key(path), true);
        }
        assert_eq!(tree.files_count, 4);
    }
}

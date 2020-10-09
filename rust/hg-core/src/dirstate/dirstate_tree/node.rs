// node.rs
//
// Copyright 2020, Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use super::iter::Iter;
use crate::utils::hg_path::HgPathBuf;
use crate::{DirstateEntry, EntryState, FastHashMap};

/// Represents a filesystem directory in the dirstate tree
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Directory {
    /// Contains the old file information if it existed between changesets.
    /// Happens if a file `foo` is marked as removed, removed from the
    /// filesystem then a directory `foo` is created and at least one of its
    /// descendents is added to Mercurial.
    pub(super) was_file: Option<Box<File>>,
    pub(super) children: FastHashMap<Vec<u8>, Node>,
}

/// Represents a filesystem file (or symlink) in the dirstate tree
#[derive(Debug, Clone, PartialEq)]
pub struct File {
    /// Contains the old structure if it existed between changesets.
    /// Happens all descendents of `foo` marked as removed and removed from
    /// the filesystem, then a file `foo` is created and added to Mercurial.
    pub(super) was_directory: Option<Box<Directory>>,
    pub(super) entry: DirstateEntry,
}

#[derive(Debug, Clone, PartialEq)]
pub enum NodeKind {
    Directory(Directory),
    File(File),
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Node {
    pub kind: NodeKind,
}

impl Default for NodeKind {
    fn default() -> Self {
        NodeKind::Directory(Default::default())
    }
}

impl Node {
    pub fn insert(
        &mut self,
        path: &[u8],
        new_entry: DirstateEntry,
    ) -> InsertResult {
        let mut split = path.splitn(2, |&c| c == b'/');
        let head = split.next().unwrap_or(b"");
        let tail = split.next().unwrap_or(b"");

        // Are we're modifying the current file ? Is the the end of the path ?
        let is_current_file = tail.is_empty() && head.is_empty();

        // Potentially Replace the current file with a directory if it's marked
        // as `Removed`
        if !is_current_file {
            if let NodeKind::File(file) = &mut self.kind {
                if file.entry.state == EntryState::Removed {
                    self.kind = NodeKind::Directory(Directory {
                        was_file: Some(Box::from(file.clone())),
                        children: Default::default(),
                    })
                }
            }
        }
        match &mut self.kind {
            NodeKind::Directory(directory) => {
                Node::insert_in_directory(directory, new_entry, head, tail)
            }
            NodeKind::File(file) => {
                if is_current_file {
                    let new = Self {
                        kind: NodeKind::File(File {
                            entry: new_entry,
                            ..file.clone()
                        }),
                    };
                    InsertResult {
                        did_insert: false,
                        old_entry: Some(std::mem::replace(self, new)),
                    }
                } else {
                    match file.entry.state {
                        EntryState::Removed => {
                            unreachable!("Removed file turning into a directory was dealt with earlier")
                        }
                        _ => {
                            Node::insert_in_file(
                                file, new_entry, head, tail,
                            )
                        }
                    }
                }
            }
        }
    }

    /// The current file still exists and is not marked as `Removed`.
    /// Insert the entry in its `was_directory`.
    fn insert_in_file(
        file: &mut File,
        new_entry: DirstateEntry,
        head: &[u8],
        tail: &[u8],
    ) -> InsertResult {
        if let Some(d) = &mut file.was_directory {
            Node::insert_in_directory(d, new_entry, head, tail)
        } else {
            let mut dir = Directory {
                was_file: None,
                children: FastHashMap::default(),
            };
            let res =
                Node::insert_in_directory(&mut dir, new_entry, head, tail);
            file.was_directory = Some(Box::new(dir));
            res
        }
    }

    /// Insert an entry in the subtree of `directory`
    fn insert_in_directory(
        directory: &mut Directory,
        new_entry: DirstateEntry,
        head: &[u8],
        tail: &[u8],
    ) -> InsertResult {
        let mut res = InsertResult::default();

        if let Some(node) = directory.children.get_mut(head) {
            // Node exists
            match &mut node.kind {
                NodeKind::Directory(subdir) => {
                    if tail.is_empty() {
                        let becomes_file = Self {
                            kind: NodeKind::File(File {
                                was_directory: Some(Box::from(subdir.clone())),
                                entry: new_entry,
                            }),
                        };
                        let old_entry = directory
                            .children
                            .insert(head.to_owned(), becomes_file);
                        return InsertResult {
                            did_insert: true,
                            old_entry,
                        };
                    } else {
                        res = node.insert(tail, new_entry);
                    }
                }
                NodeKind::File(_) => {
                    res = node.insert(tail, new_entry);
                }
            }
        } else if tail.is_empty() {
            // File does not already exist
            directory.children.insert(
                head.to_owned(),
                Self {
                    kind: NodeKind::File(File {
                        was_directory: None,
                        entry: new_entry,
                    }),
                },
            );
            res.did_insert = true;
        } else {
            // Directory does not already exist
            let mut nested = Self {
                kind: NodeKind::Directory(Directory {
                    was_file: None,
                    children: Default::default(),
                }),
            };
            res = nested.insert(tail, new_entry);
            directory.children.insert(head.to_owned(), nested);
        }
        res
    }

    /// Removes an entry from the tree, returns a `RemoveResult`.
    pub fn remove(&mut self, path: &[u8]) -> RemoveResult {
        let empty_result = RemoveResult::default();
        if path.is_empty() {
            return empty_result;
        }
        let mut split = path.splitn(2, |&c| c == b'/');
        let head = split.next();
        let tail = split.next().unwrap_or(b"");

        let head = match head {
            None => {
                return empty_result;
            }
            Some(h) => h,
        };
        if head == path {
            match &mut self.kind {
                NodeKind::Directory(d) => {
                    return Node::remove_from_directory(head, d);
                }
                NodeKind::File(f) => {
                    if let Some(d) = &mut f.was_directory {
                        let RemoveResult { old_entry, .. } =
                            Node::remove_from_directory(head, d);
                        return RemoveResult {
                            cleanup: false,
                            old_entry,
                        };
                    }
                }
            }
            empty_result
        } else {
            // Look into the dirs
            match &mut self.kind {
                NodeKind::Directory(d) => {
                    if let Some(child) = d.children.get_mut(head) {
                        let mut res = child.remove(tail);
                        if res.cleanup {
                            d.children.remove(head);
                        }
                        res.cleanup =
                            d.children.is_empty() && d.was_file.is_none();
                        res
                    } else {
                        empty_result
                    }
                }
                NodeKind::File(f) => {
                    if let Some(d) = &mut f.was_directory {
                        if let Some(child) = d.children.get_mut(head) {
                            let RemoveResult { cleanup, old_entry } =
                                child.remove(tail);
                            if cleanup {
                                d.children.remove(head);
                            }
                            if d.children.is_empty() && d.was_file.is_none() {
                                f.was_directory = None;
                            }

                            return RemoveResult {
                                cleanup: false,
                                old_entry,
                            };
                        }
                    }
                    empty_result
                }
            }
        }
    }

    fn remove_from_directory(head: &[u8], d: &mut Directory) -> RemoveResult {
        if let Some(node) = d.children.get_mut(head) {
            return match &mut node.kind {
                NodeKind::Directory(d) => {
                    if let Some(f) = &mut d.was_file {
                        let entry = f.entry;
                        d.was_file = None;
                        RemoveResult {
                            cleanup: false,
                            old_entry: Some(entry),
                        }
                    } else {
                        RemoveResult::default()
                    }
                }
                NodeKind::File(f) => {
                    let entry = f.entry;
                    let mut cleanup = false;
                    match &f.was_directory {
                        None => {
                            if d.children.len() == 1 {
                                cleanup = true;
                            }
                            d.children.remove(head);
                        }
                        Some(dir) => {
                            node.kind = NodeKind::Directory(*dir.clone());
                        }
                    }

                    RemoveResult {
                        cleanup,
                        old_entry: Some(entry),
                    }
                }
            };
        }
        RemoveResult::default()
    }

    pub fn get(&self, path: &[u8]) -> Option<&Node> {
        if path.is_empty() {
            return Some(&self);
        }
        let mut split = path.splitn(2, |&c| c == b'/');
        let head = split.next();
        let tail = split.next().unwrap_or(b"");

        let head = match head {
            None => {
                return Some(&self);
            }
            Some(h) => h,
        };
        match &self.kind {
            NodeKind::Directory(d) => {
                if let Some(child) = d.children.get(head) {
                    return child.get(tail);
                }
            }
            NodeKind::File(f) => {
                if let Some(d) = &f.was_directory {
                    if let Some(child) = d.children.get(head) {
                        return child.get(tail);
                    }
                }
            }
        }

        None
    }

    pub fn get_mut(&mut self, path: &[u8]) -> Option<&mut NodeKind> {
        if path.is_empty() {
            return Some(&mut self.kind);
        }
        let mut split = path.splitn(2, |&c| c == b'/');
        let head = split.next();
        let tail = split.next().unwrap_or(b"");

        let head = match head {
            None => {
                return Some(&mut self.kind);
            }
            Some(h) => h,
        };
        match &mut self.kind {
            NodeKind::Directory(d) => {
                if let Some(child) = d.children.get_mut(head) {
                    return child.get_mut(tail);
                }
            }
            NodeKind::File(f) => {
                if let Some(d) = &mut f.was_directory {
                    if let Some(child) = d.children.get_mut(head) {
                        return child.get_mut(tail);
                    }
                }
            }
        }

        None
    }

    pub fn iter(&self) -> Iter {
        Iter::new(self)
    }
}

/// Information returned to the caller of an `insert` operation for integrity.
#[derive(Debug, Default)]
pub struct InsertResult {
    /// Whether the insertion resulted in an actual insertion and not an
    /// update
    pub(super) did_insert: bool,
    /// The entry that was replaced, if it exists
    pub(super) old_entry: Option<Node>,
}

/// Information returned to the caller of a `remove` operation integrity.
#[derive(Debug, Default)]
pub struct RemoveResult {
    /// If the caller needs to remove the current node
    pub(super) cleanup: bool,
    /// The entry that was replaced, if it exists
    pub(super) old_entry: Option<DirstateEntry>,
}

impl<'a> IntoIterator for &'a Node {
    type Item = (HgPathBuf, DirstateEntry);
    type IntoIter = Iter<'a>;

    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

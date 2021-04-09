use bytes_cast::BytesCast;
use std::path::PathBuf;
use std::{collections::BTreeMap, convert::TryInto};

use super::path_with_basename::WithBasename;
use crate::dirstate::parsers::clear_ambiguous_mtime;
use crate::dirstate::parsers::pack_entry;
use crate::dirstate::parsers::packed_entry_size;
use crate::dirstate::parsers::parse_dirstate_entries;
use crate::dirstate::parsers::parse_dirstate_parents;
use crate::dirstate::parsers::Timestamp;
use crate::matchers::Matcher;
use crate::revlog::node::NULL_NODE;
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::CopyMapIter;
use crate::DirstateEntry;
use crate::DirstateError;
use crate::DirstateMapError;
use crate::DirstateParents;
use crate::DirstateStatus;
use crate::EntryState;
use crate::FastHashMap;
use crate::HgPathCow;
use crate::PatternFileWarning;
use crate::StateMapIter;
use crate::StatusError;
use crate::StatusOptions;

pub struct DirstateMap {
    parents: Option<DirstateParents>,
    dirty_parents: bool,
    root: ChildNodes,

    /// Number of nodes anywhere in the tree that have `.entry.is_some()`.
    nodes_with_entry_count: usize,

    /// Number of nodes anywhere in the tree that have
    /// `.copy_source.is_some()`.
    nodes_with_copy_source_count: usize,
}

/// Using a plain `HgPathBuf` of the full path from the repository root as a
/// map key would also work: all paths in a given map have the same parent
/// path, so comparing full paths gives the same result as comparing base
/// names. However `BTreeMap` would waste time always re-comparing the same
/// string prefix.
type ChildNodes = BTreeMap<WithBasename<HgPathBuf>, Node>;

/// Represents a file or a directory
#[derive(Default)]
struct Node {
    /// `None` for directories
    entry: Option<DirstateEntry>,

    copy_source: Option<HgPathBuf>,

    children: ChildNodes,

    /// How many (non-inclusive) descendants of this node are tracked files
    tracked_descendants_count: usize,
}

impl Node {
    /// Whether this node has a `DirstateEntry` with `.state.is_tracked()`
    fn is_tracked_file(&self) -> bool {
        if let Some(entry) = &self.entry {
            entry.state.is_tracked()
        } else {
            false
        }
    }
}

/// `(full_path, entry, copy_source)`
type NodeDataMut<'a> = (
    &'a WithBasename<HgPathBuf>,
    &'a mut Option<DirstateEntry>,
    &'a mut Option<HgPathBuf>,
);

impl DirstateMap {
    pub fn new() -> Self {
        Self {
            parents: None,
            dirty_parents: false,
            root: ChildNodes::new(),
            nodes_with_entry_count: 0,
            nodes_with_copy_source_count: 0,
        }
    }

    fn get_node(&self, path: &HgPath) -> Option<&Node> {
        let mut children = &self.root;
        let mut components = path.components();
        let mut component =
            components.next().expect("expected at least one components");
        loop {
            let child = children.get(component)?;
            if let Some(next_component) = components.next() {
                component = next_component;
                children = &child.children;
            } else {
                return Some(child);
            }
        }
    }

    /// Returns a mutable reference to the node at `path` if it exists
    ///
    /// This takes `root` instead of `&mut self` so that callers can mutate
    /// other fields while the returned borrow is still valid
    fn get_node_mut<'tree>(
        root: &'tree mut ChildNodes,
        path: &HgPath,
    ) -> Option<&'tree mut Node> {
        Self::each_and_get(root, path, |_| {})
    }

    /// Call `each` for each ancestor node of the one at `path` (not including
    /// that node itself), starting from nearest the root.
    ///
    /// Panics (possibly after some calls to `each`) if there is no node at
    /// `path`.
    fn for_each_ancestor_node<'tree>(
        &mut self,
        path: &HgPath,
        each: impl FnMut(&mut Node),
    ) {
        let parent = path.parent();
        if !parent.is_empty() {
            Self::each_and_get(&mut self.root, parent, each)
                .expect("missing dirstate node");
        }
    }

    /// Common implementation detail of `get_node_mut` and
    /// `for_each_ancestor_node`
    fn each_and_get<'tree>(
        root: &'tree mut ChildNodes,
        path: &HgPath,
        mut each: impl FnMut(&mut Node),
    ) -> Option<&'tree mut Node> {
        let mut children = root;
        let mut components = path.components();
        let mut component =
            components.next().expect("expected at least one components");
        loop {
            let child = children.get_mut(component)?;
            each(child);
            if let Some(next_component) = components.next() {
                component = next_component;
                children = &mut child.children;
            } else {
                return Some(child);
            }
        }
    }

    fn get_or_insert_node<'tree>(
        root: &'tree mut ChildNodes,
        path: &HgPath,
    ) -> &'tree mut Node {
        let mut child_nodes = root;
        let mut inclusive_ancestor_paths =
            WithBasename::inclusive_ancestors_of(path);
        let mut ancestor_path = inclusive_ancestor_paths
            .next()
            .expect("expected at least one inclusive ancestor");
        loop {
            // TODO: can we avoid double lookup in all cases without allocating
            // an owned key in cases where the map already contains that key?
            let child_node =
                if child_nodes.contains_key(ancestor_path.base_name()) {
                    child_nodes.get_mut(ancestor_path.base_name()).unwrap()
                } else {
                    // This is always a vacant entry, using `.entry()` lets us
                    // return a `&mut Node` of the newly-inserted node without
                    // yet another lookup. `BTreeMap::insert` doesn’t do this.
                    child_nodes.entry(ancestor_path.to_owned()).or_default()
                };
            if let Some(next) = inclusive_ancestor_paths.next() {
                ancestor_path = next;
                child_nodes = &mut child_node.children;
            } else {
                return child_node;
            }
        }
    }

    /// The meaning of `new_copy_source` is:
    ///
    /// * `Some(Some(x))`: set `Node::copy_source` to `Some(x)`
    /// * `Some(None)`: set `Node::copy_source` to `None`
    /// * `None`: leave `Node::copy_source` unchanged
    fn add_file_node(
        &mut self,
        path: &HgPath,
        new_entry: DirstateEntry,
        new_copy_source: Option<Option<HgPathBuf>>,
    ) {
        let node = Self::get_or_insert_node(&mut self.root, path);
        if node.entry.is_none() {
            self.nodes_with_entry_count += 1
        }
        if let Some(source) = &new_copy_source {
            if node.copy_source.is_none() && source.is_some() {
                self.nodes_with_copy_source_count += 1
            }
            if node.copy_source.is_some() && source.is_none() {
                self.nodes_with_copy_source_count -= 1
            }
        }
        let tracked_count_increment =
            match (node.is_tracked_file(), new_entry.state.is_tracked()) {
                (false, true) => 1,
                (true, false) => -1,
                _ => 0,
            };

        node.entry = Some(new_entry);
        if let Some(source) = new_copy_source {
            node.copy_source = source
        }
        // Borrow of `self.root` through `node` ends here

        match tracked_count_increment {
            1 => self.for_each_ancestor_node(path, |node| {
                node.tracked_descendants_count += 1
            }),
            // We can’t use `+= -1` because the counter is unsigned
            -1 => self.for_each_ancestor_node(path, |node| {
                node.tracked_descendants_count -= 1
            }),
            _ => {}
        }
    }

    fn iter_nodes<'a>(
        &'a self,
    ) -> impl Iterator<Item = (&'a WithBasename<HgPathBuf>, &'a Node)> + 'a
    {
        // Depth first tree traversal.
        //
        // If we could afford internal iteration and recursion,
        // this would look like:
        //
        // ```
        // fn traverse_children(
        //     children: &ChildNodes,
        //     each: &mut impl FnMut(&Node),
        // ) {
        //     for child in children.values() {
        //         traverse_children(&child.children, each);
        //         each(child);
        //     }
        // }
        // ```
        //
        // However we want an external iterator and therefore can’t use the
        // call stack. Use an explicit stack instead:
        let mut stack = Vec::new();
        let mut iter = self.root.iter();
        std::iter::from_fn(move || {
            while let Some((key, child_node)) = iter.next() {
                // Pseudo-recursion
                let new_iter = child_node.children.iter();
                let old_iter = std::mem::replace(&mut iter, new_iter);
                stack.push((key, child_node, old_iter));
            }
            // Found the end of a `children.iter()` iterator.
            if let Some((key, child_node, next_iter)) = stack.pop() {
                // "Return" from pseudo-recursion by restoring state from the
                // explicit stack
                iter = next_iter;

                Some((key, child_node))
            } else {
                // Reached the bottom of the stack, we’re done
                None
            }
        })
    }

    /// Mutable iterator for the `(entry, copy source)` of each node.
    ///
    /// It would not be safe to yield mutable references to nodes themeselves
    /// with `-> impl Iterator<Item = &mut Node>` since child nodes are
    /// reachable from their ancestor nodes, potentially creating multiple
    /// `&mut` references to a given node.
    fn iter_node_data_mut<'a>(
        &'a mut self,
    ) -> impl Iterator<Item = NodeDataMut<'a>> + 'a {
        // Explict stack for pseudo-recursion, see `iter_nodes` above.
        let mut stack = Vec::new();
        let mut iter = self.root.iter_mut();
        std::iter::from_fn(move || {
            while let Some((key, child_node)) = iter.next() {
                // Pseudo-recursion
                let data =
                    (key, &mut child_node.entry, &mut child_node.copy_source);
                let new_iter = child_node.children.iter_mut();
                let old_iter = std::mem::replace(&mut iter, new_iter);
                stack.push((data, old_iter));
            }
            // Found the end of a `children.values_mut()` iterator.
            if let Some((data, next_iter)) = stack.pop() {
                // "Return" from pseudo-recursion by restoring state from the
                // explicit stack
                iter = next_iter;

                Some(data)
            } else {
                // Reached the bottom of the stack, we’re done
                None
            }
        })
    }
}

impl super::dispatch::DirstateMapMethods for DirstateMap {
    fn clear(&mut self) {
        self.set_parents(&DirstateParents {
            p1: NULL_NODE,
            p2: NULL_NODE,
        });
        self.root.clear();
        self.nodes_with_entry_count = 0;
        self.nodes_with_copy_source_count = 0;
    }

    fn add_file(
        &mut self,
        filename: &HgPath,
        _old_state: EntryState,
        entry: DirstateEntry,
    ) -> Result<(), DirstateMapError> {
        self.add_file_node(filename, entry, None);
        Ok(())
    }

    fn remove_file(
        &mut self,
        filename: &HgPath,
        _old_state: EntryState,
        size: i32,
    ) -> Result<(), DirstateMapError> {
        let entry = DirstateEntry {
            state: EntryState::Removed,
            mode: 0,
            size,
            mtime: 0,
        };
        self.add_file_node(filename, entry, None);
        Ok(())
    }

    fn drop_file(
        &mut self,
        filename: &HgPath,
        _old_state: EntryState,
    ) -> Result<bool, DirstateMapError> {
        if let Some(node) = Self::get_node_mut(&mut self.root, filename) {
            let was_tracked = node.is_tracked_file();
            let had_entry = node.entry.is_some();
            let had_copy_source = node.copy_source.is_some();

            // TODO: this leaves in the tree a "non-file" node. Should we
            // remove the node instead, together with ancestor nodes for
            // directories that become empty?
            node.entry = None;
            node.copy_source = None;

            if had_entry {
                self.nodes_with_entry_count -= 1
            }
            if had_copy_source {
                self.nodes_with_copy_source_count -= 1
            }
            if was_tracked {
                self.for_each_ancestor_node(filename, |node| {
                    node.tracked_descendants_count -= 1
                })
            }
            Ok(had_entry)
        } else {
            Ok(false)
        }
    }

    fn clear_ambiguous_times(&mut self, filenames: Vec<HgPathBuf>, now: i32) {
        for filename in filenames {
            if let Some(node) = Self::get_node_mut(&mut self.root, &filename) {
                if let Some(entry) = node.entry.as_mut() {
                    clear_ambiguous_mtime(entry, now);
                }
            }
        }
    }

    fn non_normal_entries_contains(&mut self, key: &HgPath) -> bool {
        self.get_node(key)
            .and_then(|node| node.entry.as_ref())
            .map_or(false, DirstateEntry::is_non_normal)
    }

    fn non_normal_entries_remove(&mut self, _key: &HgPath) {
        // Do nothing, this `DirstateMap` does not have a separate "non normal
        // entries" set that need to be kept up to date
    }

    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + '_> {
        Box::new(self.iter_nodes().filter_map(|(path, node)| {
            node.entry
                .as_ref()
                .filter(|entry| {
                    entry.is_non_normal() || entry.is_from_other_parent()
                })
                .map(|_| path.full_path())
        }))
    }

    fn set_non_normal_other_parent_entries(&mut self, _force: bool) {
        // Do nothing, this `DirstateMap` does not have a separate "non normal
        // entries" and "from other parent" sets that need to be recomputed
    }

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        self.iter_non_normal_paths_panic()
    }

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        Box::new(self.iter_nodes().filter_map(|(path, node)| {
            node.entry
                .as_ref()
                .filter(|entry| entry.is_non_normal())
                .map(|_| path.full_path())
        }))
    }

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        Box::new(self.iter_nodes().filter_map(|(path, node)| {
            node.entry
                .as_ref()
                .filter(|entry| entry.is_from_other_parent())
                .map(|_| path.full_path())
        }))
    }

    fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateMapError> {
        if let Some(node) = self.get_node(directory) {
            // A node without a `DirstateEntry` was created to hold child
            // nodes, and is therefore a directory.
            Ok(node.entry.is_none() && node.tracked_descendants_count > 0)
        } else {
            Ok(false)
        }
    }

    fn has_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateMapError> {
        if let Some(node) = self.get_node(directory) {
            // A node without a `DirstateEntry` was created to hold child
            // nodes, and is therefore a directory.
            Ok(node.entry.is_none())
        } else {
            Ok(false)
        }
    }

    fn parents(
        &mut self,
        file_contents: &[u8],
    ) -> Result<&DirstateParents, DirstateError> {
        if self.parents.is_none() {
            let parents = if !file_contents.is_empty() {
                parse_dirstate_parents(file_contents)?.clone()
            } else {
                DirstateParents {
                    p1: NULL_NODE,
                    p2: NULL_NODE,
                }
            };
            self.parents = Some(parents);
        }
        Ok(self.parents.as_ref().unwrap())
    }

    fn set_parents(&mut self, parents: &DirstateParents) {
        self.parents = Some(parents.clone());
        self.dirty_parents = true;
    }

    fn read<'a>(
        &mut self,
        file_contents: &'a [u8],
    ) -> Result<Option<&'a DirstateParents>, DirstateError> {
        if file_contents.is_empty() {
            return Ok(None);
        }

        let parents = parse_dirstate_entries(
            file_contents,
            |path, entry, copy_source| {
                self.add_file_node(
                    path,
                    *entry,
                    Some(copy_source.map(HgPath::to_owned)),
                )
            },
        )?;

        if !self.dirty_parents {
            self.set_parents(parents);
        }

        Ok(Some(parents))
    }

    fn pack(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError> {
        // Optizimation (to be measured?): pre-compute size to avoid `Vec`
        // reallocations
        let mut size = parents.as_bytes().len();
        for (path, node) in self.iter_nodes() {
            if node.entry.is_some() {
                size += packed_entry_size(
                    path.full_path(),
                    node.copy_source.as_ref(),
                )
            }
        }

        let mut packed = Vec::with_capacity(size);
        packed.extend(parents.as_bytes());

        let now: i32 = now.0.try_into().expect("time overflow");
        for (path, opt_entry, copy_source) in self.iter_node_data_mut() {
            if let Some(entry) = opt_entry {
                clear_ambiguous_mtime(entry, now);
                pack_entry(
                    path.full_path(),
                    entry,
                    copy_source.as_ref(),
                    &mut packed,
                );
            }
        }
        self.dirty_parents = false;
        Ok(packed)
    }

    fn build_file_fold_map(&mut self) -> &FastHashMap<HgPathBuf, HgPathBuf> {
        todo!()
    }

    fn set_all_dirs(&mut self) -> Result<(), DirstateMapError> {
        // Do nothing, this `DirstateMap` does not a separate `all_dirs` that
        // needs to be recomputed
        Ok(())
    }

    fn set_dirs(&mut self) -> Result<(), DirstateMapError> {
        // Do nothing, this `DirstateMap` does not a separate `dirs` that needs
        // to be recomputed
        Ok(())
    }

    fn status<'a>(
        &'a self,
        _matcher: &'a (dyn Matcher + Sync),
        _root_dir: PathBuf,
        _ignore_files: Vec<PathBuf>,
        _options: StatusOptions,
    ) -> Result<
        (
            (Vec<HgPathCow<'a>>, DirstateStatus<'a>),
            Vec<PatternFileWarning>,
        ),
        StatusError,
    > {
        todo!()
    }

    fn copy_map_len(&self) -> usize {
        self.nodes_with_copy_source_count
    }

    fn copy_map_iter(&self) -> CopyMapIter<'_> {
        Box::new(self.iter_nodes().filter_map(|(path, node)| {
            node.copy_source
                .as_ref()
                .map(|copy_source| (path.full_path(), copy_source))
        }))
    }

    fn copy_map_contains_key(&self, key: &HgPath) -> bool {
        if let Some(node) = self.get_node(key) {
            node.copy_source.is_some()
        } else {
            false
        }
    }

    fn copy_map_get(&self, key: &HgPath) -> Option<&HgPathBuf> {
        self.get_node(key)?.copy_source.as_ref()
    }

    fn copy_map_remove(&mut self, key: &HgPath) -> Option<HgPathBuf> {
        let count = &mut self.nodes_with_copy_source_count;
        Self::get_node_mut(&mut self.root, key).and_then(|node| {
            if node.copy_source.is_some() {
                *count -= 1
            }
            node.copy_source.take()
        })
    }

    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Option<HgPathBuf> {
        let node = Self::get_or_insert_node(&mut self.root, &key);
        if node.copy_source.is_none() {
            self.nodes_with_copy_source_count += 1
        }
        node.copy_source.replace(value)
    }

    fn len(&self) -> usize {
        self.nodes_with_entry_count
    }

    fn contains_key(&self, key: &HgPath) -> bool {
        self.get(key).is_some()
    }

    fn get(&self, key: &HgPath) -> Option<&DirstateEntry> {
        self.get_node(key)?.entry.as_ref()
    }

    fn iter(&self) -> StateMapIter<'_> {
        Box::new(self.iter_nodes().filter_map(|(path, node)| {
            node.entry.as_ref().map(|entry| (path.full_path(), entry))
        }))
    }
}

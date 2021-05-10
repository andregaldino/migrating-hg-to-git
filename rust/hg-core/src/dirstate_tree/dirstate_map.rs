use bytes_cast::BytesCast;
use micro_timer::timed;
use std::borrow::Cow;
use std::convert::TryInto;
use std::path::PathBuf;

use super::path_with_basename::WithBasename;
use crate::dirstate::parsers::clear_ambiguous_mtime;
use crate::dirstate::parsers::pack_entry;
use crate::dirstate::parsers::packed_entry_size;
use crate::dirstate::parsers::parse_dirstate_entries;
use crate::dirstate::parsers::Timestamp;
use crate::matchers::Matcher;
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::CopyMapIter;
use crate::DirstateEntry;
use crate::DirstateError;
use crate::DirstateMapError;
use crate::DirstateParents;
use crate::DirstateStatus;
use crate::EntryState;
use crate::FastHashMap;
use crate::PatternFileWarning;
use crate::StateMapIter;
use crate::StatusError;
use crate::StatusOptions;

pub struct DirstateMap<'on_disk> {
    /// Contents of the `.hg/dirstate` file
    on_disk: &'on_disk [u8],

    pub(super) root: ChildNodes<'on_disk>,

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
pub(super) type ChildNodes<'on_disk> =
    FastHashMap<WithBasename<Cow<'on_disk, HgPath>>, Node<'on_disk>>;

/// Represents a file or a directory
#[derive(Default)]
pub(super) struct Node<'on_disk> {
    /// `None` for directories
    pub(super) entry: Option<DirstateEntry>,

    pub(super) copy_source: Option<Cow<'on_disk, HgPath>>,

    pub(super) children: ChildNodes<'on_disk>,

    /// How many (non-inclusive) descendants of this node are tracked files
    tracked_descendants_count: usize,
}

impl Node<'_> {
    pub(super) fn state(&self) -> Option<EntryState> {
        self.entry.as_ref().map(|entry| entry.state)
    }
}

/// `(full_path, entry, copy_source)`
type NodeDataMut<'tree, 'on_disk> = (
    &'tree HgPath,
    &'tree mut Option<DirstateEntry>,
    &'tree mut Option<Cow<'on_disk, HgPath>>,
);

impl<'on_disk> DirstateMap<'on_disk> {
    pub fn new(
        on_disk: &'on_disk [u8],
    ) -> Result<(Self, Option<DirstateParents>), DirstateError> {
        let mut map = Self {
            on_disk,
            root: ChildNodes::default(),
            nodes_with_entry_count: 0,
            nodes_with_copy_source_count: 0,
        };
        let parents = map.read()?;
        Ok((map, parents))
    }

    /// Should only be called in `new`
    #[timed]
    fn read(&mut self) -> Result<Option<DirstateParents>, DirstateError> {
        if self.on_disk.is_empty() {
            return Ok(None);
        }

        let parents = parse_dirstate_entries(
            self.on_disk,
            |path, entry, copy_source| {
                let tracked = entry.state.is_tracked();
                let node = Self::get_or_insert_node(
                    &mut self.root,
                    path,
                    WithBasename::to_cow_borrowed,
                    |ancestor| {
                        if tracked {
                            ancestor.tracked_descendants_count += 1
                        }
                    },
                );
                assert!(
                    node.entry.is_none(),
                    "duplicate dirstate entry in read"
                );
                assert!(
                    node.copy_source.is_none(),
                    "duplicate dirstate entry in read"
                );
                node.entry = Some(*entry);
                node.copy_source = copy_source.map(Cow::Borrowed);
                self.nodes_with_entry_count += 1;
                if copy_source.is_some() {
                    self.nodes_with_copy_source_count += 1
                }
            },
        )?;

        Ok(Some(parents.clone()))
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
        root: &'tree mut ChildNodes<'on_disk>,
        path: &HgPath,
    ) -> Option<&'tree mut Node<'on_disk>> {
        let mut children = root;
        let mut components = path.components();
        let mut component =
            components.next().expect("expected at least one components");
        loop {
            let child = children.get_mut(component)?;
            if let Some(next_component) = components.next() {
                component = next_component;
                children = &mut child.children;
            } else {
                return Some(child);
            }
        }
    }

    fn get_or_insert_node<'tree, 'path>(
        root: &'tree mut ChildNodes<'on_disk>,
        path: &'path HgPath,
        to_cow: impl Fn(
            WithBasename<&'path HgPath>,
        ) -> WithBasename<Cow<'on_disk, HgPath>>,
        mut each_ancestor: impl FnMut(&mut Node),
    ) -> &'tree mut Node<'on_disk> {
        let mut child_nodes = root;
        let mut inclusive_ancestor_paths =
            WithBasename::inclusive_ancestors_of(path);
        let mut ancestor_path = inclusive_ancestor_paths
            .next()
            .expect("expected at least one inclusive ancestor");
        loop {
            // TODO: can we avoid allocating an owned key in cases where the
            // map already contains that key, without introducing double
            // lookup?
            let child_node =
                child_nodes.entry(to_cow(ancestor_path)).or_default();
            if let Some(next) = inclusive_ancestor_paths.next() {
                each_ancestor(child_node);
                ancestor_path = next;
                child_nodes = &mut child_node.children;
            } else {
                return child_node;
            }
        }
    }

    fn add_or_remove_file(
        &mut self,
        path: &HgPath,
        old_state: EntryState,
        new_entry: DirstateEntry,
    ) {
        let tracked_count_increment =
            match (old_state.is_tracked(), new_entry.state.is_tracked()) {
                (false, true) => 1,
                (true, false) => -1,
                _ => 0,
            };

        let node = Self::get_or_insert_node(
            &mut self.root,
            path,
            WithBasename::to_cow_owned,
            |ancestor| {
                // We can’t use `+= increment` because the counter is unsigned,
                // and we want debug builds to detect accidental underflow
                // through zero
                match tracked_count_increment {
                    1 => ancestor.tracked_descendants_count += 1,
                    -1 => ancestor.tracked_descendants_count -= 1,
                    _ => {}
                }
            },
        );
        if node.entry.is_none() {
            self.nodes_with_entry_count += 1
        }
        node.entry = Some(new_entry)
    }

    fn iter_nodes<'a>(
        &'a self,
    ) -> impl Iterator<Item = (&'a HgPath, &'a Node)> + 'a {
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
                let key = &**key.full_path();
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
    fn iter_node_data_mut<'tree>(
        &'tree mut self,
    ) -> impl Iterator<Item = NodeDataMut<'tree, 'on_disk>> + 'tree {
        // Explict stack for pseudo-recursion, see `iter_nodes` above.
        let mut stack = Vec::new();
        let mut iter = self.root.iter_mut();
        std::iter::from_fn(move || {
            while let Some((key, child_node)) = iter.next() {
                // Pseudo-recursion
                let data = (
                    &**key.full_path(),
                    &mut child_node.entry,
                    &mut child_node.copy_source,
                );
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

impl<'on_disk> super::dispatch::DirstateMapMethods for DirstateMap<'on_disk> {
    fn clear(&mut self) {
        self.root.clear();
        self.nodes_with_entry_count = 0;
        self.nodes_with_copy_source_count = 0;
    }

    fn add_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        entry: DirstateEntry,
    ) -> Result<(), DirstateMapError> {
        self.add_or_remove_file(filename, old_state, entry);
        Ok(())
    }

    fn remove_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        size: i32,
    ) -> Result<(), DirstateMapError> {
        let entry = DirstateEntry {
            state: EntryState::Removed,
            mode: 0,
            size,
            mtime: 0,
        };
        self.add_or_remove_file(filename, old_state, entry);
        Ok(())
    }

    fn drop_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
    ) -> Result<bool, DirstateMapError> {
        struct Dropped {
            was_tracked: bool,
            had_entry: bool,
            had_copy_source: bool,
        }
        fn recur(nodes: &mut ChildNodes, path: &HgPath) -> Option<Dropped> {
            let (first_path_component, rest_of_path) =
                path.split_first_component();
            let node = nodes.get_mut(first_path_component)?;
            let dropped;
            if let Some(rest) = rest_of_path {
                dropped = recur(&mut node.children, rest)?;
                if dropped.was_tracked {
                    node.tracked_descendants_count -= 1;
                }
            } else {
                dropped = Dropped {
                    was_tracked: node
                        .entry
                        .as_ref()
                        .map_or(false, |entry| entry.state.is_tracked()),
                    had_entry: node.entry.take().is_some(),
                    had_copy_source: node.copy_source.take().is_some(),
                };
            }
            // After recursion, for both leaf (rest_of_path is None) nodes and
            // parent nodes, remove a node if it just became empty.
            if node.entry.is_none()
                && node.copy_source.is_none()
                && node.children.is_empty()
            {
                nodes.remove(first_path_component);
            }
            Some(dropped)
        }

        if let Some(dropped) = recur(&mut self.root, filename) {
            if dropped.had_entry {
                self.nodes_with_entry_count -= 1
            }
            if dropped.had_copy_source {
                self.nodes_with_copy_source_count -= 1
            }
            Ok(dropped.had_entry)
        } else {
            debug_assert!(!old_state.is_tracked());
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
    ) -> Box<dyn Iterator<Item = &HgPath> + '_> {
        Box::new(self.iter_nodes().filter_map(|(path, node)| {
            node.entry
                .as_ref()
                .filter(|entry| {
                    entry.is_non_normal() || entry.is_from_other_parent()
                })
                .map(|_| path)
        }))
    }

    fn set_non_normal_other_parent_entries(&mut self, _force: bool) {
        // Do nothing, this `DirstateMap` does not have a separate "non normal
        // entries" and "from other parent" sets that need to be recomputed
    }

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPath> + Send + '_> {
        self.iter_non_normal_paths_panic()
    }

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<dyn Iterator<Item = &HgPath> + Send + '_> {
        Box::new(self.iter_nodes().filter_map(|(path, node)| {
            node.entry
                .as_ref()
                .filter(|entry| entry.is_non_normal())
                .map(|_| path)
        }))
    }

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPath> + Send + '_> {
        Box::new(self.iter_nodes().filter_map(|(path, node)| {
            node.entry
                .as_ref()
                .filter(|entry| entry.is_from_other_parent())
                .map(|_| path)
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
                    path,
                    node.copy_source.as_ref().map(|p| &**p),
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
                    path,
                    entry,
                    copy_source.as_ref().map(|p| &**p),
                    &mut packed,
                );
            }
        }
        Ok(packed)
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
        &'a mut self,
        matcher: &'a (dyn Matcher + Sync),
        root_dir: PathBuf,
        ignore_files: Vec<PathBuf>,
        options: StatusOptions,
    ) -> Result<(DirstateStatus<'a>, Vec<PatternFileWarning>), StatusError>
    {
        super::status::status(self, matcher, root_dir, ignore_files, options)
    }

    fn copy_map_len(&self) -> usize {
        self.nodes_with_copy_source_count
    }

    fn copy_map_iter(&self) -> CopyMapIter<'_> {
        Box::new(self.iter_nodes().filter_map(|(path, node)| {
            node.copy_source
                .as_ref()
                .map(|copy_source| (path, &**copy_source))
        }))
    }

    fn copy_map_contains_key(&self, key: &HgPath) -> bool {
        if let Some(node) = self.get_node(key) {
            node.copy_source.is_some()
        } else {
            false
        }
    }

    fn copy_map_get(&self, key: &HgPath) -> Option<&HgPath> {
        self.get_node(key)?.copy_source.as_ref().map(|p| &**p)
    }

    fn copy_map_remove(&mut self, key: &HgPath) -> Option<HgPathBuf> {
        let count = &mut self.nodes_with_copy_source_count;
        Self::get_node_mut(&mut self.root, key).and_then(|node| {
            if node.copy_source.is_some() {
                *count -= 1
            }
            node.copy_source.take().map(Cow::into_owned)
        })
    }

    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Option<HgPathBuf> {
        let node = Self::get_or_insert_node(
            &mut self.root,
            &key,
            WithBasename::to_cow_owned,
            |_ancestor| {},
        );
        if node.copy_source.is_none() {
            self.nodes_with_copy_source_count += 1
        }
        node.copy_source.replace(value.into()).map(Cow::into_owned)
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
            node.entry.as_ref().map(|entry| (path, entry))
        }))
    }
}

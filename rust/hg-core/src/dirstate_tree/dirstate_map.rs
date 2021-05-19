use bytes_cast::BytesCast;
use micro_timer::timed;
use std::borrow::Cow;
use std::convert::TryInto;
use std::path::PathBuf;

use super::on_disk;
use super::on_disk::DirstateV2ParseError;
use super::path_with_basename::WithBasename;
use crate::dirstate::parsers::pack_entry;
use crate::dirstate::parsers::packed_entry_size;
use crate::dirstate::parsers::parse_dirstate_entries;
use crate::dirstate::parsers::Timestamp;
use crate::matchers::Matcher;
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::CopyMapIter;
use crate::DirstateEntry;
use crate::DirstateError;
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
    pub(super) on_disk: &'on_disk [u8],

    pub(super) root: ChildNodes<'on_disk>,

    /// Number of nodes anywhere in the tree that have `.entry.is_some()`.
    pub(super) nodes_with_entry_count: u32,

    /// Number of nodes anywhere in the tree that have
    /// `.copy_source.is_some()`.
    pub(super) nodes_with_copy_source_count: u32,
}

/// Using a plain `HgPathBuf` of the full path from the repository root as a
/// map key would also work: all paths in a given map have the same parent
/// path, so comparing full paths gives the same result as comparing base
/// names. However `HashMap` would waste time always re-hashing the same
/// string prefix.
pub(super) type NodeKey<'on_disk> = WithBasename<Cow<'on_disk, HgPath>>;

pub(super) enum ChildNodes<'on_disk> {
    InMemory(FastHashMap<NodeKey<'on_disk>, Node<'on_disk>>),
    OnDisk(&'on_disk [on_disk::Node]),
}

pub(super) enum ChildNodesRef<'tree, 'on_disk> {
    InMemory(&'tree FastHashMap<NodeKey<'on_disk>, Node<'on_disk>>),
    OnDisk(&'on_disk [on_disk::Node]),
}

pub(super) enum NodeRef<'tree, 'on_disk> {
    InMemory(&'tree NodeKey<'on_disk>, &'tree Node<'on_disk>),
    OnDisk(&'on_disk on_disk::Node),
}

impl Default for ChildNodes<'_> {
    fn default() -> Self {
        ChildNodes::InMemory(Default::default())
    }
}

impl<'on_disk> ChildNodes<'on_disk> {
    pub(super) fn as_ref<'tree>(
        &'tree self,
    ) -> ChildNodesRef<'tree, 'on_disk> {
        match self {
            ChildNodes::InMemory(nodes) => ChildNodesRef::InMemory(nodes),
            ChildNodes::OnDisk(nodes) => ChildNodesRef::OnDisk(nodes),
        }
    }

    pub(super) fn is_empty(&self) -> bool {
        match self {
            ChildNodes::InMemory(nodes) => nodes.is_empty(),
            ChildNodes::OnDisk(nodes) => nodes.is_empty(),
        }
    }

    pub(super) fn make_mut(
        &mut self,
        on_disk: &'on_disk [u8],
    ) -> Result<
        &mut FastHashMap<NodeKey<'on_disk>, Node<'on_disk>>,
        DirstateV2ParseError,
    > {
        match self {
            ChildNodes::InMemory(nodes) => Ok(nodes),
            ChildNodes::OnDisk(nodes) => {
                let nodes = nodes
                    .iter()
                    .map(|node| {
                        Ok((
                            node.path(on_disk)?,
                            node.to_in_memory_node(on_disk)?,
                        ))
                    })
                    .collect::<Result<_, _>>()?;
                *self = ChildNodes::InMemory(nodes);
                match self {
                    ChildNodes::InMemory(nodes) => Ok(nodes),
                    ChildNodes::OnDisk(_) => unreachable!(),
                }
            }
        }
    }
}

impl<'tree, 'on_disk> ChildNodesRef<'tree, 'on_disk> {
    pub(super) fn get(
        &self,
        base_name: &HgPath,
        on_disk: &'on_disk [u8],
    ) -> Result<Option<NodeRef<'tree, 'on_disk>>, DirstateV2ParseError> {
        match self {
            ChildNodesRef::InMemory(nodes) => Ok(nodes
                .get_key_value(base_name)
                .map(|(k, v)| NodeRef::InMemory(k, v))),
            ChildNodesRef::OnDisk(nodes) => {
                let mut parse_result = Ok(());
                let search_result = nodes.binary_search_by(|node| {
                    match node.base_name(on_disk) {
                        Ok(node_base_name) => node_base_name.cmp(base_name),
                        Err(e) => {
                            parse_result = Err(e);
                            // Dummy comparison result, `search_result` won’t
                            // be used since `parse_result` is an error
                            std::cmp::Ordering::Equal
                        }
                    }
                });
                parse_result.map(|()| {
                    search_result.ok().map(|i| NodeRef::OnDisk(&nodes[i]))
                })
            }
        }
    }

    /// Iterate in undefined order
    pub(super) fn iter(
        &self,
    ) -> impl Iterator<Item = NodeRef<'tree, 'on_disk>> {
        match self {
            ChildNodesRef::InMemory(nodes) => itertools::Either::Left(
                nodes.iter().map(|(k, v)| NodeRef::InMemory(k, v)),
            ),
            ChildNodesRef::OnDisk(nodes) => {
                itertools::Either::Right(nodes.iter().map(NodeRef::OnDisk))
            }
        }
    }

    /// Iterate in parallel in undefined order
    pub(super) fn par_iter(
        &self,
    ) -> impl rayon::iter::ParallelIterator<Item = NodeRef<'tree, 'on_disk>>
    {
        use rayon::prelude::*;
        match self {
            ChildNodesRef::InMemory(nodes) => rayon::iter::Either::Left(
                nodes.par_iter().map(|(k, v)| NodeRef::InMemory(k, v)),
            ),
            ChildNodesRef::OnDisk(nodes) => rayon::iter::Either::Right(
                nodes.par_iter().map(NodeRef::OnDisk),
            ),
        }
    }

    pub(super) fn sorted(&self) -> Vec<NodeRef<'tree, 'on_disk>> {
        match self {
            ChildNodesRef::InMemory(nodes) => {
                let mut vec: Vec<_> = nodes
                    .iter()
                    .map(|(k, v)| NodeRef::InMemory(k, v))
                    .collect();
                fn sort_key<'a>(node: &'a NodeRef) -> &'a HgPath {
                    match node {
                        NodeRef::InMemory(path, _node) => path.base_name(),
                        NodeRef::OnDisk(_) => unreachable!(),
                    }
                }
                // `sort_unstable_by_key` doesn’t allow keys borrowing from the
                // value: https://github.com/rust-lang/rust/issues/34162
                vec.sort_unstable_by(|a, b| sort_key(a).cmp(sort_key(b)));
                vec
            }
            ChildNodesRef::OnDisk(nodes) => {
                // Nodes on disk are already sorted
                nodes.iter().map(NodeRef::OnDisk).collect()
            }
        }
    }
}

impl<'tree, 'on_disk> NodeRef<'tree, 'on_disk> {
    pub(super) fn full_path(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<&'tree HgPath, DirstateV2ParseError> {
        match self {
            NodeRef::InMemory(path, _node) => Ok(path.full_path()),
            NodeRef::OnDisk(node) => node.full_path(on_disk),
        }
    }

    /// Returns a `Cow` that can borrow 'on_disk but is detached from 'tree
    pub(super) fn full_path_cow(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<Cow<'on_disk, HgPath>, DirstateV2ParseError> {
        match self {
            NodeRef::InMemory(path, _node) => Ok(path.full_path().clone()),
            NodeRef::OnDisk(node) => {
                Ok(Cow::Borrowed(node.full_path(on_disk)?))
            }
        }
    }

    pub(super) fn base_name(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<&'tree HgPath, DirstateV2ParseError> {
        match self {
            NodeRef::InMemory(path, _node) => Ok(path.base_name()),
            NodeRef::OnDisk(node) => node.base_name(on_disk),
        }
    }

    pub(super) fn children(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<ChildNodesRef<'tree, 'on_disk>, DirstateV2ParseError> {
        match self {
            NodeRef::InMemory(_path, node) => Ok(node.children.as_ref()),
            NodeRef::OnDisk(node) => {
                Ok(ChildNodesRef::OnDisk(node.children(on_disk)?))
            }
        }
    }

    pub(super) fn has_copy_source(&self) -> bool {
        match self {
            NodeRef::InMemory(_path, node) => node.copy_source.is_some(),
            NodeRef::OnDisk(node) => node.has_copy_source(),
        }
    }

    pub(super) fn copy_source(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<Option<&'tree HgPath>, DirstateV2ParseError> {
        match self {
            NodeRef::InMemory(_path, node) => {
                Ok(node.copy_source.as_ref().map(|s| &**s))
            }
            NodeRef::OnDisk(node) => node.copy_source(on_disk),
        }
    }

    pub(super) fn has_entry(&self) -> bool {
        match self {
            NodeRef::InMemory(_path, node) => node.entry.is_some(),
            NodeRef::OnDisk(node) => node.has_entry(),
        }
    }

    pub(super) fn entry(
        &self,
    ) -> Result<Option<DirstateEntry>, DirstateV2ParseError> {
        match self {
            NodeRef::InMemory(_path, node) => Ok(node.entry),
            NodeRef::OnDisk(node) => node.entry(),
        }
    }

    pub(super) fn state(
        &self,
    ) -> Result<Option<EntryState>, DirstateV2ParseError> {
        match self {
            NodeRef::InMemory(_path, node) => {
                Ok(node.entry.as_ref().map(|entry| entry.state))
            }
            NodeRef::OnDisk(node) => node.state(),
        }
    }

    pub(super) fn tracked_descendants_count(&self) -> u32 {
        match self {
            NodeRef::InMemory(_path, node) => node.tracked_descendants_count,
            NodeRef::OnDisk(node) => node.tracked_descendants_count.get(),
        }
    }
}

/// Represents a file or a directory
#[derive(Default)]
pub(super) struct Node<'on_disk> {
    /// `None` for directories
    pub(super) entry: Option<DirstateEntry>,

    pub(super) copy_source: Option<Cow<'on_disk, HgPath>>,

    pub(super) children: ChildNodes<'on_disk>,

    /// How many (non-inclusive) descendants of this node are tracked files
    pub(super) tracked_descendants_count: u32,
}

impl<'on_disk> DirstateMap<'on_disk> {
    pub(super) fn empty(on_disk: &'on_disk [u8]) -> Self {
        Self {
            on_disk,
            root: ChildNodes::default(),
            nodes_with_entry_count: 0,
            nodes_with_copy_source_count: 0,
        }
    }

    #[timed]
    pub fn new_v2(
        on_disk: &'on_disk [u8],
    ) -> Result<(Self, Option<DirstateParents>), DirstateError> {
        Ok(on_disk::read(on_disk)?)
    }

    #[timed]
    pub fn new_v1(
        on_disk: &'on_disk [u8],
    ) -> Result<(Self, Option<DirstateParents>), DirstateError> {
        let mut map = Self::empty(on_disk);
        if map.on_disk.is_empty() {
            return Ok((map, None));
        }

        let parents = parse_dirstate_entries(
            map.on_disk,
            |path, entry, copy_source| {
                let tracked = entry.state.is_tracked();
                let node = Self::get_or_insert_node(
                    map.on_disk,
                    &mut map.root,
                    path,
                    WithBasename::to_cow_borrowed,
                    |ancestor| {
                        if tracked {
                            ancestor.tracked_descendants_count += 1
                        }
                    },
                )?;
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
                map.nodes_with_entry_count += 1;
                if copy_source.is_some() {
                    map.nodes_with_copy_source_count += 1
                }
                Ok(())
            },
        )?;
        let parents = Some(parents.clone());

        Ok((map, parents))
    }

    fn get_node<'tree>(
        &'tree self,
        path: &HgPath,
    ) -> Result<Option<NodeRef<'tree, 'on_disk>>, DirstateV2ParseError> {
        let mut children = self.root.as_ref();
        let mut components = path.components();
        let mut component =
            components.next().expect("expected at least one components");
        loop {
            if let Some(child) = children.get(component, self.on_disk)? {
                if let Some(next_component) = components.next() {
                    component = next_component;
                    children = child.children(self.on_disk)?;
                } else {
                    return Ok(Some(child));
                }
            } else {
                return Ok(None);
            }
        }
    }

    /// Returns a mutable reference to the node at `path` if it exists
    ///
    /// This takes `root` instead of `&mut self` so that callers can mutate
    /// other fields while the returned borrow is still valid
    fn get_node_mut<'tree>(
        on_disk: &'on_disk [u8],
        root: &'tree mut ChildNodes<'on_disk>,
        path: &HgPath,
    ) -> Result<Option<&'tree mut Node<'on_disk>>, DirstateV2ParseError> {
        let mut children = root;
        let mut components = path.components();
        let mut component =
            components.next().expect("expected at least one components");
        loop {
            if let Some(child) = children.make_mut(on_disk)?.get_mut(component)
            {
                if let Some(next_component) = components.next() {
                    component = next_component;
                    children = &mut child.children;
                } else {
                    return Ok(Some(child));
                }
            } else {
                return Ok(None);
            }
        }
    }

    fn get_or_insert_node<'tree, 'path>(
        on_disk: &'on_disk [u8],
        root: &'tree mut ChildNodes<'on_disk>,
        path: &'path HgPath,
        to_cow: impl Fn(
            WithBasename<&'path HgPath>,
        ) -> WithBasename<Cow<'on_disk, HgPath>>,
        mut each_ancestor: impl FnMut(&mut Node),
    ) -> Result<&'tree mut Node<'on_disk>, DirstateV2ParseError> {
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
            let child_node = child_nodes
                .make_mut(on_disk)?
                .entry(to_cow(ancestor_path))
                .or_default();
            if let Some(next) = inclusive_ancestor_paths.next() {
                each_ancestor(child_node);
                ancestor_path = next;
                child_nodes = &mut child_node.children;
            } else {
                return Ok(child_node);
            }
        }
    }

    fn add_or_remove_file(
        &mut self,
        path: &HgPath,
        old_state: EntryState,
        new_entry: DirstateEntry,
    ) -> Result<(), DirstateV2ParseError> {
        let tracked_count_increment =
            match (old_state.is_tracked(), new_entry.state.is_tracked()) {
                (false, true) => 1,
                (true, false) => -1,
                _ => 0,
            };

        let node = Self::get_or_insert_node(
            self.on_disk,
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
        )?;
        if node.entry.is_none() {
            self.nodes_with_entry_count += 1
        }
        node.entry = Some(new_entry);
        Ok(())
    }

    fn iter_nodes<'tree>(
        &'tree self,
    ) -> impl Iterator<
        Item = Result<NodeRef<'tree, 'on_disk>, DirstateV2ParseError>,
    > + 'tree {
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
        let mut iter = self.root.as_ref().iter();
        std::iter::from_fn(move || {
            while let Some(child_node) = iter.next() {
                let children = match child_node.children(self.on_disk) {
                    Ok(children) => children,
                    Err(error) => return Some(Err(error)),
                };
                // Pseudo-recursion
                let new_iter = children.iter();
                let old_iter = std::mem::replace(&mut iter, new_iter);
                stack.push((child_node, old_iter));
            }
            // Found the end of a `children.iter()` iterator.
            if let Some((child_node, next_iter)) = stack.pop() {
                // "Return" from pseudo-recursion by restoring state from the
                // explicit stack
                iter = next_iter;

                Some(Ok(child_node))
            } else {
                // Reached the bottom of the stack, we’re done
                None
            }
        })
    }

    fn clear_known_ambiguous_mtimes(
        &mut self,
        paths: &[impl AsRef<HgPath>],
    ) -> Result<(), DirstateV2ParseError> {
        for path in paths {
            if let Some(node) = Self::get_node_mut(
                self.on_disk,
                &mut self.root,
                path.as_ref(),
            )? {
                if let Some(entry) = node.entry.as_mut() {
                    entry.clear_mtime();
                }
            }
        }
        Ok(())
    }

    /// Return a faillilble iterator of full paths of nodes that have an
    /// `entry` for which the given `predicate` returns true.
    ///
    /// Fallibility means that each iterator item is a `Result`, which may
    /// indicate a parse error of the on-disk dirstate-v2 format. Such errors
    /// should only happen if Mercurial is buggy or a repository is corrupted.
    fn filter_full_paths<'tree>(
        &'tree self,
        predicate: impl Fn(&DirstateEntry) -> bool + 'tree,
    ) -> impl Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + 'tree
    {
        filter_map_results(self.iter_nodes(), move |node| {
            if let Some(entry) = node.entry()? {
                if predicate(&entry) {
                    return Ok(Some(node.full_path(self.on_disk)?));
                }
            }
            Ok(None)
        })
    }
}

/// Like `Iterator::filter_map`, but over a fallible iterator of `Result`s.
///
/// The callback is only called for incoming `Ok` values. Errors are passed
/// through as-is. In order to let it use the `?` operator the callback is
/// expected to return a `Result` of `Option`, instead of an `Option` of
/// `Result`.
fn filter_map_results<'a, I, F, A, B, E>(
    iter: I,
    f: F,
) -> impl Iterator<Item = Result<B, E>> + 'a
where
    I: Iterator<Item = Result<A, E>> + 'a,
    F: Fn(A) -> Result<Option<B>, E> + 'a,
{
    iter.filter_map(move |result| match result {
        Ok(node) => f(node).transpose(),
        Err(e) => Some(Err(e)),
    })
}

impl<'on_disk> super::dispatch::DirstateMapMethods for DirstateMap<'on_disk> {
    fn clear(&mut self) {
        self.root = Default::default();
        self.nodes_with_entry_count = 0;
        self.nodes_with_copy_source_count = 0;
    }

    fn add_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        entry: DirstateEntry,
    ) -> Result<(), DirstateError> {
        Ok(self.add_or_remove_file(filename, old_state, entry)?)
    }

    fn remove_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        size: i32,
    ) -> Result<(), DirstateError> {
        let entry = DirstateEntry {
            state: EntryState::Removed,
            mode: 0,
            size,
            mtime: 0,
        };
        Ok(self.add_or_remove_file(filename, old_state, entry)?)
    }

    fn drop_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
    ) -> Result<bool, DirstateError> {
        struct Dropped {
            was_tracked: bool,
            had_entry: bool,
            had_copy_source: bool,
        }
        fn recur<'on_disk>(
            on_disk: &'on_disk [u8],
            nodes: &mut ChildNodes<'on_disk>,
            path: &HgPath,
        ) -> Result<Option<Dropped>, DirstateV2ParseError> {
            let (first_path_component, rest_of_path) =
                path.split_first_component();
            let node = if let Some(node) =
                nodes.make_mut(on_disk)?.get_mut(first_path_component)
            {
                node
            } else {
                return Ok(None);
            };
            let dropped;
            if let Some(rest) = rest_of_path {
                if let Some(d) = recur(on_disk, &mut node.children, rest)? {
                    dropped = d;
                    if dropped.was_tracked {
                        node.tracked_descendants_count -= 1;
                    }
                } else {
                    return Ok(None);
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
                nodes.make_mut(on_disk)?.remove(first_path_component);
            }
            Ok(Some(dropped))
        }

        if let Some(dropped) = recur(self.on_disk, &mut self.root, filename)? {
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

    fn clear_ambiguous_times(
        &mut self,
        filenames: Vec<HgPathBuf>,
        now: i32,
    ) -> Result<(), DirstateV2ParseError> {
        for filename in filenames {
            if let Some(node) =
                Self::get_node_mut(self.on_disk, &mut self.root, &filename)?
            {
                if let Some(entry) = node.entry.as_mut() {
                    entry.clear_ambiguous_mtime(now);
                }
            }
        }
        Ok(())
    }

    fn non_normal_entries_contains(
        &mut self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError> {
        Ok(if let Some(node) = self.get_node(key)? {
            node.entry()?.map_or(false, |entry| entry.is_non_normal())
        } else {
            false
        })
    }

    fn non_normal_entries_remove(&mut self, _key: &HgPath) {
        // Do nothing, this `DirstateMap` does not have a separate "non normal
        // entries" set that need to be kept up to date
    }

    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + '_>
    {
        Box::new(self.filter_full_paths(|entry| {
            entry.is_non_normal() || entry.is_from_other_parent()
        }))
    }

    fn set_non_normal_other_parent_entries(&mut self, _force: bool) {
        // Do nothing, this `DirstateMap` does not have a separate "non normal
        // entries" and "from other parent" sets that need to be recomputed
    }

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    > {
        self.iter_non_normal_paths_panic()
    }

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    > {
        Box::new(self.filter_full_paths(|entry| entry.is_non_normal()))
    }

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    > {
        Box::new(self.filter_full_paths(|entry| entry.is_from_other_parent()))
    }

    fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateError> {
        if let Some(node) = self.get_node(directory)? {
            // A node without a `DirstateEntry` was created to hold child
            // nodes, and is therefore a directory.
            Ok(!node.has_entry() && node.tracked_descendants_count() > 0)
        } else {
            Ok(false)
        }
    }

    fn has_dir(&mut self, directory: &HgPath) -> Result<bool, DirstateError> {
        if let Some(node) = self.get_node(directory)? {
            // A node without a `DirstateEntry` was created to hold child
            // nodes, and is therefore a directory.
            Ok(!node.has_entry())
        } else {
            Ok(false)
        }
    }

    #[timed]
    fn pack_v1(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError> {
        let now: i32 = now.0.try_into().expect("time overflow");
        let mut ambiguous_mtimes = Vec::new();
        // Optizimation (to be measured?): pre-compute size to avoid `Vec`
        // reallocations
        let mut size = parents.as_bytes().len();
        for node in self.iter_nodes() {
            let node = node?;
            if let Some(entry) = node.entry()? {
                size += packed_entry_size(
                    node.full_path(self.on_disk)?,
                    node.copy_source(self.on_disk)?,
                );
                if entry.mtime_is_ambiguous(now) {
                    ambiguous_mtimes.push(node.full_path_cow(self.on_disk)?)
                }
            }
        }
        self.clear_known_ambiguous_mtimes(&ambiguous_mtimes)?;

        let mut packed = Vec::with_capacity(size);
        packed.extend(parents.as_bytes());

        for node in self.iter_nodes() {
            let node = node?;
            if let Some(entry) = node.entry()? {
                pack_entry(
                    node.full_path(self.on_disk)?,
                    &entry,
                    node.copy_source(self.on_disk)?,
                    &mut packed,
                );
            }
        }
        Ok(packed)
    }

    #[timed]
    fn pack_v2(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError> {
        // TODO: how do we want to handle this in 2038?
        let now: i32 = now.0.try_into().expect("time overflow");
        let mut paths = Vec::new();
        for node in self.iter_nodes() {
            let node = node?;
            if let Some(entry) = node.entry()? {
                if entry.mtime_is_ambiguous(now) {
                    paths.push(node.full_path_cow(self.on_disk)?)
                }
            }
        }
        // Borrow of `self` ends here since we collect cloned paths

        self.clear_known_ambiguous_mtimes(&paths)?;

        on_disk::write(self, parents)
    }

    fn set_all_dirs(&mut self) -> Result<(), DirstateError> {
        // Do nothing, this `DirstateMap` does not a separate `all_dirs` that
        // needs to be recomputed
        Ok(())
    }

    fn set_dirs(&mut self) -> Result<(), DirstateError> {
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
        self.nodes_with_copy_source_count as usize
    }

    fn copy_map_iter(&self) -> CopyMapIter<'_> {
        Box::new(filter_map_results(self.iter_nodes(), move |node| {
            Ok(if let Some(source) = node.copy_source(self.on_disk)? {
                Some((node.full_path(self.on_disk)?, source))
            } else {
                None
            })
        }))
    }

    fn copy_map_contains_key(
        &self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError> {
        Ok(if let Some(node) = self.get_node(key)? {
            node.has_copy_source()
        } else {
            false
        })
    }

    fn copy_map_get(
        &self,
        key: &HgPath,
    ) -> Result<Option<&HgPath>, DirstateV2ParseError> {
        if let Some(node) = self.get_node(key)? {
            if let Some(source) = node.copy_source(self.on_disk)? {
                return Ok(Some(source));
            }
        }
        Ok(None)
    }

    fn copy_map_remove(
        &mut self,
        key: &HgPath,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError> {
        let count = &mut self.nodes_with_copy_source_count;
        Ok(
            Self::get_node_mut(self.on_disk, &mut self.root, key)?.and_then(
                |node| {
                    if node.copy_source.is_some() {
                        *count -= 1
                    }
                    node.copy_source.take().map(Cow::into_owned)
                },
            ),
        )
    }

    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError> {
        let node = Self::get_or_insert_node(
            self.on_disk,
            &mut self.root,
            &key,
            WithBasename::to_cow_owned,
            |_ancestor| {},
        )?;
        if node.copy_source.is_none() {
            self.nodes_with_copy_source_count += 1
        }
        Ok(node.copy_source.replace(value.into()).map(Cow::into_owned))
    }

    fn len(&self) -> usize {
        self.nodes_with_entry_count as usize
    }

    fn contains_key(
        &self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError> {
        Ok(self.get(key)?.is_some())
    }

    fn get(
        &self,
        key: &HgPath,
    ) -> Result<Option<DirstateEntry>, DirstateV2ParseError> {
        Ok(if let Some(node) = self.get_node(key)? {
            node.entry()?
        } else {
            None
        })
    }

    fn iter(&self) -> StateMapIter<'_> {
        Box::new(filter_map_results(self.iter_nodes(), move |node| {
            Ok(if let Some(entry) = node.entry()? {
                Some((node.full_path(self.on_disk)?, entry))
            } else {
                None
            })
        }))
    }
}

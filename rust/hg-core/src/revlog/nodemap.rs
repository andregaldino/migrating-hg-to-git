// Copyright 2018-2020 Georges Racinet <georges.racinet@octobus.net>
//           and Mercurial contributors
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.
//! Indexing facilities for fast retrieval of `Revision` from `Node`
//!
//! This provides a variation on the 16-ary radix tree that is
//! provided as "nodetree" in revlog.c, ready for append-only persistence
//! on disk.
//!
//! Following existing implicit conventions, the "nodemap" terminology
//! is used in a more abstract context.

use super::{
    node::NULL_NODE, Node, NodeError, NodePrefix, NodePrefixRef, Revision,
    RevlogIndex, NULL_REVISION,
};

use std::cmp::max;
use std::fmt;
use std::mem;
use std::ops::Deref;
use std::ops::Index;
use std::slice;

#[derive(Debug, PartialEq)]
pub enum NodeMapError {
    MultipleResults,
    InvalidNodePrefix(NodeError),
    /// A `Revision` stored in the nodemap could not be found in the index
    RevisionNotInIndex(Revision),
}

impl From<NodeError> for NodeMapError {
    fn from(err: NodeError) -> Self {
        NodeMapError::InvalidNodePrefix(err)
    }
}

/// Mapping system from Mercurial nodes to revision numbers.
///
/// ## `RevlogIndex` and `NodeMap`
///
/// One way to think about their relationship is that
/// the `NodeMap` is a prefix-oriented reverse index of the `Node` information
/// carried by a [`RevlogIndex`].
///
/// Many of the methods in this trait take a `RevlogIndex` argument
/// which is used for validation of their results. This index must naturally
/// be the one the `NodeMap` is about, and it must be consistent.
///
/// Notably, the `NodeMap` must not store
/// information about more `Revision` values than there are in the index.
/// In these methods, an encountered `Revision` is not in the index, a
/// [`RevisionNotInIndex`] error is returned.
///
/// In insert operations, the rule is thus that the `NodeMap` must always
/// be updated after the `RevlogIndex`
/// be updated first, and the `NodeMap` second.
///
/// [`RevisionNotInIndex`]: enum.NodeMapError.html#variant.RevisionNotInIndex
/// [`RevlogIndex`]: ../trait.RevlogIndex.html
pub trait NodeMap {
    /// Find the unique `Revision` having the given `Node`
    ///
    /// If no Revision matches the given `Node`, `Ok(None)` is returned.
    fn find_node(
        &self,
        index: &impl RevlogIndex,
        node: &Node,
    ) -> Result<Option<Revision>, NodeMapError> {
        self.find_bin(index, node.into())
    }

    /// Find the unique Revision whose `Node` starts with a given binary prefix
    ///
    /// If no Revision matches the given prefix, `Ok(None)` is returned.
    ///
    /// If several Revisions match the given prefix, a [`MultipleResults`]
    /// error is returned.
    fn find_bin<'a>(
        &self,
        idx: &impl RevlogIndex,
        prefix: NodePrefixRef<'a>,
    ) -> Result<Option<Revision>, NodeMapError>;

    /// Find the unique Revision whose `Node` hexadecimal string representation
    /// starts with a given prefix
    ///
    /// If no Revision matches the given prefix, `Ok(None)` is returned.
    ///
    /// If several Revisions match the given prefix, a [`MultipleResults`]
    /// error is returned.
    fn find_hex(
        &self,
        idx: &impl RevlogIndex,
        prefix: &str,
    ) -> Result<Option<Revision>, NodeMapError> {
        self.find_bin(idx, NodePrefix::from_hex(prefix)?.borrow())
    }

    /// Give the size of the shortest node prefix that determines
    /// the revision uniquely.
    ///
    /// From a binary node prefix, if it is matched in the node map, this
    /// returns the number of hexadecimal digits that would had sufficed
    /// to find the revision uniquely.
    ///
    /// Returns `None` if no `Revision` could be found for the prefix.
    ///
    /// If several Revisions match the given prefix, a [`MultipleResults`]
    /// error is returned.
    fn unique_prefix_len_bin<'a>(
        &self,
        idx: &impl RevlogIndex,
        node_prefix: NodePrefixRef<'a>,
    ) -> Result<Option<usize>, NodeMapError>;

    /// Same as `unique_prefix_len_bin`, with the hexadecimal representation
    /// of the prefix as input.
    fn unique_prefix_len_hex(
        &self,
        idx: &impl RevlogIndex,
        prefix: &str,
    ) -> Result<Option<usize>, NodeMapError> {
        self.unique_prefix_len_bin(idx, NodePrefix::from_hex(prefix)?.borrow())
    }

    /// Same as `unique_prefix_len_bin`, with a full `Node` as input
    fn unique_prefix_len_node(
        &self,
        idx: &impl RevlogIndex,
        node: &Node,
    ) -> Result<Option<usize>, NodeMapError> {
        self.unique_prefix_len_bin(idx, node.into())
    }
}

pub trait MutableNodeMap: NodeMap {
    fn insert<I: RevlogIndex>(
        &mut self,
        index: &I,
        node: &Node,
        rev: Revision,
    ) -> Result<(), NodeMapError>;
}

/// Low level NodeTree [`Blocks`] elements
///
/// These are exactly as for instance on persistent storage.
type RawElement = i32;

/// High level representation of values in NodeTree
/// [`Blocks`](struct.Block.html)
///
/// This is the high level representation that most algorithms should
/// use.
#[derive(Clone, Debug, Eq, PartialEq)]
enum Element {
    Rev(Revision),
    Block(usize),
    None,
}

impl From<RawElement> for Element {
    /// Conversion from low level representation, after endianness conversion.
    ///
    /// See [`Block`](struct.Block.html) for explanation about the encoding.
    fn from(raw: RawElement) -> Element {
        if raw >= 0 {
            Element::Block(raw as usize)
        } else if raw == -1 {
            Element::None
        } else {
            Element::Rev(-raw - 2)
        }
    }
}

impl From<Element> for RawElement {
    fn from(element: Element) -> RawElement {
        match element {
            Element::None => 0,
            Element::Block(i) => i as RawElement,
            Element::Rev(rev) => -rev - 2,
        }
    }
}

/// A logical block of the `NodeTree`, packed with a fixed size.
///
/// These are always used in container types implementing `Index<Block>`,
/// such as `&Block`
///
/// As an array of integers, its ith element encodes that the
/// ith potential edge from the block, representing the ith hexadecimal digit
/// (nybble) `i` is either:
///
/// - absent (value -1)
/// - another `Block` in the same indexable container (value ≥ 0)
///  - a `Revision` leaf (value ≤ -2)
///
/// Endianness has to be fixed for consistency on shared storage across
/// different architectures.
///
/// A key difference with the C `nodetree` is that we need to be
/// able to represent the [`Block`] at index 0, hence -1 is the empty marker
/// rather than 0 and the `Revision` range upper limit of -2 instead of -1.
///
/// Another related difference is that `NULL_REVISION` (-1) is not
/// represented at all, because we want an immutable empty nodetree
/// to be valid.

#[derive(Copy, Clone)]
pub struct Block([u8; BLOCK_SIZE]);

/// Not derivable for arrays of length >32 until const generics are stable
impl PartialEq for Block {
    fn eq(&self, other: &Self) -> bool {
        &self.0[..] == &other.0[..]
    }
}

pub const BLOCK_SIZE: usize = 64;

impl Block {
    fn new() -> Self {
        // -1 in 2's complement to create an absent node
        let byte: u8 = 255;
        Block([byte; BLOCK_SIZE])
    }

    fn get(&self, nybble: u8) -> Element {
        let index = nybble as usize * mem::size_of::<RawElement>();
        Element::from(RawElement::from_be_bytes([
            self.0[index],
            self.0[index + 1],
            self.0[index + 2],
            self.0[index + 3],
        ]))
    }

    fn set(&mut self, nybble: u8, element: Element) {
        let values = RawElement::to_be_bytes(element.into());
        let index = nybble as usize * mem::size_of::<RawElement>();
        self.0[index] = values[0];
        self.0[index + 1] = values[1];
        self.0[index + 2] = values[2];
        self.0[index + 3] = values[3];
    }
}

impl fmt::Debug for Block {
    /// sparse representation for testing and debugging purposes
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.debug_map()
            .entries((0..16).filter_map(|i| match self.get(i) {
                Element::None => None,
                element => Some((i, element)),
            }))
            .finish()
    }
}

/// A mutable 16-radix tree with the root block logically at the end
///
/// Because of the append only nature of our node trees, we need to
/// keep the original untouched and store new blocks separately.
///
/// The mutable root `Block` is kept apart so that we don't have to rebump
/// it on each insertion.
pub struct NodeTree {
    readonly: Box<dyn Deref<Target = [Block]> + Send>,
    growable: Vec<Block>,
    root: Block,
    masked_inner_blocks: usize,
}

impl Index<usize> for NodeTree {
    type Output = Block;

    fn index(&self, i: usize) -> &Block {
        let ro_len = self.readonly.len();
        if i < ro_len {
            &self.readonly[i]
        } else if i == ro_len + self.growable.len() {
            &self.root
        } else {
            &self.growable[i - ro_len]
        }
    }
}

/// Return `None` unless the `Node` for `rev` has given prefix in `index`.
fn has_prefix_or_none(
    idx: &impl RevlogIndex,
    prefix: NodePrefixRef,
    rev: Revision,
) -> Result<Option<Revision>, NodeMapError> {
    idx.node(rev)
        .ok_or_else(|| NodeMapError::RevisionNotInIndex(rev))
        .map(|node| {
            if prefix.is_prefix_of(node) {
                Some(rev)
            } else {
                None
            }
        })
}

/// validate that the candidate's node starts indeed with given prefix,
/// and treat ambiguities related to `NULL_REVISION`.
///
/// From the data in the NodeTree, one can only conclude that some
/// revision is the only one for a *subprefix* of the one being looked up.
fn validate_candidate(
    idx: &impl RevlogIndex,
    prefix: NodePrefixRef,
    candidate: (Option<Revision>, usize),
) -> Result<(Option<Revision>, usize), NodeMapError> {
    let (rev, steps) = candidate;
    if let Some(nz_nybble) = prefix.first_different_nybble(&NULL_NODE) {
        rev.map_or(Ok((None, steps)), |r| {
            has_prefix_or_none(idx, prefix, r)
                .map(|opt| (opt, max(steps, nz_nybble + 1)))
        })
    } else {
        // the prefix is only made of zeros; NULL_REVISION always matches it
        // and any other *valid* result is an ambiguity
        match rev {
            None => Ok((Some(NULL_REVISION), steps + 1)),
            Some(r) => match has_prefix_or_none(idx, prefix, r)? {
                None => Ok((Some(NULL_REVISION), steps + 1)),
                _ => Err(NodeMapError::MultipleResults),
            },
        }
    }
}

impl NodeTree {
    /// Initiate a NodeTree from an immutable slice-like of `Block`
    ///
    /// We keep `readonly` and clone its root block if it isn't empty.
    fn new(readonly: Box<dyn Deref<Target = [Block]> + Send>) -> Self {
        let root = readonly
            .last()
            .map(|b| b.clone())
            .unwrap_or_else(|| Block::new());
        NodeTree {
            readonly: readonly,
            growable: Vec::new(),
            root: root,
            masked_inner_blocks: 0,
        }
    }

    /// Create from an opaque bunch of bytes
    ///
    /// The created `NodeTreeBytes` from `buffer`,
    /// of which exactly `amount` bytes are used.
    ///
    /// - `buffer` could be derived from `PyBuffer` and `Mmap` objects.
    /// - `offset` allows for the final file format to include fixed data
    ///   (generation number, behavioural flags)
    /// - `amount` is expressed in bytes, and is not automatically derived from
    ///   `bytes`, so that a caller that manages them atomically can perform
    ///   temporary disk serializations and still rollback easily if needed.
    ///   First use-case for this would be to support Mercurial shell hooks.
    ///
    /// panics if `buffer` is smaller than `amount`
    pub fn load_bytes(
        bytes: Box<dyn Deref<Target = [u8]> + Send>,
        amount: usize,
    ) -> Self {
        NodeTree::new(Box::new(NodeTreeBytes::new(bytes, amount)))
    }

    /// Retrieve added `Block` and the original immutable data
    pub fn into_readonly_and_added(
        self,
    ) -> (Box<dyn Deref<Target = [Block]> + Send>, Vec<Block>) {
        let mut vec = self.growable;
        let readonly = self.readonly;
        if readonly.last() != Some(&self.root) {
            vec.push(self.root);
        }
        (readonly, vec)
    }

    /// Retrieve added `Blocks` as bytes, ready to be written to persistent
    /// storage
    pub fn into_readonly_and_added_bytes(
        self,
    ) -> (Box<dyn Deref<Target = [Block]> + Send>, Vec<u8>) {
        let (readonly, vec) = self.into_readonly_and_added();
        // Prevent running `v`'s destructor so we are in complete control
        // of the allocation.
        let vec = mem::ManuallyDrop::new(vec);

        // Transmute the `Vec<Block>` to a `Vec<u8>`. Blocks are contiguous
        // bytes, so this is perfectly safe.
        let bytes = unsafe {
            // Assert that `Block` hasn't been changed and has no padding
            let _: [u8; 4 * BLOCK_SIZE] =
                std::mem::transmute([Block::new(); 4]);

            // /!\ Any use of `vec` after this is use-after-free.
            // TODO: use `into_raw_parts` once stabilized
            Vec::from_raw_parts(
                vec.as_ptr() as *mut u8,
                vec.len() * BLOCK_SIZE,
                vec.capacity() * BLOCK_SIZE,
            )
        };
        (readonly, bytes)
    }

    /// Total number of blocks
    fn len(&self) -> usize {
        self.readonly.len() + self.growable.len() + 1
    }

    /// Implemented for completeness
    ///
    /// A `NodeTree` always has at least the mutable root block.
    #[allow(dead_code)]
    fn is_empty(&self) -> bool {
        false
    }

    /// Main working method for `NodeTree` searches
    ///
    /// The first returned value is the result of analysing `NodeTree` data
    /// *alone*: whereas `None` guarantees that the given prefix is absent
    /// from the `NodeTree` data (but still could match `NULL_NODE`), with
    /// `Some(rev)`, it is to be understood that `rev` is the unique `Revision`
    /// that could match the prefix. Actually, all that can be inferred from
    /// the `NodeTree` data is that `rev` is the revision with the longest
    /// common node prefix with the given prefix.
    ///
    /// The second returned value is the size of the smallest subprefix
    /// of `prefix` that would give the same result, i.e. not the
    /// `MultipleResults` error variant (again, using only the data of the
    /// `NodeTree`).
    fn lookup(
        &self,
        prefix: NodePrefixRef,
    ) -> Result<(Option<Revision>, usize), NodeMapError> {
        for (i, visit_item) in self.visit(prefix).enumerate() {
            if let Some(opt) = visit_item.final_revision() {
                return Ok((opt, i + 1));
            }
        }
        Err(NodeMapError::MultipleResults)
    }

    fn visit<'n, 'p>(
        &'n self,
        prefix: NodePrefixRef<'p>,
    ) -> NodeTreeVisitor<'n, 'p> {
        NodeTreeVisitor {
            nt: self,
            prefix: prefix,
            visit: self.len() - 1,
            nybble_idx: 0,
            done: false,
        }
    }
    /// Return a mutable reference for `Block` at index `idx`.
    ///
    /// If `idx` lies in the immutable area, then the reference is to
    /// a newly appended copy.
    ///
    /// Returns (new_idx, glen, mut_ref) where
    ///
    /// - `new_idx` is the index of the mutable `Block`
    /// - `mut_ref` is a mutable reference to the mutable Block.
    /// - `glen` is the new length of `self.growable`
    ///
    /// Note: the caller wouldn't be allowed to query `self.growable.len()`
    /// itself because of the mutable borrow taken with the returned `Block`
    fn mutable_block(&mut self, idx: usize) -> (usize, &mut Block, usize) {
        let ro_blocks = &self.readonly;
        let ro_len = ro_blocks.len();
        let glen = self.growable.len();
        if idx < ro_len {
            self.masked_inner_blocks += 1;
            // TODO OPTIM I think this makes two copies
            self.growable.push(ro_blocks[idx].clone());
            (glen + ro_len, &mut self.growable[glen], glen + 1)
        } else if glen + ro_len == idx {
            (idx, &mut self.root, glen)
        } else {
            (idx, &mut self.growable[idx - ro_len], glen)
        }
    }

    /// Main insertion method
    ///
    /// This will dive in the node tree to find the deepest `Block` for
    /// `node`, split it as much as needed and record `node` in there.
    /// The method then backtracks, updating references in all the visited
    /// blocks from the root.
    ///
    /// All the mutated `Block` are copied first to the growable part if
    /// needed. That happens for those in the immutable part except the root.
    pub fn insert<I: RevlogIndex>(
        &mut self,
        index: &I,
        node: &Node,
        rev: Revision,
    ) -> Result<(), NodeMapError> {
        let ro_len = &self.readonly.len();

        let mut visit_steps: Vec<_> = self.visit(node.into()).collect();
        let read_nybbles = visit_steps.len();
        // visit_steps cannot be empty, since we always visit the root block
        let deepest = visit_steps.pop().unwrap();

        let (mut block_idx, mut block, mut glen) =
            self.mutable_block(deepest.block_idx);

        if let Element::Rev(old_rev) = deepest.element {
            let old_node = index
                .node(old_rev)
                .ok_or_else(|| NodeMapError::RevisionNotInIndex(old_rev))?;
            if old_node == node {
                return Ok(()); // avoid creating lots of useless blocks
            }

            // Looping over the tail of nybbles in both nodes, creating
            // new blocks until we find the difference
            let mut new_block_idx = ro_len + glen;
            let mut nybble = deepest.nybble;
            for nybble_pos in read_nybbles..node.nybbles_len() {
                block.set(nybble, Element::Block(new_block_idx));

                let new_nybble = node.get_nybble(nybble_pos);
                let old_nybble = old_node.get_nybble(nybble_pos);

                if old_nybble == new_nybble {
                    self.growable.push(Block::new());
                    block = &mut self.growable[glen];
                    glen += 1;
                    new_block_idx += 1;
                    nybble = new_nybble;
                } else {
                    let mut new_block = Block::new();
                    new_block.set(old_nybble, Element::Rev(old_rev));
                    new_block.set(new_nybble, Element::Rev(rev));
                    self.growable.push(new_block);
                    break;
                }
            }
        } else {
            // Free slot in the deepest block: no splitting has to be done
            block.set(deepest.nybble, Element::Rev(rev));
        }

        // Backtrack over visit steps to update references
        while let Some(visited) = visit_steps.pop() {
            let to_write = Element::Block(block_idx);
            if visit_steps.is_empty() {
                self.root.set(visited.nybble, to_write);
                break;
            }
            let (new_idx, block, _) = self.mutable_block(visited.block_idx);
            if block.get(visited.nybble) == to_write {
                break;
            }
            block.set(visited.nybble, to_write);
            block_idx = new_idx;
        }
        Ok(())
    }

    /// Return the number of blocks in the readonly part that are currently
    /// masked in the mutable part.
    ///
    /// The `NodeTree` structure has no efficient way to know how many blocks
    /// are already unreachable in the readonly part.
    pub fn masked_readonly_blocks(&self) -> usize {
        if let Some(readonly_root) = self.readonly.last() {
            if readonly_root == &self.root {
                return 0;
            }
        } else {
            return 0;
        }
        self.masked_inner_blocks + 1
    }
}

pub struct NodeTreeBytes {
    buffer: Box<dyn Deref<Target = [u8]> + Send>,
    len_in_blocks: usize,
}

impl NodeTreeBytes {
    fn new(
        buffer: Box<dyn Deref<Target = [u8]> + Send>,
        amount: usize,
    ) -> Self {
        assert!(buffer.len() >= amount);
        let len_in_blocks = amount / BLOCK_SIZE;
        NodeTreeBytes {
            buffer,
            len_in_blocks,
        }
    }
}

impl Deref for NodeTreeBytes {
    type Target = [Block];

    fn deref(&self) -> &[Block] {
        unsafe {
            slice::from_raw_parts(
                (&self.buffer).as_ptr() as *const Block,
                self.len_in_blocks,
            )
        }
    }
}

struct NodeTreeVisitor<'n, 'p> {
    nt: &'n NodeTree,
    prefix: NodePrefixRef<'p>,
    visit: usize,
    nybble_idx: usize,
    done: bool,
}

#[derive(Debug, PartialEq, Clone)]
struct NodeTreeVisitItem {
    block_idx: usize,
    nybble: u8,
    element: Element,
}

impl<'n, 'p> Iterator for NodeTreeVisitor<'n, 'p> {
    type Item = NodeTreeVisitItem;

    fn next(&mut self) -> Option<Self::Item> {
        if self.done || self.nybble_idx >= self.prefix.len() {
            return None;
        }

        let nybble = self.prefix.get_nybble(self.nybble_idx);
        self.nybble_idx += 1;

        let visit = self.visit;
        let element = self.nt[visit].get(nybble);
        if let Element::Block(idx) = element {
            self.visit = idx;
        } else {
            self.done = true;
        }

        Some(NodeTreeVisitItem {
            block_idx: visit,
            nybble: nybble,
            element: element,
        })
    }
}

impl NodeTreeVisitItem {
    // Return `Some(opt)` if this item is final, with `opt` being the
    // `Revision` that it may represent.
    //
    // If the item is not terminal, return `None`
    fn final_revision(&self) -> Option<Option<Revision>> {
        match self.element {
            Element::Block(_) => None,
            Element::Rev(r) => Some(Some(r)),
            Element::None => Some(None),
        }
    }
}

impl From<Vec<Block>> for NodeTree {
    fn from(vec: Vec<Block>) -> Self {
        Self::new(Box::new(vec))
    }
}

impl fmt::Debug for NodeTree {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let readonly: &[Block] = &*self.readonly;
        write!(
            f,
            "readonly: {:?}, growable: {:?}, root: {:?}",
            readonly, self.growable, self.root
        )
    }
}

impl Default for NodeTree {
    /// Create a fully mutable empty NodeTree
    fn default() -> Self {
        NodeTree::new(Box::new(Vec::new()))
    }
}

impl NodeMap for NodeTree {
    fn find_bin<'a>(
        &self,
        idx: &impl RevlogIndex,
        prefix: NodePrefixRef<'a>,
    ) -> Result<Option<Revision>, NodeMapError> {
        validate_candidate(idx, prefix.clone(), self.lookup(prefix)?)
            .map(|(opt, _shortest)| opt)
    }

    fn unique_prefix_len_bin<'a>(
        &self,
        idx: &impl RevlogIndex,
        prefix: NodePrefixRef<'a>,
    ) -> Result<Option<usize>, NodeMapError> {
        validate_candidate(idx, prefix.clone(), self.lookup(prefix)?)
            .map(|(opt, shortest)| opt.map(|_rev| shortest))
    }
}

#[cfg(test)]
mod tests {
    use super::NodeMapError::*;
    use super::*;
    use crate::revlog::node::{hex_pad_right, Node};
    use std::collections::HashMap;

    /// Creates a `Block` using a syntax close to the `Debug` output
    macro_rules! block {
        {$($nybble:tt : $variant:ident($val:tt)),*} => (
            {
                let mut block = Block::new();
                $(block.set($nybble, Element::$variant($val)));*;
                block
            }
        )
    }

    #[test]
    fn test_block_debug() {
        let mut block = Block::new();
        block.set(1, Element::Rev(3));
        block.set(10, Element::Block(0));
        assert_eq!(format!("{:?}", block), "{1: Rev(3), 10: Block(0)}");
    }

    #[test]
    fn test_block_macro() {
        let block = block! {5: Block(2)};
        assert_eq!(format!("{:?}", block), "{5: Block(2)}");

        let block = block! {13: Rev(15), 5: Block(2)};
        assert_eq!(format!("{:?}", block), "{5: Block(2), 13: Rev(15)}");
    }

    #[test]
    fn test_raw_block() {
        let mut raw = [255u8; 64];

        let mut counter = 0;
        for val in [0, 15, -2, -1, -3].iter() {
            for byte in RawElement::to_be_bytes(*val).iter() {
                raw[counter] = *byte;
                counter += 1;
            }
        }
        let block = Block(raw);
        assert_eq!(block.get(0), Element::Block(0));
        assert_eq!(block.get(1), Element::Block(15));
        assert_eq!(block.get(3), Element::None);
        assert_eq!(block.get(2), Element::Rev(0));
        assert_eq!(block.get(4), Element::Rev(1));
    }

    type TestIndex = HashMap<Revision, Node>;

    impl RevlogIndex for TestIndex {
        fn node(&self, rev: Revision) -> Option<&Node> {
            self.get(&rev)
        }

        fn len(&self) -> usize {
            self.len()
        }
    }

    /// Pad hexadecimal Node prefix with zeros on the right
    ///
    /// This avoids having to repeatedly write very long hexadecimal
    /// strings for test data, and brings actual hash size independency.
    #[cfg(test)]
    fn pad_node(hex: &str) -> Node {
        Node::from_hex(&hex_pad_right(hex)).unwrap()
    }

    /// Pad hexadecimal Node prefix with zeros on the right, then insert
    fn pad_insert(idx: &mut TestIndex, rev: Revision, hex: &str) {
        idx.insert(rev, pad_node(hex));
    }

    fn sample_nodetree() -> NodeTree {
        NodeTree::from(vec![
            block![0: Rev(9)],
            block![0: Rev(0), 1: Rev(9)],
            block![0: Block(1), 1:Rev(1)],
        ])
    }

    #[test]
    fn test_nt_debug() {
        let nt = sample_nodetree();
        assert_eq!(
            format!("{:?}", nt),
            "readonly: \
             [{0: Rev(9)}, {0: Rev(0), 1: Rev(9)}, {0: Block(1), 1: Rev(1)}], \
             growable: [], \
             root: {0: Block(1), 1: Rev(1)}",
        );
    }

    #[test]
    fn test_immutable_find_simplest() -> Result<(), NodeMapError> {
        let mut idx: TestIndex = HashMap::new();
        pad_insert(&mut idx, 1, "1234deadcafe");

        let nt = NodeTree::from(vec![block! {1: Rev(1)}]);
        assert_eq!(nt.find_hex(&idx, "1")?, Some(1));
        assert_eq!(nt.find_hex(&idx, "12")?, Some(1));
        assert_eq!(nt.find_hex(&idx, "1234de")?, Some(1));
        assert_eq!(nt.find_hex(&idx, "1a")?, None);
        assert_eq!(nt.find_hex(&idx, "ab")?, None);

        // and with full binary Nodes
        assert_eq!(nt.find_node(&idx, idx.get(&1).unwrap())?, Some(1));
        let unknown = Node::from_hex(&hex_pad_right("3d")).unwrap();
        assert_eq!(nt.find_node(&idx, &unknown)?, None);
        Ok(())
    }

    #[test]
    fn test_immutable_find_one_jump() {
        let mut idx = TestIndex::new();
        pad_insert(&mut idx, 9, "012");
        pad_insert(&mut idx, 0, "00a");

        let nt = sample_nodetree();

        assert_eq!(nt.find_hex(&idx, "0"), Err(MultipleResults));
        assert_eq!(nt.find_hex(&idx, "01"), Ok(Some(9)));
        assert_eq!(nt.find_hex(&idx, "00"), Err(MultipleResults));
        assert_eq!(nt.find_hex(&idx, "00a"), Ok(Some(0)));
        assert_eq!(nt.unique_prefix_len_hex(&idx, "00a"), Ok(Some(3)));
        assert_eq!(nt.find_hex(&idx, "000"), Ok(Some(NULL_REVISION)));
    }

    #[test]
    fn test_mutated_find() -> Result<(), NodeMapError> {
        let mut idx = TestIndex::new();
        pad_insert(&mut idx, 9, "012");
        pad_insert(&mut idx, 0, "00a");
        pad_insert(&mut idx, 2, "cafe");
        pad_insert(&mut idx, 3, "15");
        pad_insert(&mut idx, 1, "10");

        let nt = NodeTree {
            readonly: sample_nodetree().readonly,
            growable: vec![block![0: Rev(1), 5: Rev(3)]],
            root: block![0: Block(1), 1:Block(3), 12: Rev(2)],
            masked_inner_blocks: 1,
        };
        assert_eq!(nt.find_hex(&idx, "10")?, Some(1));
        assert_eq!(nt.find_hex(&idx, "c")?, Some(2));
        assert_eq!(nt.unique_prefix_len_hex(&idx, "c")?, Some(1));
        assert_eq!(nt.find_hex(&idx, "00"), Err(MultipleResults));
        assert_eq!(nt.find_hex(&idx, "000")?, Some(NULL_REVISION));
        assert_eq!(nt.unique_prefix_len_hex(&idx, "000")?, Some(3));
        assert_eq!(nt.find_hex(&idx, "01")?, Some(9));
        assert_eq!(nt.masked_readonly_blocks(), 2);
        Ok(())
    }

    struct TestNtIndex {
        index: TestIndex,
        nt: NodeTree,
    }

    impl TestNtIndex {
        fn new() -> Self {
            TestNtIndex {
                index: HashMap::new(),
                nt: NodeTree::default(),
            }
        }

        fn insert(
            &mut self,
            rev: Revision,
            hex: &str,
        ) -> Result<(), NodeMapError> {
            let node = pad_node(hex);
            self.index.insert(rev, node.clone());
            self.nt.insert(&self.index, &node, rev)?;
            Ok(())
        }

        fn find_hex(
            &self,
            prefix: &str,
        ) -> Result<Option<Revision>, NodeMapError> {
            self.nt.find_hex(&self.index, prefix)
        }

        fn unique_prefix_len_hex(
            &self,
            prefix: &str,
        ) -> Result<Option<usize>, NodeMapError> {
            self.nt.unique_prefix_len_hex(&self.index, prefix)
        }

        /// Drain `added` and restart a new one
        fn commit(self) -> Self {
            let mut as_vec: Vec<Block> =
                self.nt.readonly.iter().map(|block| block.clone()).collect();
            as_vec.extend(self.nt.growable);
            as_vec.push(self.nt.root);

            Self {
                index: self.index,
                nt: NodeTree::from(as_vec).into(),
            }
        }
    }

    #[test]
    fn test_insert_full_mutable() -> Result<(), NodeMapError> {
        let mut idx = TestNtIndex::new();
        idx.insert(0, "1234")?;
        assert_eq!(idx.find_hex("1")?, Some(0));
        assert_eq!(idx.find_hex("12")?, Some(0));

        // let's trigger a simple split
        idx.insert(1, "1a34")?;
        assert_eq!(idx.nt.growable.len(), 1);
        assert_eq!(idx.find_hex("12")?, Some(0));
        assert_eq!(idx.find_hex("1a")?, Some(1));

        // reinserting is a no_op
        idx.insert(1, "1a34")?;
        assert_eq!(idx.nt.growable.len(), 1);
        assert_eq!(idx.find_hex("12")?, Some(0));
        assert_eq!(idx.find_hex("1a")?, Some(1));

        idx.insert(2, "1a01")?;
        assert_eq!(idx.nt.growable.len(), 2);
        assert_eq!(idx.find_hex("1a"), Err(NodeMapError::MultipleResults));
        assert_eq!(idx.find_hex("12")?, Some(0));
        assert_eq!(idx.find_hex("1a3")?, Some(1));
        assert_eq!(idx.find_hex("1a0")?, Some(2));
        assert_eq!(idx.find_hex("1a12")?, None);

        // now let's make it split and create more than one additional block
        idx.insert(3, "1a345")?;
        assert_eq!(idx.nt.growable.len(), 4);
        assert_eq!(idx.find_hex("1a340")?, Some(1));
        assert_eq!(idx.find_hex("1a345")?, Some(3));
        assert_eq!(idx.find_hex("1a341")?, None);

        // there's no readonly block to mask
        assert_eq!(idx.nt.masked_readonly_blocks(), 0);
        Ok(())
    }

    #[test]
    fn test_unique_prefix_len_zero_prefix() {
        let mut idx = TestNtIndex::new();
        idx.insert(0, "00000abcd").unwrap();

        assert_eq!(idx.find_hex("000"), Err(NodeMapError::MultipleResults));
        // in the nodetree proper, this will be found at the first nybble
        // yet the correct answer for unique_prefix_len is not 1, nor 1+1,
        // but the first difference with `NULL_NODE`
        assert_eq!(idx.unique_prefix_len_hex("00000a"), Ok(Some(6)));
        assert_eq!(idx.unique_prefix_len_hex("00000ab"), Ok(Some(6)));

        // same with odd result
        idx.insert(1, "00123").unwrap();
        assert_eq!(idx.unique_prefix_len_hex("001"), Ok(Some(3)));
        assert_eq!(idx.unique_prefix_len_hex("0012"), Ok(Some(3)));

        // these are unchanged of course
        assert_eq!(idx.unique_prefix_len_hex("00000a"), Ok(Some(6)));
        assert_eq!(idx.unique_prefix_len_hex("00000ab"), Ok(Some(6)));
    }

    #[test]
    fn test_insert_extreme_splitting() -> Result<(), NodeMapError> {
        // check that the splitting loop is long enough
        let mut nt_idx = TestNtIndex::new();
        let nt = &mut nt_idx.nt;
        let idx = &mut nt_idx.index;

        let node0_hex = hex_pad_right("444444");
        let mut node1_hex = hex_pad_right("444444").clone();
        node1_hex.pop();
        node1_hex.push('5');
        let node0 = Node::from_hex(&node0_hex).unwrap();
        let node1 = Node::from_hex(&node1_hex).unwrap();

        idx.insert(0, node0.clone());
        nt.insert(idx, &node0, 0)?;
        idx.insert(1, node1.clone());
        nt.insert(idx, &node1, 1)?;

        assert_eq!(nt.find_bin(idx, (&node0).into())?, Some(0));
        assert_eq!(nt.find_bin(idx, (&node1).into())?, Some(1));
        Ok(())
    }

    #[test]
    fn test_insert_partly_immutable() -> Result<(), NodeMapError> {
        let mut idx = TestNtIndex::new();
        idx.insert(0, "1234")?;
        idx.insert(1, "1235")?;
        idx.insert(2, "131")?;
        idx.insert(3, "cafe")?;
        let mut idx = idx.commit();
        assert_eq!(idx.find_hex("1234")?, Some(0));
        assert_eq!(idx.find_hex("1235")?, Some(1));
        assert_eq!(idx.find_hex("131")?, Some(2));
        assert_eq!(idx.find_hex("cafe")?, Some(3));
        // we did not add anything since init from readonly
        assert_eq!(idx.nt.masked_readonly_blocks(), 0);

        idx.insert(4, "123A")?;
        assert_eq!(idx.find_hex("1234")?, Some(0));
        assert_eq!(idx.find_hex("1235")?, Some(1));
        assert_eq!(idx.find_hex("131")?, Some(2));
        assert_eq!(idx.find_hex("cafe")?, Some(3));
        assert_eq!(idx.find_hex("123A")?, Some(4));
        // we masked blocks for all prefixes of "123", including the root
        assert_eq!(idx.nt.masked_readonly_blocks(), 4);

        eprintln!("{:?}", idx.nt);
        idx.insert(5, "c0")?;
        assert_eq!(idx.find_hex("cafe")?, Some(3));
        assert_eq!(idx.find_hex("c0")?, Some(5));
        assert_eq!(idx.find_hex("c1")?, None);
        assert_eq!(idx.find_hex("1234")?, Some(0));
        // inserting "c0" is just splitting the 'c' slot of the mutable root,
        // it doesn't mask anything
        assert_eq!(idx.nt.masked_readonly_blocks(), 4);

        Ok(())
    }

    #[test]
    fn test_into_added_empty() {
        assert!(sample_nodetree().into_readonly_and_added().1.is_empty());
        assert!(sample_nodetree()
            .into_readonly_and_added_bytes()
            .1
            .is_empty());
    }

    #[test]
    fn test_into_added_bytes() -> Result<(), NodeMapError> {
        let mut idx = TestNtIndex::new();
        idx.insert(0, "1234")?;
        let mut idx = idx.commit();
        idx.insert(4, "cafe")?;
        let (_, bytes) = idx.nt.into_readonly_and_added_bytes();

        // only the root block has been changed
        assert_eq!(bytes.len(), BLOCK_SIZE);
        // big endian for -2
        assert_eq!(&bytes[4..2 * 4], [255, 255, 255, 254]);
        // big endian for -6
        assert_eq!(&bytes[12 * 4..13 * 4], [255, 255, 255, 250]);
        Ok(())
    }
}

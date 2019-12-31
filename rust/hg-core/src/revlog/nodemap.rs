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
    Node, NodeError, NodePrefix, NodePrefixRef, Revision, RevlogIndex,
};

use std::fmt;
use std::ops::Deref;
use std::ops::Index;

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

#[derive(Clone, PartialEq)]
pub struct Block([RawElement; 16]);

impl Block {
    fn new() -> Self {
        Block([-1; 16])
    }

    fn get(&self, nybble: u8) -> Element {
        Element::from(RawElement::from_be(self.0[nybble as usize]))
    }

    fn set(&mut self, nybble: u8, element: Element) {
        self.0[nybble as usize] = RawElement::to_be(element.into())
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
fn has_prefix_or_none<'p>(
    idx: &impl RevlogIndex,
    prefix: NodePrefixRef<'p>,
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
        }
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
    /// This partial implementation lacks special cases for NULL_REVISION
    fn lookup<'p>(
        &self,
        prefix: NodePrefixRef<'p>,
    ) -> Result<Option<Revision>, NodeMapError> {
        for visit_item in self.visit(prefix) {
            if let Some(opt) = visit_item.final_revision() {
                return Ok(opt);
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
        self.lookup(prefix.clone()).and_then(|opt| {
            opt.map_or(Ok(None), |rev| has_prefix_or_none(idx, prefix, rev))
        })
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
        let mut raw = [-1; 16];
        raw[0] = 0;
        raw[1] = RawElement::to_be(15);
        raw[2] = RawElement::to_be(-2);
        raw[3] = RawElement::to_be(-1);
        raw[4] = RawElement::to_be(-3);
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
        assert_eq!(nt.find_hex(&idx, "00"), Ok(Some(0)));
        assert_eq!(nt.find_hex(&idx, "00a"), Ok(Some(0)));
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
        };
        assert_eq!(nt.find_hex(&idx, "10")?, Some(1));
        assert_eq!(nt.find_hex(&idx, "c")?, Some(2));
        assert_eq!(nt.find_hex(&idx, "00")?, Some(0));
        assert_eq!(nt.find_hex(&idx, "01")?, Some(9));
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

        Ok(())
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

        idx.insert(4, "123A")?;
        assert_eq!(idx.find_hex("1234")?, Some(0));
        assert_eq!(idx.find_hex("1235")?, Some(1));
        assert_eq!(idx.find_hex("131")?, Some(2));
        assert_eq!(idx.find_hex("cafe")?, Some(3));
        assert_eq!(idx.find_hex("123A")?, Some(4));

        idx.insert(5, "c0")?;
        assert_eq!(idx.find_hex("cafe")?, Some(3));
        assert_eq!(idx.find_hex("c0")?, Some(5));
        assert_eq!(idx.find_hex("c1")?, None);
        assert_eq!(idx.find_hex("1234")?, Some(0));

        Ok(())
    }
}

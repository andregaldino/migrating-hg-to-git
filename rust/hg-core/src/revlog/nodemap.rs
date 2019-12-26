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

/// A 16-radix tree with the root block at the end
pub struct NodeTree {
    readonly: Box<dyn Deref<Target = [Block]> + Send>,
}

impl Index<usize> for NodeTree {
    type Output = Block;

    fn index(&self, i: usize) -> &Block {
        &self.readonly[i]
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
    fn len(&self) -> usize {
        self.readonly.len()
    }

    fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Main working method for `NodeTree` searches
    ///
    /// This partial implementation lacks special cases for NULL_REVISION
    fn lookup<'p>(
        &self,
        prefix: NodePrefixRef<'p>,
    ) -> Result<Option<Revision>, NodeMapError> {
        if self.is_empty() {
            return Ok(None);
        }
        let mut visit = self.len() - 1;
        for i in 0..prefix.len() {
            let nybble = prefix.get_nybble(i);
            match self[visit].get(nybble) {
                Element::None => return Ok(None),
                Element::Rev(r) => return Ok(Some(r)),
                Element::Block(idx) => visit = idx,
            }
        }
        Err(NodeMapError::MultipleResults)
    }
}

impl From<Vec<Block>> for NodeTree {
    fn from(vec: Vec<Block>) -> Self {
        NodeTree {
            readonly: Box::new(vec),
        }
    }
}

impl fmt::Debug for NodeTree {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let blocks: &[Block] = &*self.readonly;
        write!(f, "readonly: {:?}", blocks)
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

    /// Pad hexadecimal Node prefix with zeros on the right, then insert
    ///
    /// This avoids having to repeatedly write very long hexadecimal
    /// strings for test data, and brings actual hash size independency.
    fn pad_insert(idx: &mut TestIndex, rev: Revision, hex: &str) {
        idx.insert(rev, Node::from_hex(&hex_pad_right(hex)).unwrap());
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
             [{0: Rev(9)}, {0: Rev(0), 1: Rev(9)}, {0: Block(1), 1: Rev(1)}]"
        );
    }

    #[test]
    fn test_immutable_find_simplest() -> Result<(), NodeMapError> {
        let mut idx: TestIndex = HashMap::new();
        pad_insert(&mut idx, 1, "1234deadcafe");

        let nt = NodeTree::from(vec![block![1: Rev(1)]]);
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
}

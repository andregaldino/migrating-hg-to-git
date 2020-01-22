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

use super::Revision;
use std::fmt;

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

#[cfg(test)]
mod tests {
    use super::*;

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
}

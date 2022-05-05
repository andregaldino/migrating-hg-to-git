// Copyright 2019-2020 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Definitions and utilities for Revision nodes
//!
//! In Mercurial code base, it is customary to call "a node" the binary SHA
//! of a revision.

use crate::errors::HgError;
use bytes_cast::BytesCast;
use std::convert::{TryFrom, TryInto};
use std::fmt;

/// The length in bytes of a `Node`
///
/// This constant is meant to ease refactors of this module, and
/// are private so that calling code does not expect all nodes have
/// the same size, should we support several formats concurrently in
/// the future.
pub const NODE_BYTES_LENGTH: usize = 20;

/// Id of the null node.
///
/// Used to indicate the absence of node.
pub const NULL_NODE_ID: [u8; NODE_BYTES_LENGTH] = [0u8; NODE_BYTES_LENGTH];

/// The length in bytes of a `Node`
///
/// see also `NODES_BYTES_LENGTH` about it being private.
const NODE_NYBBLES_LENGTH: usize = 2 * NODE_BYTES_LENGTH;

/// Default for UI presentation
const SHORT_PREFIX_DEFAULT_NYBBLES_LENGTH: u8 = 12;

/// Private alias for readability and to ease future change
type NodeData = [u8; NODE_BYTES_LENGTH];

/// Binary revision SHA
///
/// ## Future changes of hash size
///
/// To accomodate future changes of hash size, Rust callers
/// should use the conversion methods at the boundaries (FFI, actual
/// computation of hashes and I/O) only, and only if required.
///
/// All other callers outside of unit tests should just handle `Node` values
/// and never make any assumption on the actual length, using [`nybbles_len`]
/// if they need a loop boundary.
///
/// All methods that create a `Node` either take a type that enforces
/// the size or return an error at runtime.
///
/// [`nybbles_len`]: #method.nybbles_len
#[derive(Copy, Clone, PartialEq, BytesCast, derive_more::From)]
#[repr(transparent)]
pub struct Node {
    data: NodeData,
}

impl fmt::Debug for Node {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let n = format!("{:x?}", self.data);
        // We're using debug_tuple because it makes the output a little
        // more compact without losing data.
        f.debug_tuple("Node").field(&n).finish()
    }
}

/// The node value for NULL_REVISION
pub const NULL_NODE: Node = Node {
    data: [0; NODE_BYTES_LENGTH],
};

/// Return an error if the slice has an unexpected length
impl<'a> TryFrom<&'a [u8]> for &'a Node {
    type Error = ();

    #[inline]
    fn try_from(bytes: &'a [u8]) -> Result<Self, Self::Error> {
        match Node::from_bytes(bytes) {
            Ok((node, rest)) if rest.is_empty() => Ok(node),
            _ => Err(()),
        }
    }
}

/// Return an error if the slice has an unexpected length
impl TryFrom<&'_ [u8]> for Node {
    type Error = std::array::TryFromSliceError;

    #[inline]
    fn try_from(bytes: &'_ [u8]) -> Result<Self, Self::Error> {
        let data = bytes.try_into()?;
        Ok(Self { data })
    }
}

impl From<&'_ NodeData> for Node {
    #[inline]
    fn from(data: &'_ NodeData) -> Self {
        Self { data: *data }
    }
}

impl fmt::LowerHex for Node {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        for &byte in &self.data {
            write!(f, "{:02x}", byte)?
        }
        Ok(())
    }
}

#[derive(Debug)]
pub struct FromHexError;

/// Low level utility function, also for prefixes
fn get_nybble(s: &[u8], i: usize) -> u8 {
    if i % 2 == 0 {
        s[i / 2] >> 4
    } else {
        s[i / 2] & 0x0f
    }
}

impl Node {
    /// Retrieve the `i`th half-byte of the binary data.
    ///
    /// This is also the `i`th hexadecimal digit in numeric form,
    /// also called a [nybble](https://en.wikipedia.org/wiki/Nibble).
    pub fn get_nybble(&self, i: usize) -> u8 {
        get_nybble(&self.data, i)
    }

    /// Length of the data, in nybbles
    pub fn nybbles_len(&self) -> usize {
        // public exposure as an instance method only, so that we can
        // easily support several sizes of hashes if needed in the future.
        NODE_NYBBLES_LENGTH
    }

    /// Convert from hexadecimal string representation
    ///
    /// Exact length is required.
    ///
    /// To be used in FFI and I/O only, in order to facilitate future
    /// changes of hash format.
    pub fn from_hex(hex: impl AsRef<[u8]>) -> Result<Node, FromHexError> {
        let prefix = NodePrefix::from_hex(hex)?;
        if prefix.nybbles_len() == NODE_NYBBLES_LENGTH {
            Ok(Self { data: prefix.data })
        } else {
            Err(FromHexError)
        }
    }

    /// `from_hex`, but for input from an internal file of the repository such
    /// as a changelog or manifest entry.
    ///
    /// An error is treated as repository corruption.
    pub fn from_hex_for_repo(hex: impl AsRef<[u8]>) -> Result<Node, HgError> {
        Self::from_hex(hex.as_ref()).map_err(|FromHexError| {
            HgError::CorruptedRepository(format!(
                "Expected a full hexadecimal node ID, found {}",
                String::from_utf8_lossy(hex.as_ref())
            ))
        })
    }

    /// Provide access to binary data
    ///
    /// This is needed by FFI layers, for instance to return expected
    /// binary values to Python.
    pub fn as_bytes(&self) -> &[u8] {
        &self.data
    }

    pub fn short(&self) -> NodePrefix {
        NodePrefix {
            nybbles_len: SHORT_PREFIX_DEFAULT_NYBBLES_LENGTH,
            data: self.data,
        }
    }

    pub fn pad_to_256_bits(&self) -> [u8; 32] {
        let mut bits = [0; 32];
        bits[..NODE_BYTES_LENGTH].copy_from_slice(&self.data);
        bits
    }
}

/// The beginning of a binary revision SHA.
///
/// Since it can potentially come from an hexadecimal representation with
/// odd length, it needs to carry around whether the last 4 bits are relevant
/// or not.
#[derive(Debug, PartialEq, Copy, Clone)]
pub struct NodePrefix {
    /// In `1..=NODE_NYBBLES_LENGTH`
    nybbles_len: u8,
    /// The first `4 * length_in_nybbles` bits are used (considering bits
    /// within a bytes in big-endian: most significant first), the rest
    /// are zero.
    data: NodeData,
}

impl NodePrefix {
    /// Convert from hexadecimal string representation
    ///
    /// Similarly to `hex::decode`, can be used with Unicode string types
    /// (`String`, `&str`) as well as bytes.
    ///
    /// To be used in FFI and I/O only, in order to facilitate future
    /// changes of hash format.
    pub fn from_hex(hex: impl AsRef<[u8]>) -> Result<Self, FromHexError> {
        let hex = hex.as_ref();
        let len = hex.len();
        if len > NODE_NYBBLES_LENGTH || len == 0 {
            return Err(FromHexError);
        }

        let mut data = [0; NODE_BYTES_LENGTH];
        let mut nybbles_len = 0;
        for &ascii_byte in hex {
            let nybble = match char::from(ascii_byte).to_digit(16) {
                Some(digit) => digit as u8,
                None => return Err(FromHexError),
            };
            // Fill in the upper half of a byte first, then the lower half.
            let shift = if nybbles_len % 2 == 0 { 4 } else { 0 };
            data[nybbles_len as usize / 2] |= nybble << shift;
            nybbles_len += 1;
        }
        Ok(Self { data, nybbles_len })
    }

    pub fn nybbles_len(&self) -> usize {
        self.nybbles_len as _
    }

    pub fn is_prefix_of(&self, node: &Node) -> bool {
        let full_bytes = self.nybbles_len() / 2;
        if self.data[..full_bytes] != node.data[..full_bytes] {
            return false;
        }
        if self.nybbles_len() % 2 == 0 {
            return true;
        }
        let last = self.nybbles_len() - 1;
        self.get_nybble(last) == node.get_nybble(last)
    }

    /// Retrieve the `i`th half-byte from the prefix.
    ///
    /// This is also the `i`th hexadecimal digit in numeric form,
    /// also called a [nybble](https://en.wikipedia.org/wiki/Nibble).
    pub fn get_nybble(&self, i: usize) -> u8 {
        assert!(i < self.nybbles_len());
        get_nybble(&self.data, i)
    }

    fn iter_nybbles(&self) -> impl Iterator<Item = u8> + '_ {
        (0..self.nybbles_len()).map(move |i| get_nybble(&self.data, i))
    }

    /// Return the index first nybble that's different from `node`
    ///
    /// If the return value is `None` that means that `self` is
    /// a prefix of `node`, but the current method is a bit slower
    /// than `is_prefix_of`.
    ///
    /// Returned index is as in `get_nybble`, i.e., starting at 0.
    pub fn first_different_nybble(&self, node: &Node) -> Option<usize> {
        self.iter_nybbles()
            .zip(NodePrefix::from(*node).iter_nybbles())
            .position(|(a, b)| a != b)
    }
}

impl fmt::LowerHex for NodePrefix {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        let full_bytes = self.nybbles_len() / 2;
        for &byte in &self.data[..full_bytes] {
            write!(f, "{:02x}", byte)?
        }
        if self.nybbles_len() % 2 == 1 {
            let last = self.nybbles_len() - 1;
            write!(f, "{:x}", self.get_nybble(last))?
        }
        Ok(())
    }
}

/// A shortcut for full `Node` references
impl From<&'_ Node> for NodePrefix {
    fn from(node: &'_ Node) -> Self {
        NodePrefix {
            nybbles_len: node.nybbles_len() as _,
            data: node.data,
        }
    }
}

/// A shortcut for full `Node` references
impl From<Node> for NodePrefix {
    fn from(node: Node) -> Self {
        NodePrefix {
            nybbles_len: node.nybbles_len() as _,
            data: node.data,
        }
    }
}

impl PartialEq<Node> for NodePrefix {
    fn eq(&self, other: &Node) -> bool {
        Self::from(*other) == *self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_NODE_HEX: &str = "0123456789abcdeffedcba9876543210deadbeef";
    const SAMPLE_NODE: Node = Node {
        data: [
            0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xfe, 0xdc, 0xba,
            0x98, 0x76, 0x54, 0x32, 0x10, 0xde, 0xad, 0xbe, 0xef,
        ],
    };

    /// Pad an hexadecimal string to reach `NODE_NYBBLES_LENGTH`
    /// The padding is made with zeros.
    pub fn hex_pad_right(hex: &str) -> String {
        let mut res = hex.to_string();
        while res.len() < NODE_NYBBLES_LENGTH {
            res.push('0');
        }
        res
    }

    #[test]
    fn test_node_from_hex() {
        let not_hex = "012... oops";
        let too_short = "0123";
        let too_long = format!("{}0", SAMPLE_NODE_HEX);
        assert_eq!(Node::from_hex(SAMPLE_NODE_HEX).unwrap(), SAMPLE_NODE);
        assert!(Node::from_hex(not_hex).is_err());
        assert!(Node::from_hex(too_short).is_err());
        assert!(Node::from_hex(&too_long).is_err());
    }

    #[test]
    fn test_node_encode_hex() {
        assert_eq!(format!("{:x}", SAMPLE_NODE), SAMPLE_NODE_HEX);
    }

    #[test]
    fn test_prefix_from_to_hex() -> Result<(), FromHexError> {
        assert_eq!(format!("{:x}", NodePrefix::from_hex("0e1")?), "0e1");
        assert_eq!(format!("{:x}", NodePrefix::from_hex("0e1a")?), "0e1a");
        assert_eq!(
            format!("{:x}", NodePrefix::from_hex(SAMPLE_NODE_HEX)?),
            SAMPLE_NODE_HEX
        );
        Ok(())
    }

    #[test]
    fn test_prefix_from_hex_errors() {
        assert!(NodePrefix::from_hex("testgr").is_err());
        let mut long = format!("{:x}", NULL_NODE);
        long.push('c');
        assert!(NodePrefix::from_hex(&long).is_err())
    }

    #[test]
    fn test_is_prefix_of() -> Result<(), FromHexError> {
        let mut node_data = [0; NODE_BYTES_LENGTH];
        node_data[0] = 0x12;
        node_data[1] = 0xca;
        let node = Node::from(node_data);
        assert!(NodePrefix::from_hex("12")?.is_prefix_of(&node));
        assert!(!NodePrefix::from_hex("1a")?.is_prefix_of(&node));
        assert!(NodePrefix::from_hex("12c")?.is_prefix_of(&node));
        assert!(!NodePrefix::from_hex("12d")?.is_prefix_of(&node));
        Ok(())
    }

    #[test]
    fn test_get_nybble() -> Result<(), FromHexError> {
        let prefix = NodePrefix::from_hex("dead6789cafe")?;
        assert_eq!(prefix.get_nybble(0), 13);
        assert_eq!(prefix.get_nybble(7), 9);
        Ok(())
    }

    #[test]
    fn test_first_different_nybble_even_prefix() {
        let prefix = NodePrefix::from_hex("12ca").unwrap();
        let mut node = Node::from([0; NODE_BYTES_LENGTH]);
        assert_eq!(prefix.first_different_nybble(&node), Some(0));
        node.data[0] = 0x13;
        assert_eq!(prefix.first_different_nybble(&node), Some(1));
        node.data[0] = 0x12;
        assert_eq!(prefix.first_different_nybble(&node), Some(2));
        node.data[1] = 0xca;
        // now it is a prefix
        assert_eq!(prefix.first_different_nybble(&node), None);
    }

    #[test]
    fn test_first_different_nybble_odd_prefix() {
        let prefix = NodePrefix::from_hex("12c").unwrap();
        let mut node = Node::from([0; NODE_BYTES_LENGTH]);
        assert_eq!(prefix.first_different_nybble(&node), Some(0));
        node.data[0] = 0x13;
        assert_eq!(prefix.first_different_nybble(&node), Some(1));
        node.data[0] = 0x12;
        assert_eq!(prefix.first_different_nybble(&node), Some(2));
        node.data[1] = 0xca;
        // now it is a prefix
        assert_eq!(prefix.first_different_nybble(&node), None);
    }
}

#[cfg(test)]
pub use tests::hex_pad_right;

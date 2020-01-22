// Copyright 2019-2020 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Definitions and utilities for Revision nodes
//!
//! In Mercurial code base, it is customary to call "a node" the binary SHA
//! of a revision.

use hex::{self, FromHex, FromHexError};

/// The length in bytes of a `Node`
///
/// This constant is meant to ease refactors of this module, and
/// are private so that calling code does not expect all nodes have
/// the same size, should we support several formats concurrently in
/// the future.
const NODE_BYTES_LENGTH: usize = 20;

/// The length in bytes of a `Node`
///
/// see also `NODES_BYTES_LENGTH` about it being private.
const NODE_NYBBLES_LENGTH: usize = 2 * NODE_BYTES_LENGTH;

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
/// the size or fail immediately at runtime with [`ExactLengthRequired`].
///
/// [`nybbles_len`]: #method.nybbles_len
/// [`ExactLengthRequired`]: struct.NodeError#variant.ExactLengthRequired
#[derive(Clone, Debug, PartialEq)]
pub struct Node {
    data: NodeData,
}

/// The node value for NULL_REVISION
pub const NULL_NODE: Node = Node {
    data: [0; NODE_BYTES_LENGTH],
};

impl From<NodeData> for Node {
    fn from(data: NodeData) -> Node {
        Node { data }
    }
}

#[derive(Debug, PartialEq)]
pub enum NodeError {
    ExactLengthRequired(usize, String),
    HexError(FromHexError, String),
}

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
    pub fn from_hex(hex: &str) -> Result<Node, NodeError> {
        Ok(NodeData::from_hex(hex)
            .map_err(|e| NodeError::from((e, hex)))?
            .into())
    }

    /// Convert to hexadecimal string representation
    ///
    /// To be used in FFI and I/O only, in order to facilitate future
    /// changes of hash format.
    pub fn encode_hex(&self) -> String {
        hex::encode(self.data)
    }

    /// Provide access to binary data
    ///
    /// This is needed by FFI layers, for instance to return expected
    /// binary values to Python.
    pub fn as_bytes(&self) -> &[u8] {
        &self.data
    }
}

impl From<(FromHexError, &str)> for NodeError {
    fn from(err_offender: (FromHexError, &str)) -> Self {
        let (err, offender) = err_offender;
        match err {
            FromHexError::InvalidStringLength => {
                NodeError::ExactLengthRequired(
                    NODE_NYBBLES_LENGTH,
                    offender.to_string(),
                )
            }
            _ => NodeError::HexError(err, offender.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_node() -> Node {
        let mut data = [0; NODE_BYTES_LENGTH];
        data.copy_from_slice(&[
            0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xfe, 0xdc, 0xba,
            0x98, 0x76, 0x54, 0x32, 0x10, 0xde, 0xad, 0xbe, 0xef,
        ]);
        data.into()
    }

    /// Pad an hexadecimal string to reach `NODE_NYBBLES_LENGTH`
    ///
    /// The padding is made with zeros
    fn hex_pad_right(hex: &str) -> String {
        let mut res = hex.to_string();
        while res.len() < NODE_NYBBLES_LENGTH {
            res.push('0');
        }
        res
    }

    fn sample_node_hex() -> String {
        hex_pad_right("0123456789abcdeffedcba9876543210deadbeef")
    }

    #[test]
    fn test_node_from_hex() {
        assert_eq!(Node::from_hex(&sample_node_hex()), Ok(sample_node()));

        let mut short = hex_pad_right("0123");
        short.pop();
        short.pop();
        assert_eq!(
            Node::from_hex(&short),
            Err(NodeError::ExactLengthRequired(NODE_NYBBLES_LENGTH, short)),
        );

        let not_hex = hex_pad_right("012... oops");
        assert_eq!(
            Node::from_hex(&not_hex),
            Err(NodeError::HexError(
                FromHexError::InvalidHexCharacter { c: '.', index: 3 },
                not_hex,
            )),
        );
    }

    #[test]
    fn test_node_encode_hex() {
        assert_eq!(sample_node().encode_hex(), sample_node_hex());
    }
}

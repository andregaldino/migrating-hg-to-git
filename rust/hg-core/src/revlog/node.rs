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
    PrefixTooLong(String),
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

impl<T: AsRef<str>> From<(FromHexError, T)> for NodeError {
    fn from(err_offender: (FromHexError, T)) -> Self {
        let (err, offender) = err_offender;
        match err {
            FromHexError::InvalidStringLength => {
                NodeError::ExactLengthRequired(
                    NODE_NYBBLES_LENGTH,
                    offender.as_ref().to_owned(),
                )
            }
            _ => NodeError::HexError(err, offender.as_ref().to_owned()),
        }
    }
}

/// The beginning of a binary revision SHA.
///
/// Since it can potentially come from an hexadecimal representation with
/// odd length, it needs to carry around whether the last 4 bits are relevant
/// or not.
#[derive(Debug, PartialEq)]
pub struct NodePrefix {
    buf: Vec<u8>,
    is_odd: bool,
}

impl NodePrefix {
    /// Convert from hexadecimal string representation
    ///
    /// Similarly to `hex::decode`, can be used with Unicode string types
    /// (`String`, `&str`) as well as bytes.
    ///
    /// To be used in FFI and I/O only, in order to facilitate future
    /// changes of hash format.
    pub fn from_hex(hex: impl AsRef<[u8]>) -> Result<Self, NodeError> {
        let hex = hex.as_ref();
        let len = hex.len();
        if len > NODE_NYBBLES_LENGTH {
            return Err(NodeError::PrefixTooLong(
                String::from_utf8_lossy(hex).to_owned().to_string(),
            ));
        }

        let is_odd = len % 2 == 1;
        let even_part = if is_odd { &hex[..len - 1] } else { hex };
        let mut buf: Vec<u8> = Vec::from_hex(&even_part)
            .map_err(|e| (e, String::from_utf8_lossy(hex)))?;

        if is_odd {
            let latest_char = char::from(hex[len - 1]);
            let latest_nybble = latest_char.to_digit(16).ok_or_else(|| {
                (
                    FromHexError::InvalidHexCharacter {
                        c: latest_char,
                        index: len - 1,
                    },
                    String::from_utf8_lossy(hex),
                )
            })? as u8;
            buf.push(latest_nybble << 4);
        }
        Ok(NodePrefix { buf, is_odd })
    }

    pub fn borrow(&self) -> NodePrefixRef {
        NodePrefixRef {
            buf: &self.buf,
            is_odd: self.is_odd,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct NodePrefixRef<'a> {
    buf: &'a [u8],
    is_odd: bool,
}

impl<'a> NodePrefixRef<'a> {
    pub fn len(&self) -> usize {
        if self.is_odd {
            self.buf.len() * 2 - 1
        } else {
            self.buf.len() * 2
        }
    }

    pub fn is_prefix_of(&self, node: &Node) -> bool {
        if self.is_odd {
            let buf = self.buf;
            let last_pos = buf.len() - 1;
            node.data.starts_with(buf.split_at(last_pos).0)
                && node.data[last_pos] >> 4 == buf[last_pos] >> 4
        } else {
            node.data.starts_with(self.buf)
        }
    }

    /// Retrieve the `i`th half-byte from the prefix.
    ///
    /// This is also the `i`th hexadecimal digit in numeric form,
    /// also called a [nybble](https://en.wikipedia.org/wiki/Nibble).
    pub fn get_nybble(&self, i: usize) -> u8 {
        get_nybble(self.buf, i)
    }
}

/// A shortcut for full `Node` references
impl<'a> From<&'a Node> for NodePrefixRef<'a> {
    fn from(node: &'a Node) -> Self {
        NodePrefixRef {
            buf: &node.data,
            is_odd: false,
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
    pub fn hex_pad_right(hex: &str) -> String {
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

    #[test]
    fn test_prefix_from_hex() -> Result<(), NodeError> {
        assert_eq!(
            NodePrefix::from_hex("0e1")?,
            NodePrefix {
                buf: vec![14, 16],
                is_odd: true
            }
        );
        assert_eq!(
            NodePrefix::from_hex("0e1a")?,
            NodePrefix {
                buf: vec![14, 26],
                is_odd: false
            }
        );

        // checking limit case
        let node_as_vec = sample_node().data.iter().cloned().collect();
        assert_eq!(
            NodePrefix::from_hex(sample_node_hex())?,
            NodePrefix {
                buf: node_as_vec,
                is_odd: false
            }
        );

        Ok(())
    }

    #[test]
    fn test_prefix_from_hex_errors() {
        assert_eq!(
            NodePrefix::from_hex("testgr"),
            Err(NodeError::HexError(
                FromHexError::InvalidHexCharacter { c: 't', index: 0 },
                "testgr".to_string()
            ))
        );
        let mut long = NULL_NODE.encode_hex();
        long.push('c');
        match NodePrefix::from_hex(&long)
            .expect_err("should be refused as too long")
        {
            NodeError::PrefixTooLong(s) => assert_eq!(s, long),
            err => panic!(format!("Should have been TooLong, got {:?}", err)),
        }
    }

    #[test]
    fn test_is_prefix_of() -> Result<(), NodeError> {
        let mut node_data = [0; NODE_BYTES_LENGTH];
        node_data[0] = 0x12;
        node_data[1] = 0xca;
        let node = Node::from(node_data);
        assert!(NodePrefix::from_hex("12")?.borrow().is_prefix_of(&node));
        assert!(!NodePrefix::from_hex("1a")?.borrow().is_prefix_of(&node));
        assert!(NodePrefix::from_hex("12c")?.borrow().is_prefix_of(&node));
        assert!(!NodePrefix::from_hex("12d")?.borrow().is_prefix_of(&node));
        Ok(())
    }

    #[test]
    fn test_get_nybble() -> Result<(), NodeError> {
        let prefix = NodePrefix::from_hex("dead6789cafe")?;
        assert_eq!(prefix.borrow().get_nybble(0), 13);
        assert_eq!(prefix.borrow().get_nybble(7), 9);
        Ok(())
    }
}

#[cfg(test)]
pub use tests::hex_pad_right;

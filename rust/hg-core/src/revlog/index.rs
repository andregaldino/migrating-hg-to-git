use std::convert::TryInto;
use std::ops::Deref;

use byteorder::{BigEndian, ByteOrder};

use crate::errors::HgError;
use crate::revlog::node::Node;
use crate::revlog::revlog::RevlogError;
use crate::revlog::{Revision, NULL_REVISION};

pub const INDEX_ENTRY_SIZE: usize = 64;

/// A Revlog index
pub struct Index {
    bytes: Box<dyn Deref<Target = [u8]> + Send>,
    /// Offsets of starts of index blocks.
    /// Only needed when the index is interleaved with data.
    offsets: Option<Vec<usize>>,
}

impl Index {
    /// Create an index from bytes.
    /// Calculate the start of each entry when is_inline is true.
    pub fn new(
        bytes: Box<dyn Deref<Target = [u8]> + Send>,
    ) -> Result<Self, RevlogError> {
        if is_inline(&bytes) {
            let mut offset: usize = 0;
            let mut offsets = Vec::new();

            while offset + INDEX_ENTRY_SIZE <= bytes.len() {
                offsets.push(offset);
                let end = offset + INDEX_ENTRY_SIZE;
                let entry = IndexEntry {
                    bytes: &bytes[offset..end],
                    offset_override: None,
                };

                offset += INDEX_ENTRY_SIZE + entry.compressed_len();
            }

            if offset == bytes.len() {
                Ok(Self {
                    bytes,
                    offsets: Some(offsets),
                })
            } else {
                Err(HgError::corrupted("unexpected inline revlog length")
                    .into())
            }
        } else {
            Ok(Self {
                bytes,
                offsets: None,
            })
        }
    }

    /// Value of the inline flag.
    pub fn is_inline(&self) -> bool {
        is_inline(&self.bytes)
    }

    /// Return a slice of bytes if `revlog` is inline. Panic if not.
    pub fn data(&self, start: usize, end: usize) -> &[u8] {
        if !self.is_inline() {
            panic!("tried to access data in the index of a revlog that is not inline");
        }
        &self.bytes[start..end]
    }

    /// Return number of entries of the revlog index.
    pub fn len(&self) -> usize {
        if let Some(offsets) = &self.offsets {
            offsets.len()
        } else {
            self.bytes.len() / INDEX_ENTRY_SIZE
        }
    }

    /// Returns `true` if the `Index` has zero `entries`.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Return the index entry corresponding to the given revision if it
    /// exists.
    pub fn get_entry(&self, rev: Revision) -> Option<IndexEntry> {
        if rev == NULL_REVISION {
            return None;
        }
        if let Some(offsets) = &self.offsets {
            self.get_entry_inline(rev, offsets)
        } else {
            self.get_entry_separated(rev)
        }
    }

    fn get_entry_inline(
        &self,
        rev: Revision,
        offsets: &[usize],
    ) -> Option<IndexEntry> {
        let start = *offsets.get(rev as usize)?;
        let end = start.checked_add(INDEX_ENTRY_SIZE)?;
        let bytes = &self.bytes[start..end];

        // See IndexEntry for an explanation of this override.
        let offset_override = Some(end);

        Some(IndexEntry {
            bytes,
            offset_override,
        })
    }

    fn get_entry_separated(&self, rev: Revision) -> Option<IndexEntry> {
        let max_rev = self.bytes.len() / INDEX_ENTRY_SIZE;
        if rev as usize >= max_rev {
            return None;
        }
        let start = rev as usize * INDEX_ENTRY_SIZE;
        let end = start + INDEX_ENTRY_SIZE;
        let bytes = &self.bytes[start..end];

        // Override the offset of the first revision as its bytes are used
        // for the index's metadata (saving space because it is always 0)
        let offset_override = if rev == 0 { Some(0) } else { None };

        Some(IndexEntry {
            bytes,
            offset_override,
        })
    }
}

impl super::RevlogIndex for Index {
    fn len(&self) -> usize {
        self.len()
    }

    fn node(&self, rev: Revision) -> Option<&Node> {
        self.get_entry(rev).map(|entry| entry.hash())
    }
}

#[derive(Debug)]
pub struct IndexEntry<'a> {
    bytes: &'a [u8],
    /// Allows to override the offset value of the entry.
    ///
    /// For interleaved index and data, the offset stored in the index
    /// corresponds to the separated data offset.
    /// It has to be overridden with the actual offset in the interleaved
    /// index which is just after the index block.
    ///
    /// For separated index and data, the offset stored in the first index
    /// entry is mixed with the index headers.
    /// It has to be overridden with 0.
    offset_override: Option<usize>,
}

impl<'a> IndexEntry<'a> {
    /// Return the offset of the data.
    pub fn offset(&self) -> usize {
        if let Some(offset_override) = self.offset_override {
            offset_override
        } else {
            let mut bytes = [0; 8];
            bytes[2..8].copy_from_slice(&self.bytes[0..=5]);
            BigEndian::read_u64(&bytes[..]) as usize
        }
    }

    /// Return the compressed length of the data.
    pub fn compressed_len(&self) -> usize {
        BigEndian::read_u32(&self.bytes[8..=11]) as usize
    }

    /// Return the uncompressed length of the data.
    pub fn uncompressed_len(&self) -> usize {
        BigEndian::read_u32(&self.bytes[12..=15]) as usize
    }

    /// Return the revision upon which the data has been derived.
    pub fn base_revision(&self) -> Revision {
        // TODO Maybe return an Option when base_revision == rev?
        //      Requires to add rev to IndexEntry

        BigEndian::read_i32(&self.bytes[16..])
    }

    pub fn p1(&self) -> Revision {
        BigEndian::read_i32(&self.bytes[24..])
    }

    pub fn p2(&self) -> Revision {
        BigEndian::read_i32(&self.bytes[28..])
    }

    /// Return the hash of revision's full text.
    ///
    /// Currently, SHA-1 is used and only the first 20 bytes of this field
    /// are used.
    pub fn hash(&self) -> &'a Node {
        (&self.bytes[32..52]).try_into().unwrap()
    }
}

/// Value of the inline flag.
pub fn is_inline(index_bytes: &[u8]) -> bool {
    match &index_bytes[0..=1] {
        [0, 0] | [0, 2] => false,
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(test)]
    #[derive(Debug, Copy, Clone)]
    pub struct IndexEntryBuilder {
        is_first: bool,
        is_inline: bool,
        is_general_delta: bool,
        version: u16,
        offset: usize,
        compressed_len: usize,
        uncompressed_len: usize,
        base_revision: Revision,
    }

    #[cfg(test)]
    impl IndexEntryBuilder {
        pub fn new() -> Self {
            Self {
                is_first: false,
                is_inline: false,
                is_general_delta: true,
                version: 2,
                offset: 0,
                compressed_len: 0,
                uncompressed_len: 0,
                base_revision: 0,
            }
        }

        pub fn is_first(&mut self, value: bool) -> &mut Self {
            self.is_first = value;
            self
        }

        pub fn with_inline(&mut self, value: bool) -> &mut Self {
            self.is_inline = value;
            self
        }

        pub fn with_general_delta(&mut self, value: bool) -> &mut Self {
            self.is_general_delta = value;
            self
        }

        pub fn with_version(&mut self, value: u16) -> &mut Self {
            self.version = value;
            self
        }

        pub fn with_offset(&mut self, value: usize) -> &mut Self {
            self.offset = value;
            self
        }

        pub fn with_compressed_len(&mut self, value: usize) -> &mut Self {
            self.compressed_len = value;
            self
        }

        pub fn with_uncompressed_len(&mut self, value: usize) -> &mut Self {
            self.uncompressed_len = value;
            self
        }

        pub fn with_base_revision(&mut self, value: Revision) -> &mut Self {
            self.base_revision = value;
            self
        }

        pub fn build(&self) -> Vec<u8> {
            let mut bytes = Vec::with_capacity(INDEX_ENTRY_SIZE);
            if self.is_first {
                bytes.extend(&match (self.is_general_delta, self.is_inline) {
                    (false, false) => [0u8, 0],
                    (false, true) => [0u8, 1],
                    (true, false) => [0u8, 2],
                    (true, true) => [0u8, 3],
                });
                bytes.extend(&self.version.to_be_bytes());
                // Remaining offset bytes.
                bytes.extend(&[0u8; 2]);
            } else {
                // Offset is only 6 bytes will usize is 8.
                bytes.extend(&self.offset.to_be_bytes()[2..]);
            }
            bytes.extend(&[0u8; 2]); // Revision flags.
            bytes.extend(&self.compressed_len.to_be_bytes()[4..]);
            bytes.extend(&self.uncompressed_len.to_be_bytes()[4..]);
            bytes.extend(&self.base_revision.to_be_bytes());
            bytes
        }
    }

    #[test]
    fn is_not_inline_when_no_inline_flag_test() {
        let bytes = IndexEntryBuilder::new()
            .is_first(true)
            .with_general_delta(false)
            .with_inline(false)
            .build();

        assert_eq!(is_inline(&bytes), false)
    }

    #[test]
    fn is_inline_when_inline_flag_test() {
        let bytes = IndexEntryBuilder::new()
            .is_first(true)
            .with_general_delta(false)
            .with_inline(true)
            .build();

        assert_eq!(is_inline(&bytes), true)
    }

    #[test]
    fn is_inline_when_inline_and_generaldelta_flags_test() {
        let bytes = IndexEntryBuilder::new()
            .is_first(true)
            .with_general_delta(true)
            .with_inline(true)
            .build();

        assert_eq!(is_inline(&bytes), true)
    }

    #[test]
    fn test_offset() {
        let bytes = IndexEntryBuilder::new().with_offset(1).build();
        let entry = IndexEntry {
            bytes: &bytes,
            offset_override: None,
        };

        assert_eq!(entry.offset(), 1)
    }

    #[test]
    fn test_with_overridden_offset() {
        let bytes = IndexEntryBuilder::new().with_offset(1).build();
        let entry = IndexEntry {
            bytes: &bytes,
            offset_override: Some(2),
        };

        assert_eq!(entry.offset(), 2)
    }

    #[test]
    fn test_compressed_len() {
        let bytes = IndexEntryBuilder::new().with_compressed_len(1).build();
        let entry = IndexEntry {
            bytes: &bytes,
            offset_override: None,
        };

        assert_eq!(entry.compressed_len(), 1)
    }

    #[test]
    fn test_uncompressed_len() {
        let bytes = IndexEntryBuilder::new().with_uncompressed_len(1).build();
        let entry = IndexEntry {
            bytes: &bytes,
            offset_override: None,
        };

        assert_eq!(entry.uncompressed_len(), 1)
    }

    #[test]
    fn test_base_revision() {
        let bytes = IndexEntryBuilder::new().with_base_revision(1).build();
        let entry = IndexEntry {
            bytes: &bytes,
            offset_override: None,
        };

        assert_eq!(entry.base_revision(), 1)
    }
}

#[cfg(test)]
pub use tests::IndexEntryBuilder;

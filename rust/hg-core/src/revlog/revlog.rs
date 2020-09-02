use std::borrow::Cow;
use std::fs::File;
use std::io::Read;
use std::ops::Deref;
use std::path::Path;

use byteorder::{BigEndian, ByteOrder};
use crypto::digest::Digest;
use crypto::sha1::Sha1;
use flate2::read::ZlibDecoder;
use memmap::{Mmap, MmapOptions};
use micro_timer::timed;
use zstd;

use super::index::Index;
use super::node::{NODE_BYTES_LENGTH, NULL_NODE_ID};
use super::patch;
use crate::revlog::Revision;

pub enum RevlogError {
    IoError(std::io::Error),
    UnsuportedVersion(u16),
    InvalidRevision,
    Corrupted,
    UnknowDataFormat(u8),
}

fn mmap_open(path: &Path) -> Result<Mmap, std::io::Error> {
    let file = File::open(path)?;
    let mmap = unsafe { MmapOptions::new().map(&file) }?;
    Ok(mmap)
}

/// Read only implementation of revlog.
pub struct Revlog {
    /// When index and data are not interleaved: bytes of the revlog index.
    /// When index and data are interleaved: bytes of the revlog index and
    /// data.
    index_bytes: Box<dyn Deref<Target = [u8]> + Send>,
    /// When index and data are not interleaved: bytes of the revlog data
    data_bytes: Option<Box<dyn Deref<Target = [u8]> + Send>>,
}

impl Revlog {
    /// Open a revlog index file.
    ///
    /// It will also open the associated data file if index and data are not
    /// interleaved.
    #[timed]
    pub fn open(index_path: &Path) -> Result<Self, RevlogError> {
        let index_mmap =
            mmap_open(&index_path).map_err(RevlogError::IoError)?;

        let version = get_version(&index_mmap);
        if version != 1 {
            return Err(RevlogError::UnsuportedVersion(version));
        }

        let is_inline = is_inline(&index_mmap);

        let index_bytes = Box::new(index_mmap);

        // TODO load data only when needed //
        // type annotation required
        // won't recognize Mmap as Deref<Target = [u8]>
        let data_bytes: Option<Box<dyn Deref<Target = [u8]> + Send>> =
            if is_inline {
                None
            } else {
                let data_path = index_path.with_extension("d");
                let data_mmap =
                    mmap_open(&data_path).map_err(RevlogError::IoError)?;
                Some(Box::new(data_mmap))
            };

        Ok(Revlog {
            index_bytes,
            data_bytes,
        })
    }

    /// Return the full data associated to a revision.
    ///
    /// All entries required to build the final data out of deltas will be
    /// retrieved as needed, and the deltas will be applied to the inital
    /// snapshot to rebuild the final data.
    #[timed]
    pub fn get_rev_data(&self, rev: Revision) -> Result<Vec<u8>, RevlogError> {
        // Todo return -> Cow
        let mut entry = self.get_entry(rev)?;
        let mut delta_chain = vec![];
        while let Some(base_rev) = entry.base_rev {
            delta_chain.push(entry);
            entry = self
                .get_entry(base_rev)
                .map_err(|_| RevlogError::Corrupted)?;
        }

        // TODO do not look twice in the index
        let index = self.index();
        let index_entry =
            index.get_entry(rev).ok_or(RevlogError::InvalidRevision)?;

        let data: Vec<u8> = if delta_chain.is_empty() {
            entry.data()?.into()
        } else {
            Revlog::build_data_from_deltas(entry, &delta_chain)?
        };

        if self.check_hash(
            index_entry.p1(),
            index_entry.p2(),
            index_entry.hash(),
            &data,
        ) {
            Ok(data)
        } else {
            Err(RevlogError::Corrupted)
        }
    }

    /// Check the hash of some given data against the recorded hash.
    pub fn check_hash(
        &self,
        p1: Revision,
        p2: Revision,
        expected: &[u8],
        data: &[u8],
    ) -> bool {
        let index = self.index();
        let e1 = index.get_entry(p1);
        let h1 = match e1 {
            Some(ref entry) => entry.hash(),
            None => &NULL_NODE_ID,
        };
        let e2 = index.get_entry(p2);
        let h2 = match e2 {
            Some(ref entry) => entry.hash(),
            None => &NULL_NODE_ID,
        };

        hash(data, &h1, &h2).as_slice() == expected
    }

    /// Build the full data of a revision out its snapshot
    /// and its deltas.
    #[timed]
    fn build_data_from_deltas(
        snapshot: RevlogEntry,
        deltas: &[RevlogEntry],
    ) -> Result<Vec<u8>, RevlogError> {
        let snapshot = snapshot.data()?;
        let deltas = deltas
            .iter()
            .rev()
            .map(RevlogEntry::data)
            .collect::<Result<Vec<Cow<'_, [u8]>>, RevlogError>>()?;
        let patches: Vec<_> =
            deltas.iter().map(|d| patch::PatchList::new(d)).collect();
        let patch = patch::fold_patch_lists(&patches);
        Ok(patch.apply(&snapshot))
    }

    /// Return the revlog index.
    fn index(&self) -> Index {
        let is_inline = self.data_bytes.is_none();
        Index::new(&self.index_bytes, is_inline)
    }

    /// Return the revlog data.
    fn data(&self) -> &[u8] {
        match self.data_bytes {
            Some(ref data_bytes) => &data_bytes,
            None => &self.index_bytes,
        }
    }

    /// Get an entry of the revlog.
    fn get_entry(&self, rev: Revision) -> Result<RevlogEntry, RevlogError> {
        let index = self.index();
        let index_entry =
            index.get_entry(rev).ok_or(RevlogError::InvalidRevision)?;
        let start = index_entry.offset();
        let end = start + index_entry.compressed_len();
        let entry = RevlogEntry {
            rev,
            bytes: &self.data()[start..end],
            compressed_len: index_entry.compressed_len(),
            uncompressed_len: index_entry.uncompressed_len(),
            base_rev: if index_entry.base_revision() == rev {
                None
            } else {
                Some(index_entry.base_revision())
            },
        };
        Ok(entry)
    }
}

/// The revlog entry's bytes and the necessary informations to extract
/// the entry's data.
#[derive(Debug)]
pub struct RevlogEntry<'a> {
    rev: Revision,
    bytes: &'a [u8],
    compressed_len: usize,
    uncompressed_len: usize,
    base_rev: Option<Revision>,
}

impl<'a> RevlogEntry<'a> {
    /// Extract the data contained in the entry.
    pub fn data(&self) -> Result<Cow<'_, [u8]>, RevlogError> {
        if self.bytes.is_empty() {
            return Ok(Cow::Borrowed(&[]));
        }
        match self.bytes[0] {
            // Revision data is the entirety of the entry, including this
            // header.
            b'\0' => Ok(Cow::Borrowed(self.bytes)),
            // Raw revision data follows.
            b'u' => Ok(Cow::Borrowed(&self.bytes[1..])),
            // zlib (RFC 1950) data.
            b'x' => Ok(Cow::Owned(self.uncompressed_zlib_data())),
            // zstd data.
            b'\x28' => Ok(Cow::Owned(self.uncompressed_zstd_data())),
            format_type => Err(RevlogError::UnknowDataFormat(format_type)),
        }
    }

    fn uncompressed_zlib_data(&self) -> Vec<u8> {
        let mut decoder = ZlibDecoder::new(self.bytes);
        if self.is_delta() {
            let mut buf = Vec::with_capacity(self.compressed_len);
            decoder.read_to_end(&mut buf).expect("corrupted zlib data");
            buf
        } else {
            let mut buf = vec![0; self.uncompressed_len];
            decoder.read_exact(&mut buf).expect("corrupted zlib data");
            buf
        }
    }

    fn uncompressed_zstd_data(&self) -> Vec<u8> {
        if self.is_delta() {
            let mut buf = Vec::with_capacity(self.compressed_len);
            zstd::stream::copy_decode(self.bytes, &mut buf)
                .expect("corrupted zstd data");
            buf
        } else {
            let mut buf = vec![0; self.uncompressed_len];
            let len = zstd::block::decompress_to_buffer(self.bytes, &mut buf)
                .expect("corrupted zstd data");
            assert_eq!(len, self.uncompressed_len, "corrupted zstd data");
            buf
        }
    }

    /// Tell if the entry is a snapshot or a delta
    /// (influences on decompression).
    fn is_delta(&self) -> bool {
        self.base_rev.is_some()
    }
}

/// Value of the inline flag.
pub fn is_inline(index_bytes: &[u8]) -> bool {
    match &index_bytes[0..=1] {
        [0, 0] | [0, 2] => false,
        _ => true,
    }
}

/// Format version of the revlog.
pub fn get_version(index_bytes: &[u8]) -> u16 {
    BigEndian::read_u16(&index_bytes[2..=3])
}

/// Calculate the hash of a revision given its data and its parents.
fn hash(data: &[u8], p1_hash: &[u8], p2_hash: &[u8]) -> Vec<u8> {
    let mut hasher = Sha1::new();
    let (a, b) = (p1_hash, p2_hash);
    if a > b {
        hasher.input(b);
        hasher.input(a);
    } else {
        hasher.input(a);
        hasher.input(b);
    }
    hasher.input(data);
    let mut hash = vec![0; NODE_BYTES_LENGTH];
    hasher.result(&mut hash);
    hash
}

#[cfg(test)]
mod tests {
    use super::*;

    use super::super::index::IndexEntryBuilder;

    #[cfg(test)]
    pub struct RevlogBuilder {
        version: u16,
        is_general_delta: bool,
        is_inline: bool,
        offset: usize,
        index: Vec<Vec<u8>>,
        data: Vec<Vec<u8>>,
    }

    #[cfg(test)]
    impl RevlogBuilder {
        pub fn new() -> Self {
            Self {
                version: 2,
                is_inline: false,
                is_general_delta: true,
                offset: 0,
                index: vec![],
                data: vec![],
            }
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

        pub fn push(
            &mut self,
            mut index: IndexEntryBuilder,
            data: Vec<u8>,
        ) -> &mut Self {
            if self.index.is_empty() {
                index.is_first(true);
                index.with_general_delta(self.is_general_delta);
                index.with_inline(self.is_inline);
                index.with_version(self.version);
            } else {
                index.with_offset(self.offset);
            }
            self.index.push(index.build());
            self.offset += data.len();
            self.data.push(data);
            self
        }

        pub fn build_inline(&self) -> Vec<u8> {
            let mut bytes =
                Vec::with_capacity(self.index.len() + self.data.len());
            for (index, data) in self.index.iter().zip(self.data.iter()) {
                bytes.extend(index);
                bytes.extend(data);
            }
            bytes
        }
    }

    #[test]
    fn is_not_inline_when_no_inline_flag_test() {
        let bytes = RevlogBuilder::new()
            .with_general_delta(false)
            .with_inline(false)
            .push(IndexEntryBuilder::new(), vec![])
            .build_inline();

        assert_eq!(is_inline(&bytes), false)
    }

    #[test]
    fn is_inline_when_inline_flag_test() {
        let bytes = RevlogBuilder::new()
            .with_general_delta(false)
            .with_inline(true)
            .push(IndexEntryBuilder::new(), vec![])
            .build_inline();

        assert_eq!(is_inline(&bytes), true)
    }

    #[test]
    fn is_inline_when_inline_and_generaldelta_flags_test() {
        let bytes = RevlogBuilder::new()
            .with_general_delta(true)
            .with_inline(true)
            .push(IndexEntryBuilder::new(), vec![])
            .build_inline();

        assert_eq!(is_inline(&bytes), true)
    }

    #[test]
    fn version_test() {
        let bytes = RevlogBuilder::new()
            .with_version(1)
            .push(IndexEntryBuilder::new(), vec![])
            .build_inline();

        assert_eq!(get_version(&bytes), 1)
    }
}

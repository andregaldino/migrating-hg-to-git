// Copyright 2019-2020 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Minimal `RevlogIndex`, readable from standard Mercurial file format
use hg::*;
use memmap2::*;
use std::fs::File;
use std::ops::Deref;
use std::path::Path;
use std::slice;

pub struct Index {
    data: Box<dyn Deref<Target = [IndexEntry]> + Send>,
}

/// A fixed sized index entry. All numbers are big endian
#[repr(C)]
pub struct IndexEntry {
    not_used_yet: [u8; 24],
    p1: Revision,
    p2: Revision,
    node: Node,
    unused_node: [u8; 12],
}

pub const INDEX_ENTRY_SIZE: usize = 64;

impl IndexEntry {
    fn parents(&self) -> [Revision; 2] {
        [Revision::from_be(self.p1), Revision::from_be(self.p1)]
    }
}

impl RevlogIndex for Index {
    fn len(&self) -> usize {
        self.data.len()
    }

    fn node(&self, rev: Revision) -> Option<&Node> {
        if rev == NULL_REVISION {
            return None;
        }
        let i = rev as usize;
        if i >= self.len() {
            None
        } else {
            Some(&self.data[i].node)
        }
    }
}

impl Graph for &Index {
    fn parents(&self, rev: Revision) -> Result<[Revision; 2], GraphError> {
        let [p1, p2] = (*self).data[rev as usize].parents();
        let len = (*self).len();
        if p1 < NULL_REVISION
            || p2 < NULL_REVISION
            || p1 as usize >= len
            || p2 as usize >= len
        {
            return Err(GraphError::ParentOutOfRange(rev));
        }
        Ok([p1, p2])
    }
}

struct IndexMmap(Mmap);

impl Deref for IndexMmap {
    type Target = [IndexEntry];

    fn deref(&self) -> &[IndexEntry] {
        let ptr = self.0.as_ptr() as *const IndexEntry;
        // Any misaligned data will be ignored.
        debug_assert_eq!(
            self.0.len() % std::mem::align_of::<IndexEntry>(),
            0,
            "Misaligned data in mmap"
        );
        unsafe { slice::from_raw_parts(ptr, self.0.len() / INDEX_ENTRY_SIZE) }
    }
}

impl Index {
    pub fn load_mmap(path: impl AsRef<Path>) -> Self {
        let file = File::open(path).unwrap();
        let msg = "Index file is missing, or missing permission";
        let mmap = unsafe { MmapOptions::new().map(&file) }.expect(msg);
        Self {
            data: Box::new(IndexMmap(mmap)),
        }
    }
}

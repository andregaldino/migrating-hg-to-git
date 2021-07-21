// dirstate module
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate_tree::on_disk::DirstateV2ParseError;
use crate::errors::HgError;
use crate::revlog::node::NULL_NODE;
use crate::revlog::Node;
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::FastHashMap;
use bytes_cast::{unaligned, BytesCast};
use std::convert::TryFrom;

pub mod dirs_multiset;
pub mod dirstate_map;
pub mod parsers;
pub mod status;

#[derive(Debug, PartialEq, Clone, BytesCast)]
#[repr(C)]
pub struct DirstateParents {
    pub p1: Node,
    pub p2: Node,
}

impl DirstateParents {
    pub const NULL: Self = Self {
        p1: NULL_NODE,
        p2: NULL_NODE,
    };
}

/// The C implementation uses all signed types. This will be an issue
/// either when 4GB+ source files are commonplace or in 2038, whichever
/// comes first.
#[derive(Debug, PartialEq, Copy, Clone)]
pub struct DirstateEntry {
    pub state: EntryState,
    pub mode: i32,
    pub mtime: i32,
    pub size: i32,
}

impl DirstateEntry {
    pub fn is_non_normal(&self) -> bool {
        self.state != EntryState::Normal || self.mtime == MTIME_UNSET
    }

    pub fn is_from_other_parent(&self) -> bool {
        self.state == EntryState::Normal && self.size == SIZE_FROM_OTHER_PARENT
    }

    // TODO: other platforms
    #[cfg(unix)]
    pub fn mode_changed(
        &self,
        filesystem_metadata: &std::fs::Metadata,
    ) -> bool {
        use std::os::unix::fs::MetadataExt;
        const EXEC_BIT_MASK: u32 = 0o100;
        let dirstate_exec_bit = (self.mode as u32) & EXEC_BIT_MASK;
        let fs_exec_bit = filesystem_metadata.mode() & EXEC_BIT_MASK;
        dirstate_exec_bit != fs_exec_bit
    }

    /// Returns a `(state, mode, size, mtime)` tuple as for
    /// `DirstateMapMethods::debug_iter`.
    pub fn debug_tuple(&self) -> (u8, i32, i32, i32) {
        (self.state.into(), self.mode, self.size, self.mtime)
    }
}

#[derive(BytesCast)]
#[repr(C)]
struct RawEntry {
    state: u8,
    mode: unaligned::I32Be,
    size: unaligned::I32Be,
    mtime: unaligned::I32Be,
    length: unaligned::I32Be,
}

pub const V1_RANGEMASK: i32 = 0x7FFFFFFF;

pub const MTIME_UNSET: i32 = -1;

/// A `DirstateEntry` with a size of `-2` means that it was merged from the
/// other parent. This allows revert to pick the right status back during a
/// merge.
pub const SIZE_FROM_OTHER_PARENT: i32 = -2;
/// A special value used for internal representation of special case in
/// dirstate v1 format.
pub const SIZE_NON_NORMAL: i32 = -1;

pub type StateMap = FastHashMap<HgPathBuf, DirstateEntry>;
pub type StateMapIter<'a> = Box<
    dyn Iterator<
            Item = Result<(&'a HgPath, DirstateEntry), DirstateV2ParseError>,
        > + Send
        + 'a,
>;

pub type CopyMap = FastHashMap<HgPathBuf, HgPathBuf>;
pub type CopyMapIter<'a> = Box<
    dyn Iterator<Item = Result<(&'a HgPath, &'a HgPath), DirstateV2ParseError>>
        + Send
        + 'a,
>;

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum EntryState {
    Normal,
    Added,
    Removed,
    Merged,
    Unknown,
}

impl EntryState {
    pub fn is_tracked(self) -> bool {
        use EntryState::*;
        match self {
            Normal | Added | Merged => true,
            Removed | Unknown => false,
        }
    }
}

impl TryFrom<u8> for EntryState {
    type Error = HgError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            b'n' => Ok(EntryState::Normal),
            b'a' => Ok(EntryState::Added),
            b'r' => Ok(EntryState::Removed),
            b'm' => Ok(EntryState::Merged),
            b'?' => Ok(EntryState::Unknown),
            _ => Err(HgError::CorruptedRepository(format!(
                "Incorrect dirstate entry state {}",
                value
            ))),
        }
    }
}

impl Into<u8> for EntryState {
    fn into(self) -> u8 {
        match self {
            EntryState::Normal => b'n',
            EntryState::Added => b'a',
            EntryState::Removed => b'r',
            EntryState::Merged => b'm',
            EntryState::Unknown => b'?',
        }
    }
}

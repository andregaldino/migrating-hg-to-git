// dirstate module
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::{utils::hg_path::HgPathBuf, DirstateParseError};
use std::collections::hash_map;
use std::collections::HashMap;
use std::convert::TryFrom;

pub mod dirs_multiset;
pub mod dirstate_map;
pub mod parsers;
pub mod status;

#[derive(Debug, PartialEq, Clone)]
pub struct DirstateParents {
    pub p1: [u8; 20],
    pub p2: [u8; 20],
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

pub type StateMap = HashMap<HgPathBuf, DirstateEntry>;
pub type StateMapIter<'a> = hash_map::Iter<'a, HgPathBuf, DirstateEntry>;
pub type CopyMap = HashMap<HgPathBuf, HgPathBuf>;
pub type CopyMapIter<'a> = hash_map::Iter<'a, HgPathBuf, HgPathBuf>;

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum EntryState {
    Normal,
    Added,
    Removed,
    Merged,
    Unknown,
}

impl TryFrom<u8> for EntryState {
    type Error = DirstateParseError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            b'n' => Ok(EntryState::Normal),
            b'a' => Ok(EntryState::Added),
            b'r' => Ok(EntryState::Removed),
            b'm' => Ok(EntryState::Merged),
            b'?' => Ok(EntryState::Unknown),
            _ => Err(DirstateParseError::CorruptedEntry(format!(
                "Incorrect entry state {}",
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

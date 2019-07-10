// dirstate module
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::DirstateParseError;
use std::collections::HashMap;
use std::convert::TryFrom;

pub mod dirs_multiset;
pub mod dirstate_map;
pub mod parsers;

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

pub type StateMap = HashMap<Vec<u8>, DirstateEntry>;
pub type CopyMap = HashMap<Vec<u8>, Vec<u8>>;

/// The Python implementation passes either a mapping (dirstate) or a flat
/// iterable (manifest)
pub enum DirsIterable<'a> {
    Dirstate(&'a HashMap<Vec<u8>, DirstateEntry>),
    Manifest(&'a Vec<Vec<u8>>),
}

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

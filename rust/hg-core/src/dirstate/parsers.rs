// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::errors::HgError;
use crate::utils::hg_path::HgPath;
use crate::{
    dirstate::{CopyMap, EntryState, RawEntry, StateMap},
    DirstateEntry, DirstateParents,
};
use byteorder::{BigEndian, WriteBytesExt};
use bytes_cast::BytesCast;
use micro_timer::timed;
use std::convert::{TryFrom, TryInto};

/// Parents are stored in the dirstate as byte hashes.
pub const PARENT_SIZE: usize = 20;
/// Dirstate entries have a static part of 8 + 32 + 32 + 32 + 32 bits.
const MIN_ENTRY_SIZE: usize = 17;

type ParseResult<'a> = (
    &'a DirstateParents,
    Vec<(&'a HgPath, DirstateEntry)>,
    Vec<(&'a HgPath, &'a HgPath)>,
);

pub fn parse_dirstate_parents(
    contents: &[u8],
) -> Result<&DirstateParents, HgError> {
    let (parents, _rest) = DirstateParents::from_bytes(contents)
        .map_err(|_| HgError::corrupted("Too little data for dirstate."))?;
    Ok(parents)
}

#[timed]
pub fn parse_dirstate(contents: &[u8]) -> Result<ParseResult, HgError> {
    let mut copies = Vec::new();
    let mut entries = Vec::new();
    let parents =
        parse_dirstate_entries(contents, |path, entry, copy_source| {
            if let Some(source) = copy_source {
                copies.push((path, source));
            }
            entries.push((path, *entry));
            Ok(())
        })?;
    Ok((parents, entries, copies))
}

pub fn parse_dirstate_entries<'a>(
    mut contents: &'a [u8],
    mut each_entry: impl FnMut(
        &'a HgPath,
        &DirstateEntry,
        Option<&'a HgPath>,
    ) -> Result<(), HgError>,
) -> Result<&'a DirstateParents, HgError> {
    let (parents, rest) = DirstateParents::from_bytes(contents)
        .map_err(|_| HgError::corrupted("Too little data for dirstate."))?;
    contents = rest;
    while !contents.is_empty() {
        let (raw_entry, rest) = RawEntry::from_bytes(contents)
            .map_err(|_| HgError::corrupted("Overflow in dirstate."))?;

        let entry = DirstateEntry {
            state: EntryState::try_from(raw_entry.state)?,
            mode: raw_entry.mode.get(),
            mtime: raw_entry.mtime.get(),
            size: raw_entry.size.get(),
        };
        let (paths, rest) =
            u8::slice_from_bytes(rest, raw_entry.length.get() as usize)
                .map_err(|_| HgError::corrupted("Overflow in dirstate."))?;

        // `paths` is either a single path, or two paths separated by a NULL
        // byte
        let mut iter = paths.splitn(2, |&byte| byte == b'\0');
        let path = HgPath::new(
            iter.next().expect("splitn always yields at least one item"),
        );
        let copy_source = iter.next().map(HgPath::new);
        each_entry(path, &entry, copy_source)?;

        contents = rest;
    }
    Ok(parents)
}

fn packed_filename_and_copy_source_size(
    filename: &HgPath,
    copy_source: Option<&HgPath>,
) -> usize {
    filename.len()
        + if let Some(source) = copy_source {
            b"\0".len() + source.len()
        } else {
            0
        }
}

pub fn packed_entry_size(
    filename: &HgPath,
    copy_source: Option<&HgPath>,
) -> usize {
    MIN_ENTRY_SIZE
        + packed_filename_and_copy_source_size(filename, copy_source)
}

pub fn pack_entry(
    filename: &HgPath,
    entry: &DirstateEntry,
    copy_source: Option<&HgPath>,
    packed: &mut Vec<u8>,
) {
    let length = packed_filename_and_copy_source_size(filename, copy_source);

    // Unwrapping because `impl std::io::Write for Vec<u8>` never errors
    packed.write_u8(entry.state.into()).unwrap();
    packed.write_i32::<BigEndian>(entry.mode).unwrap();
    packed.write_i32::<BigEndian>(entry.size).unwrap();
    packed.write_i32::<BigEndian>(entry.mtime).unwrap();
    packed.write_i32::<BigEndian>(length as i32).unwrap();
    packed.extend(filename.as_bytes());
    if let Some(source) = copy_source {
        packed.push(b'\0');
        packed.extend(source.as_bytes());
    }
}

/// Seconds since the Unix epoch
pub struct Timestamp(pub i64);

impl DirstateEntry {
    pub fn mtime_is_ambiguous(&self, now: i32) -> bool {
        self.state == EntryState::Normal && self.mtime == now
    }

    pub fn clear_ambiguous_mtime(&mut self, now: i32) -> bool {
        let ambiguous = self.mtime_is_ambiguous(now);
        if ambiguous {
            // The file was last modified "simultaneously" with the current
            // write to dirstate (i.e. within the same second for file-
            // systems with a granularity of 1 sec). This commonly happens
            // for at least a couple of files on 'update'.
            // The user could change the file without changing its size
            // within the same second. Invalidate the file's mtime in
            // dirstate, forcing future 'status' calls to compare the
            // contents of the file if the size is the same. This prevents
            // mistakenly treating such files as clean.
            self.clear_mtime()
        }
        ambiguous
    }

    pub fn clear_mtime(&mut self) {
        self.mtime = -1;
    }
}

pub fn pack_dirstate(
    state_map: &mut StateMap,
    copy_map: &CopyMap,
    parents: DirstateParents,
    now: Timestamp,
) -> Result<Vec<u8>, HgError> {
    // TODO move away from i32 before 2038.
    let now: i32 = now.0.try_into().expect("time overflow");

    let expected_size: usize = state_map
        .iter()
        .map(|(filename, _)| {
            packed_entry_size(filename, copy_map.get(filename).map(|p| &**p))
        })
        .sum();
    let expected_size = expected_size + PARENT_SIZE * 2;

    let mut packed = Vec::with_capacity(expected_size);

    packed.extend(parents.p1.as_bytes());
    packed.extend(parents.p2.as_bytes());

    for (filename, entry) in state_map.iter_mut() {
        entry.clear_ambiguous_mtime(now);
        pack_entry(
            filename,
            entry,
            copy_map.get(filename).map(|p| &**p),
            &mut packed,
        )
    }

    if packed.len() != expected_size {
        return Err(HgError::CorruptedRepository(format!(
            "bad dirstate size: {} != {}",
            expected_size,
            packed.len()
        )));
    }

    Ok(packed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{utils::hg_path::HgPathBuf, FastHashMap};
    use pretty_assertions::assert_eq;

    #[test]
    fn test_pack_dirstate_empty() {
        let mut state_map = StateMap::default();
        let copymap = FastHashMap::default();
        let parents = DirstateParents {
            p1: b"12345678910111213141".into(),
            p2: b"00000000000000000000".into(),
        };
        let now = Timestamp(15000000);
        let expected = b"1234567891011121314100000000000000000000".to_vec();

        assert_eq!(
            expected,
            pack_dirstate(&mut state_map, &copymap, parents, now).unwrap()
        );

        assert!(state_map.is_empty())
    }
    #[test]
    fn test_pack_dirstate_one_entry() {
        let expected_state_map: StateMap = [(
            HgPathBuf::from_bytes(b"f1"),
            DirstateEntry {
                state: EntryState::Normal,
                mode: 0o644,
                size: 0,
                mtime: 791231220,
            },
        )]
        .iter()
        .cloned()
        .collect();
        let mut state_map = expected_state_map.clone();

        let copymap = FastHashMap::default();
        let parents = DirstateParents {
            p1: b"12345678910111213141".into(),
            p2: b"00000000000000000000".into(),
        };
        let now = Timestamp(15000000);
        let expected = [
            49, 50, 51, 52, 53, 54, 55, 56, 57, 49, 48, 49, 49, 49, 50, 49,
            51, 49, 52, 49, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48,
            48, 48, 48, 48, 48, 48, 48, 48, 110, 0, 0, 1, 164, 0, 0, 0, 0, 47,
            41, 58, 244, 0, 0, 0, 2, 102, 49,
        ]
        .to_vec();

        assert_eq!(
            expected,
            pack_dirstate(&mut state_map, &copymap, parents, now).unwrap()
        );

        assert_eq!(expected_state_map, state_map);
    }
    #[test]
    fn test_pack_dirstate_one_entry_with_copy() {
        let expected_state_map: StateMap = [(
            HgPathBuf::from_bytes(b"f1"),
            DirstateEntry {
                state: EntryState::Normal,
                mode: 0o644,
                size: 0,
                mtime: 791231220,
            },
        )]
        .iter()
        .cloned()
        .collect();
        let mut state_map = expected_state_map.clone();
        let mut copymap = FastHashMap::default();
        copymap.insert(
            HgPathBuf::from_bytes(b"f1"),
            HgPathBuf::from_bytes(b"copyname"),
        );
        let parents = DirstateParents {
            p1: b"12345678910111213141".into(),
            p2: b"00000000000000000000".into(),
        };
        let now = Timestamp(15000000);
        let expected = [
            49, 50, 51, 52, 53, 54, 55, 56, 57, 49, 48, 49, 49, 49, 50, 49,
            51, 49, 52, 49, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48,
            48, 48, 48, 48, 48, 48, 48, 48, 110, 0, 0, 1, 164, 0, 0, 0, 0, 47,
            41, 58, 244, 0, 0, 0, 11, 102, 49, 0, 99, 111, 112, 121, 110, 97,
            109, 101,
        ]
        .to_vec();

        assert_eq!(
            expected,
            pack_dirstate(&mut state_map, &copymap, parents, now).unwrap()
        );
        assert_eq!(expected_state_map, state_map);
    }

    #[test]
    fn test_parse_pack_one_entry_with_copy() {
        let mut state_map: StateMap = [(
            HgPathBuf::from_bytes(b"f1"),
            DirstateEntry {
                state: EntryState::Normal,
                mode: 0o644,
                size: 0,
                mtime: 791231220,
            },
        )]
        .iter()
        .cloned()
        .collect();
        let mut copymap = FastHashMap::default();
        copymap.insert(
            HgPathBuf::from_bytes(b"f1"),
            HgPathBuf::from_bytes(b"copyname"),
        );
        let parents = DirstateParents {
            p1: b"12345678910111213141".into(),
            p2: b"00000000000000000000".into(),
        };
        let now = Timestamp(15000000);
        let result =
            pack_dirstate(&mut state_map, &copymap, parents.clone(), now)
                .unwrap();

        let (new_parents, entries, copies) =
            parse_dirstate(result.as_slice()).unwrap();
        let new_state_map: StateMap = entries
            .into_iter()
            .map(|(path, entry)| (path.to_owned(), entry))
            .collect();
        let new_copy_map: CopyMap = copies
            .into_iter()
            .map(|(path, copy)| (path.to_owned(), copy.to_owned()))
            .collect();

        assert_eq!(
            (&parents, state_map, copymap),
            (new_parents, new_state_map, new_copy_map)
        )
    }

    #[test]
    fn test_parse_pack_multiple_entries_with_copy() {
        let mut state_map: StateMap = [
            (
                HgPathBuf::from_bytes(b"f1"),
                DirstateEntry {
                    state: EntryState::Normal,
                    mode: 0o644,
                    size: 0,
                    mtime: 791231220,
                },
            ),
            (
                HgPathBuf::from_bytes(b"f2"),
                DirstateEntry {
                    state: EntryState::Merged,
                    mode: 0o777,
                    size: 1000,
                    mtime: 791231220,
                },
            ),
            (
                HgPathBuf::from_bytes(b"f3"),
                DirstateEntry {
                    state: EntryState::Removed,
                    mode: 0o644,
                    size: 234553,
                    mtime: 791231220,
                },
            ),
            (
                HgPathBuf::from_bytes(b"f4\xF6"),
                DirstateEntry {
                    state: EntryState::Added,
                    mode: 0o644,
                    size: -1,
                    mtime: -1,
                },
            ),
        ]
        .iter()
        .cloned()
        .collect();
        let mut copymap = FastHashMap::default();
        copymap.insert(
            HgPathBuf::from_bytes(b"f1"),
            HgPathBuf::from_bytes(b"copyname"),
        );
        copymap.insert(
            HgPathBuf::from_bytes(b"f4\xF6"),
            HgPathBuf::from_bytes(b"copyname2"),
        );
        let parents = DirstateParents {
            p1: b"12345678910111213141".into(),
            p2: b"00000000000000000000".into(),
        };
        let now = Timestamp(15000000);
        let result =
            pack_dirstate(&mut state_map, &copymap, parents.clone(), now)
                .unwrap();

        let (new_parents, entries, copies) =
            parse_dirstate(result.as_slice()).unwrap();
        let new_state_map: StateMap = entries
            .into_iter()
            .map(|(path, entry)| (path.to_owned(), entry))
            .collect();
        let new_copy_map: CopyMap = copies
            .into_iter()
            .map(|(path, copy)| (path.to_owned(), copy.to_owned()))
            .collect();

        assert_eq!(
            (&parents, state_map, copymap),
            (new_parents, new_state_map, new_copy_map)
        )
    }

    #[test]
    /// https://www.mercurial-scm.org/repo/hg/rev/af3f26b6bba4
    fn test_parse_pack_one_entry_with_copy_and_time_conflict() {
        let mut state_map: StateMap = [(
            HgPathBuf::from_bytes(b"f1"),
            DirstateEntry {
                state: EntryState::Normal,
                mode: 0o644,
                size: 0,
                mtime: 15000000,
            },
        )]
        .iter()
        .cloned()
        .collect();
        let mut copymap = FastHashMap::default();
        copymap.insert(
            HgPathBuf::from_bytes(b"f1"),
            HgPathBuf::from_bytes(b"copyname"),
        );
        let parents = DirstateParents {
            p1: b"12345678910111213141".into(),
            p2: b"00000000000000000000".into(),
        };
        let now = Timestamp(15000000);
        let result =
            pack_dirstate(&mut state_map, &copymap, parents.clone(), now)
                .unwrap();

        let (new_parents, entries, copies) =
            parse_dirstate(result.as_slice()).unwrap();
        let new_state_map: StateMap = entries
            .into_iter()
            .map(|(path, entry)| (path.to_owned(), entry))
            .collect();
        let new_copy_map: CopyMap = copies
            .into_iter()
            .map(|(path, copy)| (path.to_owned(), copy.to_owned()))
            .collect();

        assert_eq!(
            (
                &parents,
                [(
                    HgPathBuf::from_bytes(b"f1"),
                    DirstateEntry {
                        state: EntryState::Normal,
                        mode: 0o644,
                        size: 0,
                        mtime: -1
                    }
                )]
                .iter()
                .cloned()
                .collect::<StateMap>(),
                copymap,
            ),
            (new_parents, new_state_map, new_copy_map)
        )
    }
}

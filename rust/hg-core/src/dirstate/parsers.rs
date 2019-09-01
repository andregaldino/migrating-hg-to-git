// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::utils::hg_path::HgPath;
use crate::{
    dirstate::{CopyMap, EntryState, StateMap},
    DirstateEntry, DirstatePackError, DirstateParents, DirstateParseError,
};
use byteorder::{BigEndian, ReadBytesExt, WriteBytesExt};
use std::convert::{TryFrom, TryInto};
use std::io::Cursor;
use std::time::Duration;

/// Parents are stored in the dirstate as byte hashes.
pub const PARENT_SIZE: usize = 20;
/// Dirstate entries have a static part of 8 + 32 + 32 + 32 + 32 bits.
const MIN_ENTRY_SIZE: usize = 17;

// TODO parse/pack: is mutate-on-loop better for performance?

pub fn parse_dirstate(
    state_map: &mut StateMap,
    copy_map: &mut CopyMap,
    contents: &[u8],
) -> Result<DirstateParents, DirstateParseError> {
    if contents.len() < PARENT_SIZE * 2 {
        return Err(DirstateParseError::TooLittleData);
    }

    let mut curr_pos = PARENT_SIZE * 2;
    let parents = DirstateParents {
        p1: contents[..PARENT_SIZE].try_into().unwrap(),
        p2: contents[PARENT_SIZE..curr_pos].try_into().unwrap(),
    };

    while curr_pos < contents.len() {
        if curr_pos + MIN_ENTRY_SIZE > contents.len() {
            return Err(DirstateParseError::Overflow);
        }
        let entry_bytes = &contents[curr_pos..];

        let mut cursor = Cursor::new(entry_bytes);
        let state = EntryState::try_from(cursor.read_u8()?)?;
        let mode = cursor.read_i32::<BigEndian>()?;
        let size = cursor.read_i32::<BigEndian>()?;
        let mtime = cursor.read_i32::<BigEndian>()?;
        let path_len = cursor.read_i32::<BigEndian>()? as usize;

        if path_len > contents.len() - curr_pos {
            return Err(DirstateParseError::Overflow);
        }

        // Slice instead of allocating a Vec needed for `read_exact`
        let path = &entry_bytes[MIN_ENTRY_SIZE..MIN_ENTRY_SIZE + (path_len)];

        let (path, copy) = match memchr::memchr(0, path) {
            None => (path, None),
            Some(i) => (&path[..i], Some(&path[(i + 1)..])),
        };

        if let Some(copy_path) = copy {
            copy_map.insert(
                HgPath::new(path).to_owned(),
                HgPath::new(copy_path).to_owned(),
            );
        };
        state_map.insert(
            HgPath::new(path).to_owned(),
            DirstateEntry {
                state,
                mode,
                size,
                mtime,
            },
        );
        curr_pos = curr_pos + MIN_ENTRY_SIZE + (path_len);
    }

    Ok(parents)
}

/// `now` is the duration in seconds since the Unix epoch
pub fn pack_dirstate(
    state_map: &mut StateMap,
    copy_map: &CopyMap,
    parents: DirstateParents,
    now: Duration,
) -> Result<Vec<u8>, DirstatePackError> {
    // TODO move away from i32 before 2038.
    let now: i32 = now.as_secs().try_into().expect("time overflow");

    let expected_size: usize = state_map
        .iter()
        .map(|(filename, _)| {
            let mut length = MIN_ENTRY_SIZE + filename.len();
            if let Some(copy) = copy_map.get(filename) {
                length += copy.len() + 1;
            }
            length
        })
        .sum();
    let expected_size = expected_size + PARENT_SIZE * 2;

    let mut packed = Vec::with_capacity(expected_size);
    let mut new_state_map = vec![];

    packed.extend(&parents.p1);
    packed.extend(&parents.p2);

    for (filename, entry) in state_map.iter() {
        let new_filename = filename.to_owned();
        let mut new_mtime: i32 = entry.mtime;
        if entry.state == EntryState::Normal && entry.mtime == now {
            // The file was last modified "simultaneously" with the current
            // write to dirstate (i.e. within the same second for file-
            // systems with a granularity of 1 sec). This commonly happens
            // for at least a couple of files on 'update'.
            // The user could change the file without changing its size
            // within the same second. Invalidate the file's mtime in
            // dirstate, forcing future 'status' calls to compare the
            // contents of the file if the size is the same. This prevents
            // mistakenly treating such files as clean.
            new_mtime = -1;
            new_state_map.push((
                filename.to_owned(),
                DirstateEntry {
                    mtime: new_mtime,
                    ..*entry
                },
            ));
        }
        let mut new_filename = new_filename.into_vec();
        if let Some(copy) = copy_map.get(filename) {
            new_filename.push('\0' as u8);
            new_filename.extend(copy.bytes());
        }

        packed.write_u8(entry.state.into())?;
        packed.write_i32::<BigEndian>(entry.mode)?;
        packed.write_i32::<BigEndian>(entry.size)?;
        packed.write_i32::<BigEndian>(new_mtime)?;
        packed.write_i32::<BigEndian>(new_filename.len() as i32)?;
        packed.extend(new_filename)
    }

    if packed.len() != expected_size {
        return Err(DirstatePackError::BadSize(expected_size, packed.len()));
    }

    state_map.extend(new_state_map);

    Ok(packed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::utils::hg_path::HgPathBuf;
    use std::collections::HashMap;

    #[test]
    fn test_pack_dirstate_empty() {
        let mut state_map: StateMap = HashMap::new();
        let copymap = HashMap::new();
        let parents = DirstateParents {
            p1: *b"12345678910111213141",
            p2: *b"00000000000000000000",
        };
        let now = Duration::new(15000000, 0);
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

        let copymap = HashMap::new();
        let parents = DirstateParents {
            p1: *b"12345678910111213141",
            p2: *b"00000000000000000000",
        };
        let now = Duration::new(15000000, 0);
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
        let mut copymap = HashMap::new();
        copymap.insert(
            HgPathBuf::from_bytes(b"f1"),
            HgPathBuf::from_bytes(b"copyname"),
        );
        let parents = DirstateParents {
            p1: *b"12345678910111213141",
            p2: *b"00000000000000000000",
        };
        let now = Duration::new(15000000, 0);
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
        let mut copymap = HashMap::new();
        copymap.insert(
            HgPathBuf::from_bytes(b"f1"),
            HgPathBuf::from_bytes(b"copyname"),
        );
        let parents = DirstateParents {
            p1: *b"12345678910111213141",
            p2: *b"00000000000000000000",
        };
        let now = Duration::new(15000000, 0);
        let result =
            pack_dirstate(&mut state_map, &copymap, parents.clone(), now)
                .unwrap();

        let mut new_state_map: StateMap = HashMap::new();
        let mut new_copy_map: CopyMap = HashMap::new();
        let new_parents = parse_dirstate(
            &mut new_state_map,
            &mut new_copy_map,
            result.as_slice(),
        )
        .unwrap();
        assert_eq!(
            (parents, state_map, copymap),
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
        let mut copymap = HashMap::new();
        copymap.insert(
            HgPathBuf::from_bytes(b"f1"),
            HgPathBuf::from_bytes(b"copyname"),
        );
        copymap.insert(
            HgPathBuf::from_bytes(b"f4\xF6"),
            HgPathBuf::from_bytes(b"copyname2"),
        );
        let parents = DirstateParents {
            p1: *b"12345678910111213141",
            p2: *b"00000000000000000000",
        };
        let now = Duration::new(15000000, 0);
        let result =
            pack_dirstate(&mut state_map, &copymap, parents.clone(), now)
                .unwrap();

        let mut new_state_map: StateMap = HashMap::new();
        let mut new_copy_map: CopyMap = HashMap::new();
        let new_parents = parse_dirstate(
            &mut new_state_map,
            &mut new_copy_map,
            result.as_slice(),
        )
        .unwrap();
        assert_eq!(
            (parents, state_map, copymap),
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
        let mut copymap = HashMap::new();
        copymap.insert(
            HgPathBuf::from_bytes(b"f1"),
            HgPathBuf::from_bytes(b"copyname"),
        );
        let parents = DirstateParents {
            p1: *b"12345678910111213141",
            p2: *b"00000000000000000000",
        };
        let now = Duration::new(15000000, 0);
        let result =
            pack_dirstate(&mut state_map, &copymap, parents.clone(), now)
                .unwrap();

        let mut new_state_map: StateMap = HashMap::new();
        let mut new_copy_map: CopyMap = HashMap::new();
        let new_parents = parse_dirstate(
            &mut new_state_map,
            &mut new_copy_map,
            result.as_slice(),
        )
        .unwrap();

        assert_eq!(
            (
                parents,
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

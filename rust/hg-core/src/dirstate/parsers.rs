// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::{
    CopyVec, CopyVecEntry, DirstateEntry, DirstatePackError, DirstateParents,
    DirstateParseError, DirstateVec,
};
use byteorder::{BigEndian, ReadBytesExt, WriteBytesExt};
use std::collections::HashMap;
use std::io::Cursor;

/// Parents are stored in the dirstate as byte hashes.
const PARENT_SIZE: usize = 20;
/// Dirstate entries have a static part of 8 + 32 + 32 + 32 + 32 bits.
const MIN_ENTRY_SIZE: usize = 17;

pub fn parse_dirstate(
    contents: &[u8],
) -> Result<(DirstateParents, DirstateVec, CopyVec), DirstateParseError> {
    if contents.len() < PARENT_SIZE * 2 {
        return Err(DirstateParseError::TooLittleData);
    }

    let mut dirstate_vec = vec![];
    let mut copies = vec![];
    let mut curr_pos = PARENT_SIZE * 2;
    let parents = DirstateParents {
        p1: &contents[..PARENT_SIZE],
        p2: &contents[PARENT_SIZE..curr_pos],
    };

    while curr_pos < contents.len() {
        if curr_pos + MIN_ENTRY_SIZE > contents.len() {
            return Err(DirstateParseError::Overflow);
        }
        let entry_bytes = &contents[curr_pos..];

        let mut cursor = Cursor::new(entry_bytes);
        let state = cursor.read_i8()?;
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
            copies.push(CopyVecEntry { path, copy_path });
        };
        dirstate_vec.push((
            path.to_owned(),
            DirstateEntry {
                state,
                mode,
                size,
                mtime,
            },
        ));
        curr_pos = curr_pos + MIN_ENTRY_SIZE + (path_len);
    }

    Ok((parents, dirstate_vec, copies))
}

pub fn pack_dirstate(
    dirstate_vec: &DirstateVec,
    copymap: &HashMap<Vec<u8>, Vec<u8>>,
    parents: DirstateParents,
    now: i32,
) -> Result<(Vec<u8>, DirstateVec), DirstatePackError> {
    if parents.p1.len() != PARENT_SIZE || parents.p2.len() != PARENT_SIZE {
        return Err(DirstatePackError::CorruptedParent);
    }

    let expected_size: usize = dirstate_vec
        .iter()
        .map(|(ref filename, _)| {
            let mut length = MIN_ENTRY_SIZE + filename.len();
            if let Some(ref copy) = copymap.get(filename) {
                length += copy.len() + 1;
            }
            length
        })
        .sum();
    let expected_size = expected_size + PARENT_SIZE * 2;

    let mut packed = Vec::with_capacity(expected_size);
    let mut new_dirstate_vec = vec![];

    packed.extend(parents.p1);
    packed.extend(parents.p2);

    for (ref filename, entry) in dirstate_vec {
        let mut new_filename: Vec<u8> = filename.to_owned();
        let mut new_mtime: i32 = entry.mtime;
        if entry.state == 'n' as i8 && entry.mtime == now.into() {
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
            new_dirstate_vec.push((
                filename.to_owned(),
                DirstateEntry {
                    mtime: new_mtime,
                    ..*entry
                },
            ));
        }

        if let Some(copy) = copymap.get(filename) {
            new_filename.push('\0' as u8);
            new_filename.extend(copy);
        }

        packed.write_i8(entry.state)?;
        packed.write_i32::<BigEndian>(entry.mode)?;
        packed.write_i32::<BigEndian>(entry.size)?;
        packed.write_i32::<BigEndian>(new_mtime)?;
        packed.write_i32::<BigEndian>(new_filename.len() as i32)?;
        packed.extend(new_filename)
    }

    if packed.len() != expected_size {
        return Err(DirstatePackError::BadSize(expected_size, packed.len()));
    }

    Ok((packed, new_dirstate_vec))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pack_dirstate_empty() {
        let dirstate_vec: DirstateVec = vec![];
        let copymap = HashMap::new();
        let parents = DirstateParents {
            p1: b"12345678910111213141",
            p2: b"00000000000000000000",
        };
        let now: i32 = 15000000;
        let expected =
            (b"1234567891011121314100000000000000000000".to_vec(), vec![]);

        assert_eq!(
            expected,
            pack_dirstate(&dirstate_vec, &copymap, parents, now).unwrap()
        );
    }
    #[test]
    fn test_pack_dirstate_one_entry() {
        let dirstate_vec: DirstateVec = vec![(
            vec!['f' as u8, '1' as u8],
            DirstateEntry {
                state: 'n' as i8,
                mode: 0o644,
                size: 0,
                mtime: 791231220,
            },
        )];
        let copymap = HashMap::new();
        let parents = DirstateParents {
            p1: b"12345678910111213141",
            p2: b"00000000000000000000",
        };
        let now: i32 = 15000000;
        let expected = (
            [
                49, 50, 51, 52, 53, 54, 55, 56, 57, 49, 48, 49, 49, 49, 50,
                49, 51, 49, 52, 49, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48,
                48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 110, 0, 0, 1, 164, 0,
                0, 0, 0, 47, 41, 58, 244, 0, 0, 0, 2, 102, 49,
            ]
            .to_vec(),
            vec![],
        );

        assert_eq!(
            expected,
            pack_dirstate(&dirstate_vec, &copymap, parents, now).unwrap()
        );
    }
    #[test]
    fn test_pack_dirstate_one_entry_with_copy() {
        let dirstate_vec: DirstateVec = vec![(
            b"f1".to_vec(),
            DirstateEntry {
                state: 'n' as i8,
                mode: 0o644,
                size: 0,
                mtime: 791231220,
            },
        )];
        let mut copymap = HashMap::new();
        copymap.insert(b"f1".to_vec(), b"copyname".to_vec());
        let parents = DirstateParents {
            p1: b"12345678910111213141",
            p2: b"00000000000000000000",
        };
        let now: i32 = 15000000;
        let expected = (
            [
                49, 50, 51, 52, 53, 54, 55, 56, 57, 49, 48, 49, 49, 49, 50,
                49, 51, 49, 52, 49, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48,
                48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 110, 0, 0, 1, 164, 0,
                0, 0, 0, 47, 41, 58, 244, 0, 0, 0, 11, 102, 49, 0, 99, 111,
                112, 121, 110, 97, 109, 101,
            ]
            .to_vec(),
            vec![],
        );

        assert_eq!(
            expected,
            pack_dirstate(&dirstate_vec, &copymap, parents, now).unwrap()
        );
    }

    #[test]
    fn test_parse_pack_one_entry_with_copy() {
        let dirstate_vec: DirstateVec = vec![(
            b"f1".to_vec(),
            DirstateEntry {
                state: 'n' as i8,
                mode: 0o644,
                size: 0,
                mtime: 791231220,
            },
        )];
        let mut copymap = HashMap::new();
        copymap.insert(b"f1".to_vec(), b"copyname".to_vec());
        let parents = DirstateParents {
            p1: b"12345678910111213141",
            p2: b"00000000000000000000",
        };
        let now: i32 = 15000000;
        let result =
            pack_dirstate(&dirstate_vec, &copymap, parents, now).unwrap();

        assert_eq!(
            (
                parents,
                dirstate_vec,
                copymap
                    .iter()
                    .map(|(k, v)| CopyVecEntry {
                        path: k.as_slice(),
                        copy_path: v.as_slice()
                    })
                    .collect()
            ),
            parse_dirstate(result.0.as_slice()).unwrap()
        )
    }

    #[test]
    fn test_parse_pack_multiple_entries_with_copy() {
        let dirstate_vec: DirstateVec = vec![
            (
                b"f1".to_vec(),
                DirstateEntry {
                    state: 'n' as i8,
                    mode: 0o644,
                    size: 0,
                    mtime: 791231220,
                },
            ),
            (
                b"f2".to_vec(),
                DirstateEntry {
                    state: 'm' as i8,
                    mode: 0o777,
                    size: 1000,
                    mtime: 791231220,
                },
            ),
            (
                b"f3".to_vec(),
                DirstateEntry {
                    state: 'r' as i8,
                    mode: 0o644,
                    size: 234553,
                    mtime: 791231220,
                },
            ),
            (
                b"f4\xF6".to_vec(),
                DirstateEntry {
                    state: 'a' as i8,
                    mode: 0o644,
                    size: -1,
                    mtime: -1,
                },
            ),
        ];
        let mut copymap = HashMap::new();
        copymap.insert(b"f1".to_vec(), b"copyname".to_vec());
        copymap.insert(b"f4\xF6".to_vec(), b"copyname2".to_vec());
        let parents = DirstateParents {
            p1: b"12345678910111213141",
            p2: b"00000000000000000000",
        };
        let now: i32 = 15000000;
        let result =
            pack_dirstate(&dirstate_vec, &copymap, parents, now).unwrap();

        assert_eq!(
            (parents, dirstate_vec, copymap),
            parse_dirstate(result.0.as_slice())
                .and_then(|(p, dvec, cvec)| Ok((
                    p,
                    dvec,
                    cvec.iter()
                        .map(|entry| (
                            entry.path.to_vec(),
                            entry.copy_path.to_vec()
                        ))
                        .collect()
                )))
                .unwrap()
        )
    }

    #[test]
    /// https://www.mercurial-scm.org/repo/hg/rev/af3f26b6bba4
    fn test_parse_pack_one_entry_with_copy_and_time_conflict() {
        let dirstate_vec: DirstateVec = vec![(
            b"f1".to_vec(),
            DirstateEntry {
                state: 'n' as i8,
                mode: 0o644,
                size: 0,
                mtime: 15000000,
            },
        )];
        let mut copymap = HashMap::new();
        copymap.insert(b"f1".to_vec(), b"copyname".to_vec());
        let parents = DirstateParents {
            p1: b"12345678910111213141",
            p2: b"00000000000000000000",
        };
        let now: i32 = 15000000;
        let result =
            pack_dirstate(&dirstate_vec, &copymap, parents, now).unwrap();

        assert_eq!(
            (
                parents,
                vec![(
                    b"f1".to_vec(),
                    DirstateEntry {
                        state: 'n' as i8,
                        mode: 0o644,
                        size: 0,
                        mtime: -1
                    }
                )],
                copymap
                    .iter()
                    .map(|(k, v)| CopyVecEntry {
                        path: k.as_slice(),
                        copy_path: v.as_slice()
                    })
                    .collect()
            ),
            parse_dirstate(result.0.as_slice()).unwrap()
        )
    }
}

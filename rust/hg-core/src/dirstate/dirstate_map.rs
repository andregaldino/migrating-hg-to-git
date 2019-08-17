// dirstate_map.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::{
    dirstate::{parsers::PARENT_SIZE, EntryState},
    pack_dirstate, parse_dirstate,
    utils::copy_into_array,
    CopyMap, DirsIterable, DirsMultiset, DirstateEntry, DirstateError,
    DirstateMapError, DirstateParents, DirstateParseError, StateMap,
};
use core::borrow::Borrow;
use std::collections::{HashMap, HashSet};
use std::iter::FromIterator;
use std::ops::Deref;
use std::time::Duration;

pub type FileFoldMap = HashMap<Vec<u8>, Vec<u8>>;

const NULL_ID: [u8; 20] = [0; 20];
const MTIME_UNSET: i32 = -1;
const SIZE_DIRTY: i32 = -2;

#[derive(Default)]
pub struct DirstateMap {
    state_map: StateMap,
    pub copy_map: CopyMap,
    file_fold_map: Option<FileFoldMap>,
    pub dirs: Option<DirsMultiset>,
    pub all_dirs: Option<DirsMultiset>,
    non_normal_set: HashSet<Vec<u8>>,
    other_parent_set: HashSet<Vec<u8>>,
    parents: Option<DirstateParents>,
    dirty_parents: bool,
}

/// Should only really be used in python interface code, for clarity
impl Deref for DirstateMap {
    type Target = StateMap;

    fn deref(&self) -> &Self::Target {
        &self.state_map
    }
}

impl FromIterator<(Vec<u8>, DirstateEntry)> for DirstateMap {
    fn from_iter<I: IntoIterator<Item = (Vec<u8>, DirstateEntry)>>(
        iter: I,
    ) -> Self {
        Self {
            state_map: iter.into_iter().collect(),
            ..Self::default()
        }
    }
}

impl DirstateMap {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn clear(&mut self) {
        self.state_map.clear();
        self.copy_map.clear();
        self.file_fold_map = None;
        self.non_normal_set.clear();
        self.other_parent_set.clear();
        self.set_parents(DirstateParents {
            p1: NULL_ID,
            p2: NULL_ID,
        })
    }

    /// Add a tracked file to the dirstate
    pub fn add_file(
        &mut self,
        filename: &[u8],
        old_state: EntryState,
        entry: DirstateEntry,
    ) {
        if old_state == EntryState::Unknown || old_state == EntryState::Removed
        {
            if let Some(ref mut dirs) = self.dirs {
                dirs.add_path(filename)
            }
        }
        if old_state == EntryState::Unknown {
            if let Some(ref mut all_dirs) = self.all_dirs {
                all_dirs.add_path(filename)
            }
        }
        self.state_map.insert(filename.to_owned(), entry.to_owned());

        if entry.state != EntryState::Normal || entry.mtime == MTIME_UNSET {
            self.non_normal_set.insert(filename.to_owned());
        }

        if entry.size == SIZE_DIRTY {
            self.other_parent_set.insert(filename.to_owned());
        }
    }

    /// Mark a file as removed in the dirstate.
    ///
    /// The `size` parameter is used to store sentinel values that indicate
    /// the file's previous state.  In the future, we should refactor this
    /// to be more explicit about what that state is.
    pub fn remove_file(
        &mut self,
        filename: &[u8],
        old_state: EntryState,
        size: i32,
    ) -> Result<(), DirstateMapError> {
        if old_state != EntryState::Unknown && old_state != EntryState::Removed
        {
            if let Some(ref mut dirs) = self.dirs {
                dirs.delete_path(filename)?;
            }
        }
        if old_state == EntryState::Unknown {
            if let Some(ref mut all_dirs) = self.all_dirs {
                all_dirs.add_path(filename);
            }
        }

        if let Some(ref mut file_fold_map) = self.file_fold_map {
            file_fold_map.remove(&filename.to_ascii_uppercase());
        }
        self.state_map.insert(
            filename.to_owned(),
            DirstateEntry {
                state: EntryState::Removed,
                mode: 0,
                size,
                mtime: 0,
            },
        );
        self.non_normal_set.insert(filename.to_owned());
        Ok(())
    }

    /// Remove a file from the dirstate.
    /// Returns `true` if the file was previously recorded.
    pub fn drop_file(
        &mut self,
        filename: &[u8],
        old_state: EntryState,
    ) -> Result<bool, DirstateMapError> {
        let exists = self.state_map.remove(filename).is_some();

        if exists {
            if old_state != EntryState::Removed {
                if let Some(ref mut dirs) = self.dirs {
                    dirs.delete_path(filename)?;
                }
            }
            if let Some(ref mut all_dirs) = self.all_dirs {
                all_dirs.delete_path(filename)?;
            }
        }
        if let Some(ref mut file_fold_map) = self.file_fold_map {
            file_fold_map.remove(&filename.to_ascii_uppercase());
        }
        self.non_normal_set.remove(filename);

        Ok(exists)
    }

    pub fn clear_ambiguous_times(
        &mut self,
        filenames: Vec<Vec<u8>>,
        now: i32,
    ) {
        for filename in filenames {
            let mut changed = false;
            self.state_map
                .entry(filename.to_owned())
                .and_modify(|entry| {
                    if entry.state == EntryState::Normal && entry.mtime == now
                    {
                        changed = true;
                        *entry = DirstateEntry {
                            mtime: MTIME_UNSET,
                            ..*entry
                        };
                    }
                });
            if changed {
                self.non_normal_set.insert(filename.to_owned());
            }
        }
    }

    pub fn non_normal_other_parent_entries(
        &self,
    ) -> (HashSet<Vec<u8>>, HashSet<Vec<u8>>) {
        let mut non_normal = HashSet::new();
        let mut other_parent = HashSet::new();

        for (
            filename,
            DirstateEntry {
                state, size, mtime, ..
            },
        ) in self.state_map.iter()
        {
            if *state != EntryState::Normal || *mtime == MTIME_UNSET {
                non_normal.insert(filename.to_owned());
            }
            if *state == EntryState::Normal && *size == SIZE_DIRTY {
                other_parent.insert(filename.to_owned());
            }
        }

        (non_normal, other_parent)
    }

    /// Both of these setters and their uses appear to be the simplest way to
    /// emulate a Python lazy property, but it is ugly and unidiomatic.
    /// TODO One day, rewriting this struct using the typestate might be a
    /// good idea.
    pub fn set_all_dirs(&mut self) {
        if self.all_dirs.is_none() {
            self.all_dirs = Some(DirsMultiset::new(
                DirsIterable::Dirstate(&self.state_map),
                None,
            ));
        }
    }

    pub fn set_dirs(&mut self) {
        if self.dirs.is_none() {
            self.dirs = Some(DirsMultiset::new(
                DirsIterable::Dirstate(&self.state_map),
                Some(EntryState::Removed),
            ));
        }
    }

    pub fn has_tracked_dir(&mut self, directory: &[u8]) -> bool {
        self.set_dirs();
        self.dirs.as_ref().unwrap().contains(directory)
    }

    pub fn has_dir(&mut self, directory: &[u8]) -> bool {
        self.set_all_dirs();
        self.all_dirs.as_ref().unwrap().contains(directory)
    }

    pub fn parents(
        &mut self,
        file_contents: &[u8],
    ) -> Result<DirstateParents, DirstateError> {
        if let Some(ref parents) = self.parents {
            return Ok(parents.clone());
        }
        let parents;
        if file_contents.len() == 40 {
            parents = DirstateParents {
                p1: copy_into_array(&file_contents[..PARENT_SIZE]),
                p2: copy_into_array(
                    &file_contents[PARENT_SIZE..PARENT_SIZE * 2],
                ),
            };
        } else if file_contents.is_empty() {
            parents = DirstateParents {
                p1: NULL_ID,
                p2: NULL_ID,
            };
        } else {
            return Err(DirstateError::Parse(DirstateParseError::Damaged));
        }

        self.parents = Some(parents.to_owned());
        Ok(parents.clone())
    }

    pub fn set_parents(&mut self, parents: DirstateParents) {
        self.parents = Some(parents.clone());
        self.dirty_parents = true;
    }

    pub fn read(
        &mut self,
        file_contents: &[u8],
    ) -> Result<Option<DirstateParents>, DirstateError> {
        if file_contents.is_empty() {
            return Ok(None);
        }

        let parents = parse_dirstate(
            &mut self.state_map,
            &mut self.copy_map,
            file_contents,
        )?;

        if !self.dirty_parents {
            self.set_parents(parents.to_owned());
        }

        Ok(Some(parents))
    }

    pub fn pack(
        &mut self,
        parents: DirstateParents,
        now: Duration,
    ) -> Result<Vec<u8>, DirstateError> {
        let packed =
            pack_dirstate(&mut self.state_map, &self.copy_map, parents, now)?;

        self.dirty_parents = false;

        let result = self.non_normal_other_parent_entries();
        self.non_normal_set = result.0;
        self.other_parent_set = result.1;
        Ok(packed)
    }

    pub fn build_file_fold_map(&mut self) -> FileFoldMap {
        if let Some(ref file_fold_map) = self.file_fold_map {
            return file_fold_map.to_owned();
        }
        let mut new_file_fold_map = FileFoldMap::new();
        for (filename, DirstateEntry { state, .. }) in self.state_map.borrow()
        {
            if *state == EntryState::Removed {
                new_file_fold_map.insert(
                    filename.to_ascii_uppercase().to_owned(),
                    filename.to_owned(),
                );
            }
        }
        self.file_fold_map = Some(new_file_fold_map);
        self.file_fold_map.to_owned().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dirs_multiset() {
        let mut map = DirstateMap::new();
        assert!(map.dirs.is_none());
        assert!(map.all_dirs.is_none());

        assert_eq!(false, map.has_dir(b"nope"));
        assert!(map.all_dirs.is_some());
        assert!(map.dirs.is_none());

        assert_eq!(false, map.has_tracked_dir(b"nope"));
        assert!(map.dirs.is_some());
    }

    #[test]
    fn test_add_file() {
        let mut map = DirstateMap::new();

        assert_eq!(0, map.len());

        map.add_file(
            b"meh",
            EntryState::Normal,
            DirstateEntry {
                state: EntryState::Normal,
                mode: 1337,
                mtime: 1337,
                size: 1337,
            },
        );

        assert_eq!(1, map.len());
        assert_eq!(0, map.non_normal_set.len());
        assert_eq!(0, map.other_parent_set.len());
    }

    #[test]
    fn test_non_normal_other_parent_entries() {
        let map: DirstateMap = [
            (b"f1", (EntryState::Removed, 1337, 1337, 1337)),
            (b"f2", (EntryState::Normal, 1337, 1337, -1)),
            (b"f3", (EntryState::Normal, 1337, 1337, 1337)),
            (b"f4", (EntryState::Normal, 1337, -2, 1337)),
            (b"f5", (EntryState::Added, 1337, 1337, 1337)),
            (b"f6", (EntryState::Added, 1337, 1337, -1)),
            (b"f7", (EntryState::Merged, 1337, 1337, -1)),
            (b"f8", (EntryState::Merged, 1337, 1337, 1337)),
            (b"f9", (EntryState::Merged, 1337, -2, 1337)),
            (b"fa", (EntryState::Added, 1337, -2, 1337)),
            (b"fb", (EntryState::Removed, 1337, -2, 1337)),
        ]
        .iter()
        .map(|(fname, (state, mode, size, mtime))| {
            (
                fname.to_vec(),
                DirstateEntry {
                    state: *state,
                    mode: *mode,
                    size: *size,
                    mtime: *mtime,
                },
            )
        })
        .collect();

        let non_normal = [
            b"f1", b"f2", b"f5", b"f6", b"f7", b"f8", b"f9", b"fa", b"fb",
        ]
        .iter()
        .map(|x| x.to_vec())
        .collect();

        let mut other_parent = HashSet::new();
        other_parent.insert(b"f4".to_vec());

        assert_eq!(
            (non_normal, other_parent),
            map.non_normal_other_parent_entries()
        );
    }
}

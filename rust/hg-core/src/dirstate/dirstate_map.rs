// dirstate_map.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate::parsers::Timestamp;
use crate::{
    dirstate::EntryState,
    dirstate::MTIME_UNSET,
    dirstate::SIZE_FROM_OTHER_PARENT,
    dirstate::SIZE_NON_NORMAL,
    dirstate::V1_RANGEMASK,
    pack_dirstate, parse_dirstate,
    utils::hg_path::{HgPath, HgPathBuf},
    CopyMap, DirsMultiset, DirstateEntry, DirstateError, DirstateParents,
    StateMap,
};
use micro_timer::timed;
use std::collections::HashSet;
use std::iter::FromIterator;
use std::ops::Deref;

#[derive(Default)]
pub struct DirstateMap {
    state_map: StateMap,
    pub copy_map: CopyMap,
    pub dirs: Option<DirsMultiset>,
    pub all_dirs: Option<DirsMultiset>,
    non_normal_set: Option<HashSet<HgPathBuf>>,
    other_parent_set: Option<HashSet<HgPathBuf>>,
}

/// Should only really be used in python interface code, for clarity
impl Deref for DirstateMap {
    type Target = StateMap;

    fn deref(&self) -> &Self::Target {
        &self.state_map
    }
}

impl FromIterator<(HgPathBuf, DirstateEntry)> for DirstateMap {
    fn from_iter<I: IntoIterator<Item = (HgPathBuf, DirstateEntry)>>(
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
        self.state_map = StateMap::default();
        self.copy_map.clear();
        self.non_normal_set = None;
        self.other_parent_set = None;
    }

    pub fn set_v1_inner(&mut self, filename: &HgPath, entry: DirstateEntry) {
        self.state_map.insert(filename.to_owned(), entry);
    }

    /// Add a tracked file to the dirstate
    pub fn add_file(
        &mut self,
        filename: &HgPath,
        entry: DirstateEntry,
        // XXX once the dust settle this should probably become an enum
        added: bool,
        merged: bool,
        from_p2: bool,
        possibly_dirty: bool,
    ) -> Result<(), DirstateError> {
        let mut entry = entry;
        if added {
            assert!(!merged);
            assert!(!possibly_dirty);
            assert!(!from_p2);
            entry.state = EntryState::Added;
            entry.size = SIZE_NON_NORMAL;
            entry.mtime = MTIME_UNSET;
        } else if merged {
            assert!(!possibly_dirty);
            assert!(!from_p2);
            entry.state = EntryState::Merged;
            entry.size = SIZE_FROM_OTHER_PARENT;
            entry.mtime = MTIME_UNSET;
        } else if from_p2 {
            assert!(!possibly_dirty);
            entry.state = EntryState::Normal;
            entry.size = SIZE_FROM_OTHER_PARENT;
            entry.mtime = MTIME_UNSET;
        } else if possibly_dirty {
            entry.state = EntryState::Normal;
            entry.size = SIZE_NON_NORMAL;
            entry.mtime = MTIME_UNSET;
        } else {
            entry.state = EntryState::Normal;
            entry.size = entry.size & V1_RANGEMASK;
            entry.mtime = entry.mtime & V1_RANGEMASK;
        }
        let old_state = match self.get(filename) {
            Some(e) => e.state,
            None => EntryState::Unknown,
        };
        if old_state == EntryState::Unknown || old_state == EntryState::Removed
        {
            if let Some(ref mut dirs) = self.dirs {
                dirs.add_path(filename)?;
            }
        }
        if old_state == EntryState::Unknown {
            if let Some(ref mut all_dirs) = self.all_dirs {
                all_dirs.add_path(filename)?;
            }
        }
        self.state_map.insert(filename.to_owned(), entry.to_owned());

        if entry.is_non_normal() {
            self.get_non_normal_other_parent_entries()
                .0
                .insert(filename.to_owned());
        }

        if entry.is_from_other_parent() {
            self.get_non_normal_other_parent_entries()
                .1
                .insert(filename.to_owned());
        }
        Ok(())
    }

    /// Mark a file as removed in the dirstate.
    ///
    /// The `size` parameter is used to store sentinel values that indicate
    /// the file's previous state.  In the future, we should refactor this
    /// to be more explicit about what that state is.
    pub fn remove_file(
        &mut self,
        filename: &HgPath,
        in_merge: bool,
    ) -> Result<(), DirstateError> {
        let old_entry_opt = self.get(filename);
        let old_state = match old_entry_opt {
            Some(e) => e.state,
            None => EntryState::Unknown,
        };
        let mut size = 0;
        if in_merge {
            // XXX we should not be able to have 'm' state and 'FROM_P2' if not
            // during a merge. So I (marmoute) am not sure we need the
            // conditionnal at all. Adding double checking this with assert
            // would be nice.
            if let Some(old_entry) = old_entry_opt {
                // backup the previous state
                if old_entry.state == EntryState::Merged {
                    size = SIZE_NON_NORMAL;
                } else if old_entry.state == EntryState::Normal
                    && old_entry.size == SIZE_FROM_OTHER_PARENT
                {
                    // other parent
                    size = SIZE_FROM_OTHER_PARENT;
                    self.get_non_normal_other_parent_entries()
                        .1
                        .insert(filename.to_owned());
                }
            }
        }
        if old_state != EntryState::Unknown && old_state != EntryState::Removed
        {
            if let Some(ref mut dirs) = self.dirs {
                dirs.delete_path(filename)?;
            }
        }
        if old_state == EntryState::Unknown {
            if let Some(ref mut all_dirs) = self.all_dirs {
                all_dirs.add_path(filename)?;
            }
        }
        if size == 0 {
            self.copy_map.remove(filename);
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
        self.get_non_normal_other_parent_entries()
            .0
            .insert(filename.to_owned());
        Ok(())
    }

    /// Remove a file from the dirstate.
    /// Returns `true` if the file was previously recorded.
    pub fn drop_file(
        &mut self,
        filename: &HgPath,
    ) -> Result<bool, DirstateError> {
        let old_state = match self.get(filename) {
            Some(e) => e.state,
            None => EntryState::Unknown,
        };
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
        self.get_non_normal_other_parent_entries()
            .0
            .remove(filename);

        Ok(exists)
    }

    pub fn clear_ambiguous_times(
        &mut self,
        filenames: Vec<HgPathBuf>,
        now: i32,
    ) {
        for filename in filenames {
            if let Some(entry) = self.state_map.get_mut(&filename) {
                if entry.clear_ambiguous_mtime(now) {
                    self.get_non_normal_other_parent_entries()
                        .0
                        .insert(filename.to_owned());
                }
            }
        }
    }

    pub fn non_normal_entries_remove(
        &mut self,
        key: impl AsRef<HgPath>,
    ) -> bool {
        self.get_non_normal_other_parent_entries()
            .0
            .remove(key.as_ref())
    }

    pub fn non_normal_entries_add(&mut self, key: impl AsRef<HgPath>) {
        self.get_non_normal_other_parent_entries()
            .0
            .insert(key.as_ref().into());
    }

    pub fn non_normal_entries_union(
        &mut self,
        other: HashSet<HgPathBuf>,
    ) -> Vec<HgPathBuf> {
        self.get_non_normal_other_parent_entries()
            .0
            .union(&other)
            .map(ToOwned::to_owned)
            .collect()
    }

    pub fn get_non_normal_other_parent_entries(
        &mut self,
    ) -> (&mut HashSet<HgPathBuf>, &mut HashSet<HgPathBuf>) {
        self.set_non_normal_other_parent_entries(false);
        (
            self.non_normal_set.as_mut().unwrap(),
            self.other_parent_set.as_mut().unwrap(),
        )
    }

    /// Useful to get immutable references to those sets in contexts where
    /// you only have an immutable reference to the `DirstateMap`, like when
    /// sharing references with Python.
    ///
    /// TODO, get rid of this along with the other "setter/getter" stuff when
    /// a nice typestate plan is defined.
    ///
    /// # Panics
    ///
    /// Will panic if either set is `None`.
    pub fn get_non_normal_other_parent_entries_panic(
        &self,
    ) -> (&HashSet<HgPathBuf>, &HashSet<HgPathBuf>) {
        (
            self.non_normal_set.as_ref().unwrap(),
            self.other_parent_set.as_ref().unwrap(),
        )
    }

    pub fn set_non_normal_other_parent_entries(&mut self, force: bool) {
        if !force
            && self.non_normal_set.is_some()
            && self.other_parent_set.is_some()
        {
            return;
        }
        let mut non_normal = HashSet::new();
        let mut other_parent = HashSet::new();

        for (filename, entry) in self.state_map.iter() {
            if entry.is_non_normal() {
                non_normal.insert(filename.to_owned());
            }
            if entry.is_from_other_parent() {
                other_parent.insert(filename.to_owned());
            }
        }
        self.non_normal_set = Some(non_normal);
        self.other_parent_set = Some(other_parent);
    }

    /// Both of these setters and their uses appear to be the simplest way to
    /// emulate a Python lazy property, but it is ugly and unidiomatic.
    /// TODO One day, rewriting this struct using the typestate might be a
    /// good idea.
    pub fn set_all_dirs(&mut self) -> Result<(), DirstateError> {
        if self.all_dirs.is_none() {
            self.all_dirs = Some(DirsMultiset::from_dirstate(
                self.state_map.iter().map(|(k, v)| Ok((k, *v))),
                None,
            )?);
        }
        Ok(())
    }

    pub fn set_dirs(&mut self) -> Result<(), DirstateError> {
        if self.dirs.is_none() {
            self.dirs = Some(DirsMultiset::from_dirstate(
                self.state_map.iter().map(|(k, v)| Ok((k, *v))),
                Some(EntryState::Removed),
            )?);
        }
        Ok(())
    }

    pub fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateError> {
        self.set_dirs()?;
        Ok(self.dirs.as_ref().unwrap().contains(directory))
    }

    pub fn has_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateError> {
        self.set_all_dirs()?;
        Ok(self.all_dirs.as_ref().unwrap().contains(directory))
    }

    #[timed]
    pub fn read(
        &mut self,
        file_contents: &[u8],
    ) -> Result<Option<DirstateParents>, DirstateError> {
        if file_contents.is_empty() {
            return Ok(None);
        }

        let (parents, entries, copies) = parse_dirstate(file_contents)?;
        self.state_map.extend(
            entries
                .into_iter()
                .map(|(path, entry)| (path.to_owned(), entry)),
        );
        self.copy_map.extend(
            copies
                .into_iter()
                .map(|(path, copy)| (path.to_owned(), copy.to_owned())),
        );
        Ok(Some(parents.clone()))
    }

    pub fn pack(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError> {
        let packed =
            pack_dirstate(&mut self.state_map, &self.copy_map, parents, now)?;

        self.set_non_normal_other_parent_entries(true);
        Ok(packed)
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

        assert_eq!(map.has_dir(HgPath::new(b"nope")).unwrap(), false);
        assert!(map.all_dirs.is_some());
        assert!(map.dirs.is_none());

        assert_eq!(map.has_tracked_dir(HgPath::new(b"nope")).unwrap(), false);
        assert!(map.dirs.is_some());
    }

    #[test]
    fn test_add_file() {
        let mut map = DirstateMap::new();

        assert_eq!(0, map.len());

        map.add_file(
            HgPath::new(b"meh"),
            DirstateEntry {
                state: EntryState::Normal,
                mode: 1337,
                mtime: 1337,
                size: 1337,
            },
            false,
            false,
            false,
            false,
        )
        .unwrap();

        assert_eq!(1, map.len());
        assert_eq!(0, map.get_non_normal_other_parent_entries().0.len());
        assert_eq!(0, map.get_non_normal_other_parent_entries().1.len());
    }

    #[test]
    fn test_non_normal_other_parent_entries() {
        let mut map: DirstateMap = [
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
                HgPathBuf::from_bytes(fname.as_ref()),
                DirstateEntry {
                    state: *state,
                    mode: *mode,
                    size: *size,
                    mtime: *mtime,
                },
            )
        })
        .collect();

        let mut non_normal = [
            b"f1", b"f2", b"f5", b"f6", b"f7", b"f8", b"f9", b"fa", b"fb",
        ]
        .iter()
        .map(|x| HgPathBuf::from_bytes(x.as_ref()))
        .collect();

        let mut other_parent = HashSet::new();
        other_parent.insert(HgPathBuf::from_bytes(b"f4"));
        let entries = map.get_non_normal_other_parent_entries();

        assert_eq!(
            (&mut non_normal, &mut other_parent),
            (entries.0, entries.1)
        );
    }
}

// dirstate_map.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate::parsers::Timestamp;
use crate::errors::HgError;
use crate::{
    dirstate::EntryState,
    dirstate::SIZE_FROM_OTHER_PARENT,
    dirstate::SIZE_NON_NORMAL,
    pack_dirstate, parse_dirstate,
    utils::hg_path::{HgPath, HgPathBuf},
    CopyMap, DirsMultiset, DirstateEntry, DirstateError, DirstateParents,
    StateMap,
};
use micro_timer::timed;
use std::iter::FromIterator;
use std::ops::Deref;

#[derive(Default)]
pub struct DirstateMap {
    state_map: StateMap,
    pub copy_map: CopyMap,
    pub dirs: Option<DirsMultiset>,
    pub all_dirs: Option<DirsMultiset>,
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
    }

    pub fn set_entry(&mut self, filename: &HgPath, entry: DirstateEntry) {
        self.state_map.insert(filename.to_owned(), entry);
    }

    /// Add a tracked file to the dirstate
    pub fn add_file(
        &mut self,
        filename: &HgPath,
        entry: DirstateEntry,
    ) -> Result<(), DirstateError> {
        let old_state = self.get(filename).map(|e| e.state());
        if old_state.is_none() || old_state == Some(EntryState::Removed) {
            if let Some(ref mut dirs) = self.dirs {
                dirs.add_path(filename)?;
            }
        }
        if old_state.is_none() {
            if let Some(ref mut all_dirs) = self.all_dirs {
                all_dirs.add_path(filename)?;
            }
        }
        self.state_map.insert(filename.to_owned(), entry.to_owned());
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
        let old_state = old_entry_opt.map(|e| e.state());
        let mut size = 0;
        if in_merge {
            // XXX we should not be able to have 'm' state and 'FROM_P2' if not
            // during a merge. So I (marmoute) am not sure we need the
            // conditionnal at all. Adding double checking this with assert
            // would be nice.
            if let Some(old_entry) = old_entry_opt {
                // backup the previous state
                if old_entry.state() == EntryState::Merged {
                    size = SIZE_NON_NORMAL;
                } else if old_entry.state() == EntryState::Normal
                    && old_entry.size() == SIZE_FROM_OTHER_PARENT
                {
                    // other parent
                    size = SIZE_FROM_OTHER_PARENT;
                }
            }
        }
        if old_state.is_some() && old_state != Some(EntryState::Removed) {
            if let Some(ref mut dirs) = self.dirs {
                dirs.delete_path(filename)?;
            }
        }
        if old_state.is_none() {
            if let Some(ref mut all_dirs) = self.all_dirs {
                all_dirs.add_path(filename)?;
            }
        }
        if size == 0 {
            self.copy_map.remove(filename);
        }

        self.state_map
            .insert(filename.to_owned(), DirstateEntry::new_removed(size));
        Ok(())
    }

    /// Remove a file from the dirstate.
    /// Returns `true` if the file was previously recorded.
    pub fn drop_entry_and_copy_source(
        &mut self,
        filename: &HgPath,
    ) -> Result<(), DirstateError> {
        let old_state = self.get(filename).map(|e| e.state());
        let exists = self.state_map.remove(filename).is_some();

        if exists {
            if old_state != Some(EntryState::Removed) {
                if let Some(ref mut dirs) = self.dirs {
                    dirs.delete_path(filename)?;
                }
            }
            if let Some(ref mut all_dirs) = self.all_dirs {
                all_dirs.delete_path(filename)?;
            }
        }
        self.copy_map.remove(filename);

        Ok(())
    }

    /// Both of these setters and their uses appear to be the simplest way to
    /// emulate a Python lazy property, but it is ugly and unidiomatic.
    /// TODO One day, rewriting this struct using the typestate might be a
    /// good idea.
    pub fn set_all_dirs(&mut self) -> Result<(), DirstateError> {
        if self.all_dirs.is_none() {
            self.all_dirs = Some(DirsMultiset::from_dirstate(
                self.state_map.iter().map(|(k, v)| Ok((k, *v))),
                false,
            )?);
        }
        Ok(())
    }

    pub fn set_dirs(&mut self) -> Result<(), DirstateError> {
        if self.dirs.is_none() {
            self.dirs = Some(DirsMultiset::from_dirstate(
                self.state_map.iter().map(|(k, v)| Ok((k, *v))),
                true,
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
    ) -> Result<Vec<u8>, HgError> {
        pack_dirstate(&mut self.state_map, &self.copy_map, parents, now)
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
            DirstateEntry::from_v1_data(EntryState::Normal, 1337, 1337, 1337),
        )
        .unwrap();

        assert_eq!(1, map.len());
    }
}

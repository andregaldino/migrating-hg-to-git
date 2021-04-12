use std::path::PathBuf;

use crate::dirstate::parsers::Timestamp;
use crate::matchers::Matcher;
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::CopyMapIter;
use crate::DirstateEntry;
use crate::DirstateError;
use crate::DirstateMap;
use crate::DirstateMapError;
use crate::DirstateParents;
use crate::DirstateStatus;
use crate::EntryState;
use crate::FastHashMap;
use crate::HgPathCow;
use crate::PatternFileWarning;
use crate::StateMapIter;
use crate::StatusError;
use crate::StatusOptions;

pub trait DirstateMapMethods {
    fn clear(&mut self);

    fn add_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        entry: DirstateEntry,
    ) -> Result<(), DirstateMapError>;

    fn remove_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        size: i32,
    ) -> Result<(), DirstateMapError>;

    fn drop_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
    ) -> Result<bool, DirstateMapError>;

    fn clear_ambiguous_times(&mut self, filenames: Vec<HgPathBuf>, now: i32);

    fn non_normal_entries_contains(&mut self, key: &HgPath) -> bool;

    fn non_normal_entries_remove(&mut self, key: &HgPath) -> bool;

    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + '_>;

    fn set_non_normal_other_parent_entries(&mut self, force: bool);

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_>;

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_>;

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_>;

    fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateMapError>;

    fn has_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateMapError>;

    fn parents(
        &mut self,
        file_contents: &[u8],
    ) -> Result<&DirstateParents, DirstateError>;

    fn set_parents(&mut self, parents: &DirstateParents);

    fn read<'a>(
        &mut self,
        file_contents: &'a [u8],
    ) -> Result<Option<&'a DirstateParents>, DirstateError>;

    fn pack(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError>;

    fn build_file_fold_map(&mut self) -> &FastHashMap<HgPathBuf, HgPathBuf>;

    fn set_all_dirs(&mut self) -> Result<(), DirstateMapError>;

    fn set_dirs(&mut self) -> Result<(), DirstateMapError>;

    fn status<'a>(
        &'a self,
        matcher: &'a (dyn Matcher + Sync),
        root_dir: PathBuf,
        ignore_files: Vec<PathBuf>,
        options: StatusOptions,
    ) -> Result<
        (
            (Vec<HgPathCow<'a>>, DirstateStatus<'a>),
            Vec<PatternFileWarning>,
        ),
        StatusError,
    >;

    fn copy_map_len(&self) -> usize;

    fn copy_map_iter(&self) -> CopyMapIter<'_>;

    fn copy_map_contains_key(&self, key: &HgPath) -> bool;

    fn copy_map_get(&self, key: &HgPath) -> Option<&HgPathBuf>;

    fn copy_map_remove(&mut self, key: &HgPath) -> Option<HgPathBuf>;

    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Option<HgPathBuf>;

    fn len(&self) -> usize;

    fn contains_key(&self, key: &HgPath) -> bool;

    fn get(&self, key: &HgPath) -> Option<&DirstateEntry>;

    fn iter(&self) -> StateMapIter<'_>;
}

impl DirstateMapMethods for DirstateMap {
    fn clear(&mut self) {
        self.clear()
    }

    fn add_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        entry: DirstateEntry,
    ) -> Result<(), DirstateMapError> {
        self.add_file(filename, old_state, entry)
    }

    fn remove_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        size: i32,
    ) -> Result<(), DirstateMapError> {
        self.remove_file(filename, old_state, size)
    }

    fn drop_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
    ) -> Result<bool, DirstateMapError> {
        self.drop_file(filename, old_state)
    }

    fn clear_ambiguous_times(&mut self, filenames: Vec<HgPathBuf>, now: i32) {
        self.clear_ambiguous_times(filenames, now)
    }

    fn non_normal_entries_contains(&mut self, key: &HgPath) -> bool {
        let (non_normal, _other_parent) =
            self.get_non_normal_other_parent_entries();
        non_normal.contains(key)
    }

    fn non_normal_entries_remove(&mut self, key: &HgPath) -> bool {
        self.non_normal_entries_remove(key)
    }

    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + '_> {
        let (non_normal, other_parent) =
            self.get_non_normal_other_parent_entries();
        Box::new(non_normal.union(other_parent))
    }

    fn set_non_normal_other_parent_entries(&mut self, force: bool) {
        self.set_non_normal_other_parent_entries(force)
    }

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        let (non_normal, _other_parent) =
            self.get_non_normal_other_parent_entries();
        Box::new(non_normal.iter())
    }

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        let (non_normal, _other_parent) =
            self.get_non_normal_other_parent_entries_panic();
        Box::new(non_normal.iter())
    }

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        let (_non_normal, other_parent) =
            self.get_non_normal_other_parent_entries();
        Box::new(other_parent.iter())
    }

    fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateMapError> {
        self.has_tracked_dir(directory)
    }

    fn has_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateMapError> {
        self.has_dir(directory)
    }

    fn parents(
        &mut self,
        file_contents: &[u8],
    ) -> Result<&DirstateParents, DirstateError> {
        self.parents(file_contents)
    }

    fn set_parents(&mut self, parents: &DirstateParents) {
        self.set_parents(parents)
    }

    fn read<'a>(
        &mut self,
        file_contents: &'a [u8],
    ) -> Result<Option<&'a DirstateParents>, DirstateError> {
        self.read(file_contents)
    }

    fn pack(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError> {
        self.pack(parents, now)
    }

    fn build_file_fold_map(&mut self) -> &FastHashMap<HgPathBuf, HgPathBuf> {
        self.build_file_fold_map()
    }

    fn set_all_dirs(&mut self) -> Result<(), DirstateMapError> {
        self.set_all_dirs()
    }

    fn set_dirs(&mut self) -> Result<(), DirstateMapError> {
        self.set_dirs()
    }

    fn status<'a>(
        &'a self,
        matcher: &'a (dyn Matcher + Sync),
        root_dir: PathBuf,
        ignore_files: Vec<PathBuf>,
        options: StatusOptions,
    ) -> Result<
        (
            (Vec<HgPathCow<'a>>, DirstateStatus<'a>),
            Vec<PatternFileWarning>,
        ),
        StatusError,
    > {
        crate::status(self, matcher, root_dir, ignore_files, options)
    }

    fn copy_map_len(&self) -> usize {
        self.copy_map.len()
    }

    fn copy_map_iter(&self) -> CopyMapIter<'_> {
        Box::new(self.copy_map.iter())
    }

    fn copy_map_contains_key(&self, key: &HgPath) -> bool {
        self.copy_map.contains_key(key)
    }

    fn copy_map_get(&self, key: &HgPath) -> Option<&HgPathBuf> {
        self.copy_map.get(key)
    }

    fn copy_map_remove(&mut self, key: &HgPath) -> Option<HgPathBuf> {
        self.copy_map.remove(key)
    }

    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Option<HgPathBuf> {
        self.copy_map.insert(key, value)
    }

    fn len(&self) -> usize {
        (&**self).len()
    }

    fn contains_key(&self, key: &HgPath) -> bool {
        (&**self).contains_key(key)
    }

    fn get(&self, key: &HgPath) -> Option<&DirstateEntry> {
        (&**self).get(key)
    }

    fn iter(&self) -> StateMapIter<'_> {
        Box::new((&**self).iter())
    }
}

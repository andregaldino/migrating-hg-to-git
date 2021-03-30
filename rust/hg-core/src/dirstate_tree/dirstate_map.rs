use std::path::PathBuf;
use std::time::Duration;

use crate::matchers::Matcher;
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::CopyMapIter;
use crate::DirstateEntry;
use crate::DirstateError;
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

pub struct DirstateMap {
    // TODO
}

impl DirstateMap {
    pub fn new() -> Self {
        todo!()
    }
}

impl super::dispatch::DirstateMapMethods for DirstateMap {
    fn clear(&mut self) {
        todo!()
    }

    fn add_file(
        &mut self,
        _filename: &HgPath,
        _old_state: EntryState,
        _entry: DirstateEntry,
    ) -> Result<(), DirstateMapError> {
        todo!()
    }

    fn remove_file(
        &mut self,
        _filename: &HgPath,
        _old_state: EntryState,
        _size: i32,
    ) -> Result<(), DirstateMapError> {
        todo!()
    }

    fn drop_file(
        &mut self,
        _filename: &HgPath,
        _old_state: EntryState,
    ) -> Result<bool, DirstateMapError> {
        todo!()
    }

    fn clear_ambiguous_times(
        &mut self,
        _filenames: Vec<HgPathBuf>,
        _now: i32,
    ) {
        todo!()
    }

    fn non_normal_entries_contains(&mut self, _key: &HgPath) -> bool {
        todo!()
    }

    fn non_normal_entries_remove(&mut self, _key: &HgPath) -> bool {
        todo!()
    }

    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + '_> {
        todo!()
    }

    fn set_non_normal_other_parent_entries(&mut self, _force: bool) {
        todo!()
    }

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        todo!()
    }

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        todo!()
    }

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        todo!()
    }

    fn has_tracked_dir(
        &mut self,
        _directory: &HgPath,
    ) -> Result<bool, DirstateMapError> {
        todo!()
    }

    fn has_dir(
        &mut self,
        _directory: &HgPath,
    ) -> Result<bool, DirstateMapError> {
        todo!()
    }

    fn parents(
        &mut self,
        _file_contents: &[u8],
    ) -> Result<&DirstateParents, DirstateError> {
        todo!()
    }

    fn set_parents(&mut self, _parents: &DirstateParents) {
        todo!()
    }

    fn read<'a>(
        &mut self,
        _file_contents: &'a [u8],
    ) -> Result<Option<&'a DirstateParents>, DirstateError> {
        todo!()
    }

    fn pack(
        &mut self,
        _parents: DirstateParents,
        _now: Duration,
    ) -> Result<Vec<u8>, DirstateError> {
        todo!()
    }

    fn build_file_fold_map(&mut self) -> &FastHashMap<HgPathBuf, HgPathBuf> {
        todo!()
    }

    fn set_all_dirs(&mut self) -> Result<(), DirstateMapError> {
        todo!()
    }

    fn set_dirs(&mut self) -> Result<(), DirstateMapError> {
        todo!()
    }

    fn status<'a>(
        &'a self,
        _matcher: &'a (dyn Matcher + Sync),
        _root_dir: PathBuf,
        _ignore_files: Vec<PathBuf>,
        _options: StatusOptions,
    ) -> Result<
        (
            (Vec<HgPathCow<'a>>, DirstateStatus<'a>),
            Vec<PatternFileWarning>,
        ),
        StatusError,
    > {
        todo!()
    }

    fn copy_map_len(&self) -> usize {
        todo!()
    }

    fn copy_map_iter(&self) -> CopyMapIter<'_> {
        todo!()
    }

    fn copy_map_contains_key(&self, _key: &HgPath) -> bool {
        todo!()
    }

    fn copy_map_get(&self, _key: &HgPath) -> Option<&HgPathBuf> {
        todo!()
    }

    fn copy_map_remove(&mut self, _key: &HgPath) -> Option<HgPathBuf> {
        todo!()
    }

    fn copy_map_insert(
        &mut self,
        _key: HgPathBuf,
        _value: HgPathBuf,
    ) -> Option<HgPathBuf> {
        todo!()
    }

    fn len(&self) -> usize {
        todo!()
    }

    fn contains_key(&self, _key: &HgPath) -> bool {
        todo!()
    }

    fn get(&self, _key: &HgPath) -> Option<&DirstateEntry> {
        todo!()
    }

    fn iter(&self) -> StateMapIter<'_> {
        todo!()
    }
}

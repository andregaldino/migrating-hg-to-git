use crate::dirstate::owning::OwningDirstateMap;
use hg::dirstate::parsers::Timestamp;
use hg::dirstate_tree::dispatch::DirstateMapMethods;
use hg::matchers::Matcher;
use hg::utils::hg_path::{HgPath, HgPathBuf};
use hg::CopyMapIter;
use hg::DirstateEntry;
use hg::DirstateError;
use hg::DirstateMapError;
use hg::DirstateParents;
use hg::DirstateStatus;
use hg::EntryState;
use hg::PatternFileWarning;
use hg::StateMapIter;
use hg::StatusError;
use hg::StatusOptions;
use std::path::PathBuf;

impl DirstateMapMethods for OwningDirstateMap {
    fn clear(&mut self) {
        self.get_mut().clear()
    }

    fn add_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        entry: DirstateEntry,
    ) -> Result<(), DirstateMapError> {
        self.get_mut().add_file(filename, old_state, entry)
    }

    fn remove_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        size: i32,
    ) -> Result<(), DirstateMapError> {
        self.get_mut().remove_file(filename, old_state, size)
    }

    fn drop_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
    ) -> Result<bool, DirstateMapError> {
        self.get_mut().drop_file(filename, old_state)
    }

    fn clear_ambiguous_times(&mut self, filenames: Vec<HgPathBuf>, now: i32) {
        self.get_mut().clear_ambiguous_times(filenames, now)
    }

    fn non_normal_entries_contains(&mut self, key: &HgPath) -> bool {
        self.get_mut().non_normal_entries_contains(key)
    }

    fn non_normal_entries_remove(&mut self, key: &HgPath) {
        self.get_mut().non_normal_entries_remove(key)
    }

    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + '_> {
        self.get_mut().non_normal_or_other_parent_paths()
    }

    fn set_non_normal_other_parent_entries(&mut self, force: bool) {
        self.get_mut().set_non_normal_other_parent_entries(force)
    }

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        self.get_mut().iter_non_normal_paths()
    }

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        self.get().iter_non_normal_paths_panic()
    }

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = &HgPathBuf> + Send + '_> {
        self.get_mut().iter_other_parent_paths()
    }

    fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateMapError> {
        self.get_mut().has_tracked_dir(directory)
    }

    fn has_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateMapError> {
        self.get_mut().has_dir(directory)
    }

    fn pack(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError> {
        self.get_mut().pack(parents, now)
    }

    fn set_all_dirs(&mut self) -> Result<(), DirstateMapError> {
        self.get_mut().set_all_dirs()
    }

    fn set_dirs(&mut self) -> Result<(), DirstateMapError> {
        self.get_mut().set_dirs()
    }

    fn status<'a>(
        &'a mut self,
        matcher: &'a (dyn Matcher + Sync),
        root_dir: PathBuf,
        ignore_files: Vec<PathBuf>,
        options: StatusOptions,
    ) -> Result<(DirstateStatus<'a>, Vec<PatternFileWarning>), StatusError>
    {
        self.get_mut()
            .status(matcher, root_dir, ignore_files, options)
    }

    fn copy_map_len(&self) -> usize {
        self.get().copy_map_len()
    }

    fn copy_map_iter(&self) -> CopyMapIter<'_> {
        self.get().copy_map_iter()
    }

    fn copy_map_contains_key(&self, key: &HgPath) -> bool {
        self.get().copy_map_contains_key(key)
    }

    fn copy_map_get(&self, key: &HgPath) -> Option<&HgPathBuf> {
        self.get().copy_map_get(key)
    }

    fn copy_map_remove(&mut self, key: &HgPath) -> Option<HgPathBuf> {
        self.get_mut().copy_map_remove(key)
    }

    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Option<HgPathBuf> {
        self.get_mut().copy_map_insert(key, value)
    }

    fn len(&self) -> usize {
        self.get().len()
    }

    fn contains_key(&self, key: &HgPath) -> bool {
        self.get().contains_key(key)
    }

    fn get(&self, key: &HgPath) -> Option<&DirstateEntry> {
        self.get().get(key)
    }

    fn iter(&self) -> StateMapIter<'_> {
        self.get().iter()
    }
}

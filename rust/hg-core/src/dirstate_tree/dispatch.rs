use std::path::PathBuf;

use crate::dirstate::parsers::Timestamp;
use crate::dirstate_tree::on_disk::DirstateV2ParseError;
use crate::matchers::Matcher;
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::CopyMapIter;
use crate::DirstateEntry;
use crate::DirstateError;
use crate::DirstateMap;
use crate::DirstateParents;
use crate::DirstateStatus;
use crate::EntryState;
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
    ) -> Result<(), DirstateError>;

    fn remove_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        size: i32,
    ) -> Result<(), DirstateError>;

    fn drop_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
    ) -> Result<bool, DirstateError>;

    fn clear_ambiguous_times(
        &mut self,
        filenames: Vec<HgPathBuf>,
        now: i32,
    ) -> Result<(), DirstateV2ParseError>;

    fn non_normal_entries_contains(
        &mut self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError>;

    fn non_normal_entries_remove(&mut self, key: &HgPath);

    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + '_>;

    fn set_non_normal_other_parent_entries(&mut self, force: bool);

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    >;

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    >;

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    >;

    fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateError>;

    fn has_dir(&mut self, directory: &HgPath) -> Result<bool, DirstateError>;

    fn pack_v1(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError>;

    fn pack_v2(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError>;

    fn set_all_dirs(&mut self) -> Result<(), DirstateError>;

    fn set_dirs(&mut self) -> Result<(), DirstateError>;

    fn status<'a>(
        &'a mut self,
        matcher: &'a (dyn Matcher + Sync),
        root_dir: PathBuf,
        ignore_files: Vec<PathBuf>,
        options: StatusOptions,
    ) -> Result<(DirstateStatus<'a>, Vec<PatternFileWarning>), StatusError>;

    fn copy_map_len(&self) -> usize;

    fn copy_map_iter(&self) -> CopyMapIter<'_>;

    fn copy_map_contains_key(
        &self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError>;

    fn copy_map_get(
        &self,
        key: &HgPath,
    ) -> Result<Option<&HgPath>, DirstateV2ParseError>;

    fn copy_map_remove(
        &mut self,
        key: &HgPath,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError>;

    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError>;

    fn len(&self) -> usize;

    fn contains_key(&self, key: &HgPath)
        -> Result<bool, DirstateV2ParseError>;

    fn get(
        &self,
        key: &HgPath,
    ) -> Result<Option<DirstateEntry>, DirstateV2ParseError>;

    fn iter(&self) -> StateMapIter<'_>;

    fn iter_directories(
        &self,
    ) -> Box<
        dyn Iterator<
                Item = Result<
                    (&HgPath, Option<Timestamp>),
                    DirstateV2ParseError,
                >,
            > + Send
            + '_,
    >;
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
    ) -> Result<(), DirstateError> {
        self.add_file(filename, old_state, entry)
    }

    fn remove_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
        size: i32,
    ) -> Result<(), DirstateError> {
        self.remove_file(filename, old_state, size)
    }

    fn drop_file(
        &mut self,
        filename: &HgPath,
        old_state: EntryState,
    ) -> Result<bool, DirstateError> {
        self.drop_file(filename, old_state)
    }

    fn clear_ambiguous_times(
        &mut self,
        filenames: Vec<HgPathBuf>,
        now: i32,
    ) -> Result<(), DirstateV2ParseError> {
        Ok(self.clear_ambiguous_times(filenames, now))
    }

    fn non_normal_entries_contains(
        &mut self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError> {
        let (non_normal, _other_parent) =
            self.get_non_normal_other_parent_entries();
        Ok(non_normal.contains(key))
    }

    fn non_normal_entries_remove(&mut self, key: &HgPath) {
        self.non_normal_entries_remove(key)
    }

    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + '_>
    {
        let (non_normal, other_parent) =
            self.get_non_normal_other_parent_entries();
        Box::new(non_normal.union(other_parent).map(|p| Ok(&**p)))
    }

    fn set_non_normal_other_parent_entries(&mut self, force: bool) {
        self.set_non_normal_other_parent_entries(force)
    }

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    > {
        let (non_normal, _other_parent) =
            self.get_non_normal_other_parent_entries();
        Box::new(non_normal.iter().map(|p| Ok(&**p)))
    }

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    > {
        let (non_normal, _other_parent) =
            self.get_non_normal_other_parent_entries_panic();
        Box::new(non_normal.iter().map(|p| Ok(&**p)))
    }

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    > {
        let (_non_normal, other_parent) =
            self.get_non_normal_other_parent_entries();
        Box::new(other_parent.iter().map(|p| Ok(&**p)))
    }

    fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateError> {
        self.has_tracked_dir(directory)
    }

    fn has_dir(&mut self, directory: &HgPath) -> Result<bool, DirstateError> {
        self.has_dir(directory)
    }

    fn pack_v1(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError> {
        self.pack(parents, now)
    }

    fn pack_v2(
        &mut self,
        _parents: DirstateParents,
        _now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError> {
        panic!(
            "should have used dirstate_tree::DirstateMap to use the v2 format"
        )
    }

    fn set_all_dirs(&mut self) -> Result<(), DirstateError> {
        self.set_all_dirs()
    }

    fn set_dirs(&mut self) -> Result<(), DirstateError> {
        self.set_dirs()
    }

    fn status<'a>(
        &'a mut self,
        matcher: &'a (dyn Matcher + Sync),
        root_dir: PathBuf,
        ignore_files: Vec<PathBuf>,
        options: StatusOptions,
    ) -> Result<(DirstateStatus<'a>, Vec<PatternFileWarning>), StatusError>
    {
        crate::status(self, matcher, root_dir, ignore_files, options)
    }

    fn copy_map_len(&self) -> usize {
        self.copy_map.len()
    }

    fn copy_map_iter(&self) -> CopyMapIter<'_> {
        Box::new(
            self.copy_map
                .iter()
                .map(|(key, value)| Ok((&**key, &**value))),
        )
    }

    fn copy_map_contains_key(
        &self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError> {
        Ok(self.copy_map.contains_key(key))
    }

    fn copy_map_get(
        &self,
        key: &HgPath,
    ) -> Result<Option<&HgPath>, DirstateV2ParseError> {
        Ok(self.copy_map.get(key).map(|p| &**p))
    }

    fn copy_map_remove(
        &mut self,
        key: &HgPath,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError> {
        Ok(self.copy_map.remove(key))
    }

    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError> {
        Ok(self.copy_map.insert(key, value))
    }

    fn len(&self) -> usize {
        (&**self).len()
    }

    fn contains_key(
        &self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError> {
        Ok((&**self).contains_key(key))
    }

    fn get(
        &self,
        key: &HgPath,
    ) -> Result<Option<DirstateEntry>, DirstateV2ParseError> {
        Ok((&**self).get(key).cloned())
    }

    fn iter(&self) -> StateMapIter<'_> {
        Box::new((&**self).iter().map(|(key, value)| Ok((&**key, *value))))
    }

    fn iter_directories(
        &self,
    ) -> Box<
        dyn Iterator<
                Item = Result<
                    (&HgPath, Option<Timestamp>),
                    DirstateV2ParseError,
                >,
            > + Send
            + '_,
    > {
        Box::new(std::iter::empty())
    }
}

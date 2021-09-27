use crate::dirstate::parsers::Timestamp;
use crate::dirstate::CopyMapIter;
use crate::dirstate::StateMapIter;
use crate::dirstate_tree::dispatch::DirstateMapMethods;
use crate::dirstate_tree::on_disk::DirstateV2ParseError;
use crate::dirstate_tree::owning::OwningDirstateMap;
use crate::matchers::Matcher;
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::DirstateEntry;
use crate::DirstateError;
use crate::DirstateParents;
use crate::DirstateStatus;
use crate::PatternFileWarning;
use crate::StatusError;
use crate::StatusOptions;
use std::path::PathBuf;

impl DirstateMapMethods for OwningDirstateMap {
    fn clear(&mut self) {
        self.get_mut().clear()
    }

    fn set_entry(
        &mut self,
        filename: &HgPath,
        entry: DirstateEntry,
    ) -> Result<(), DirstateV2ParseError> {
        self.get_mut().set_entry(filename, entry)
    }

    fn add_file(
        &mut self,
        filename: &HgPath,
        entry: DirstateEntry,
    ) -> Result<(), DirstateError> {
        self.get_mut().add_file(filename, entry)
    }

    fn remove_file(
        &mut self,
        filename: &HgPath,
        in_merge: bool,
    ) -> Result<(), DirstateError> {
        self.get_mut().remove_file(filename, in_merge)
    }

    fn drop_entry_and_copy_source(
        &mut self,
        filename: &HgPath,
    ) -> Result<(), DirstateError> {
        self.get_mut().drop_entry_and_copy_source(filename)
    }

    fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateError> {
        self.get_mut().has_tracked_dir(directory)
    }

    fn has_dir(&mut self, directory: &HgPath) -> Result<bool, DirstateError> {
        self.get_mut().has_dir(directory)
    }

    fn pack_v1(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError> {
        self.get_mut().pack_v1(parents, now)
    }

    fn pack_v2(
        &mut self,
        now: Timestamp,
        can_append: bool,
    ) -> Result<(Vec<u8>, Vec<u8>, bool), DirstateError> {
        self.get_mut().pack_v2(now, can_append)
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

    fn copy_map_contains_key(
        &self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError> {
        self.get().copy_map_contains_key(key)
    }

    fn copy_map_get(
        &self,
        key: &HgPath,
    ) -> Result<Option<&HgPath>, DirstateV2ParseError> {
        self.get().copy_map_get(key)
    }

    fn copy_map_remove(
        &mut self,
        key: &HgPath,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError> {
        self.get_mut().copy_map_remove(key)
    }

    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError> {
        self.get_mut().copy_map_insert(key, value)
    }

    fn len(&self) -> usize {
        self.get().len()
    }

    fn contains_key(
        &self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError> {
        self.get().contains_key(key)
    }

    fn get(
        &self,
        key: &HgPath,
    ) -> Result<Option<DirstateEntry>, DirstateV2ParseError> {
        self.get().get(key)
    }

    fn iter(&self) -> StateMapIter<'_> {
        self.get().iter()
    }

    fn iter_tracked_dirs(
        &mut self,
    ) -> Result<
        Box<
            dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>>
                + Send
                + '_,
        >,
        DirstateError,
    > {
        self.get_mut().iter_tracked_dirs()
    }

    fn debug_iter(
        &self,
        all: bool,
    ) -> Box<
        dyn Iterator<
                Item = Result<
                    (&HgPath, (u8, i32, i32, i32)),
                    DirstateV2ParseError,
                >,
            > + Send
            + '_,
    > {
        self.get().debug_iter(all)
    }
}

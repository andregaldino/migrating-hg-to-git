use crate::dirstate::owning::OwningDirstateMap;
use hg::dirstate::parsers::Timestamp;
use hg::dirstate_tree::dispatch::DirstateMapMethods;
use hg::dirstate_tree::on_disk::DirstateV2ParseError;
use hg::matchers::Matcher;
use hg::utils::hg_path::{HgPath, HgPathBuf};
use hg::CopyMapIter;
use hg::DirstateEntry;
use hg::DirstateError;
use hg::DirstateParents;
use hg::DirstateStatus;
use hg::PatternFileWarning;
use hg::StateMapIter;
use hg::StatusError;
use hg::StatusOptions;
use std::path::PathBuf;

impl DirstateMapMethods for OwningDirstateMap {
    fn clear(&mut self) {
        self.get_mut().clear()
    }

    fn set_v1(&mut self, filename: &HgPath, entry: DirstateEntry) {
        self.get_mut().set_v1(filename, entry)
    }

    fn add_file(
        &mut self,
        filename: &HgPath,
        entry: DirstateEntry,
        added: bool,
        merged: bool,
        from_p2: bool,
        possibly_dirty: bool,
    ) -> Result<(), DirstateError> {
        self.get_mut().add_file(
            filename,
            entry,
            added,
            merged,
            from_p2,
            possibly_dirty,
        )
    }

    fn remove_file(
        &mut self,
        filename: &HgPath,
        in_merge: bool,
    ) -> Result<(), DirstateError> {
        self.get_mut().remove_file(filename, in_merge)
    }

    fn drop_file(&mut self, filename: &HgPath) -> Result<bool, DirstateError> {
        self.get_mut().drop_file(filename)
    }

    fn clear_ambiguous_times(
        &mut self,
        filenames: Vec<HgPathBuf>,
        now: i32,
    ) -> Result<(), DirstateV2ParseError> {
        self.get_mut().clear_ambiguous_times(filenames, now)
    }

    fn non_normal_entries_contains(
        &mut self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError> {
        self.get_mut().non_normal_entries_contains(key)
    }

    fn non_normal_entries_remove(&mut self, key: &HgPath) -> bool {
        self.get_mut().non_normal_entries_remove(key)
    }

    fn non_normal_entries_add(&mut self, key: &HgPath) {
        self.get_mut().non_normal_entries_add(key)
    }

    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + '_>
    {
        self.get_mut().non_normal_or_other_parent_paths()
    }

    fn set_non_normal_other_parent_entries(&mut self, force: bool) {
        self.get_mut().set_non_normal_other_parent_entries(force)
    }

    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    > {
        self.get_mut().iter_non_normal_paths()
    }

    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    > {
        self.get().iter_non_normal_paths_panic()
    }

    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    > {
        self.get_mut().iter_other_parent_paths()
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
    ) -> Box<
        dyn Iterator<
                Item = Result<
                    (&HgPath, (u8, i32, i32, i32)),
                    DirstateV2ParseError,
                >,
            > + Send
            + '_,
    > {
        self.get().debug_iter()
    }
}

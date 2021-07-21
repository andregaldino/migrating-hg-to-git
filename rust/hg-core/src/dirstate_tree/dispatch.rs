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
use crate::PatternFileWarning;
use crate::StateMapIter;
use crate::StatusError;
use crate::StatusOptions;

/// `rust/hg-cpython/src/dirstate/dirstate_map.rs` implements in Rust a
/// `DirstateMap` Python class that wraps `Box<dyn DirstateMapMethods + Send>`,
/// a trait object of this trait. Except for constructors, this trait defines
/// all APIs that the class needs to interact with its inner dirstate map.
///
/// A trait object is used to support two different concrete types:
///
/// * `rust/hg-core/src/dirstate/dirstate_map.rs` defines the "flat dirstate
///   map" which is based on a few large `HgPath`-keyed `HashMap` and `HashSet`
///   fields.
/// * `rust/hg-core/src/dirstate_tree/dirstate_map.rs` defines the "tree
///   dirstate map" based on a tree data struture with nodes for directories
///   containing child nodes for their files and sub-directories. This tree
///   enables a more efficient algorithm for `hg status`, but its details are
///   abstracted in this trait.
///
/// The dirstate map associates paths of files in the working directory to
/// various information about the state of those files.
pub trait DirstateMapMethods {
    /// Remove information about all files in this map
    fn clear(&mut self);

    fn set_v1(&mut self, filename: &HgPath, entry: DirstateEntry);

    /// Add or change the information associated to a given file.
    ///
    /// `old_state` is the state in the entry that `get` would have returned
    /// before this call, or `EntryState::Unknown` if there was no such entry.
    ///
    /// `entry.state` should never be `EntryState::Unknown`.
    fn add_file(
        &mut self,
        filename: &HgPath,
        entry: DirstateEntry,
        added: bool,
        merged: bool,
        from_p2: bool,
        possibly_dirty: bool,
    ) -> Result<(), DirstateError>;

    /// Mark a file as "removed" (as in `hg rm`).
    ///
    /// `old_state` is the state in the entry that `get` would have returned
    /// before this call, or `EntryState::Unknown` if there was no such entry.
    ///
    /// `size` is not actually a size but the 0 or -1 or -2 value that would be
    /// put in the size field in the dirstate-v1 format.
    fn remove_file(
        &mut self,
        filename: &HgPath,
        in_merge: bool,
    ) -> Result<(), DirstateError>;

    /// Drop information about this file from the map if any, and return
    /// whether there was any.
    ///
    /// `get` will now return `None` for this filename.
    ///
    /// `old_state` is the state in the entry that `get` would have returned
    /// before this call, or `EntryState::Unknown` if there was no such entry.
    fn drop_file(&mut self, filename: &HgPath) -> Result<bool, DirstateError>;

    /// Among given files, mark the stored `mtime` as ambiguous if there is one
    /// (if `state == EntryState::Normal`) equal to the given current Unix
    /// timestamp.
    fn clear_ambiguous_times(
        &mut self,
        filenames: Vec<HgPathBuf>,
        now: i32,
    ) -> Result<(), DirstateV2ParseError>;

    /// Return whether the map has an "non-normal" entry for the given
    /// filename. That is, any entry with a `state` other than
    /// `EntryState::Normal` or with an ambiguous `mtime`.
    fn non_normal_entries_contains(
        &mut self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError>;

    /// Mark the given path as "normal" file. This is only relevant in the flat
    /// dirstate map where there is a separate `HashSet` that needs to be kept
    /// up to date.
    /// Returns whether the key was present in the set.
    fn non_normal_entries_remove(&mut self, key: &HgPath) -> bool;

    /// Mark the given path as "non-normal" file.
    /// This is only relevant in the flat dirstate map where there is a
    /// separate `HashSet` that needs to be kept up to date.
    fn non_normal_entries_add(&mut self, key: &HgPath);

    /// Return an iterator of paths whose respective entry are either
    /// "non-normal" (see `non_normal_entries_contains`) or "from other
    /// parent".
    ///
    /// If that information is cached, create the cache as needed.
    ///
    /// "From other parent" is defined as `state == Normal && size == -2`.
    ///
    /// Because parse errors can happen during iteration, the iterated items
    /// are `Result`s.
    fn non_normal_or_other_parent_paths(
        &mut self,
    ) -> Box<dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + '_>;

    /// Create the cache for `non_normal_or_other_parent_paths` if needed.
    ///
    /// If `force` is true, the cache is re-created even if it already exists.
    fn set_non_normal_other_parent_entries(&mut self, force: bool);

    /// Return an iterator of paths whose respective entry are "non-normal"
    /// (see `non_normal_entries_contains`).
    ///
    /// If that information is cached, create the cache as needed.
    ///
    /// Because parse errors can happen during iteration, the iterated items
    /// are `Result`s.
    fn iter_non_normal_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    >;

    /// Same as `iter_non_normal_paths`, but takes `&self` instead of `&mut
    /// self`.
    ///
    /// Panics if a cache is necessary but does not exist yet.
    fn iter_non_normal_paths_panic(
        &self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    >;

    /// Return an iterator of paths whose respective entry are "from other
    /// parent".
    ///
    /// If that information is cached, create the cache as needed.
    ///
    /// "From other parent" is defined as `state == Normal && size == -2`.
    ///
    /// Because parse errors can happen during iteration, the iterated items
    /// are `Result`s.
    fn iter_other_parent_paths(
        &mut self,
    ) -> Box<
        dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>> + Send + '_,
    >;

    /// Returns whether the sub-tree rooted at the given directory contains any
    /// tracked file.
    ///
    /// A file is tracked if it has a `state` other than `EntryState::Removed`.
    fn has_tracked_dir(
        &mut self,
        directory: &HgPath,
    ) -> Result<bool, DirstateError>;

    /// Returns whether the sub-tree rooted at the given directory contains any
    /// file with a dirstate entry.
    fn has_dir(&mut self, directory: &HgPath) -> Result<bool, DirstateError>;

    /// Clear mtimes that are ambigous with `now` (similar to
    /// `clear_ambiguous_times` but for all files in the dirstate map), and
    /// serialize bytes to write the `.hg/dirstate` file to disk in dirstate-v1
    /// format.
    fn pack_v1(
        &mut self,
        parents: DirstateParents,
        now: Timestamp,
    ) -> Result<Vec<u8>, DirstateError>;

    /// Clear mtimes that are ambigous with `now` (similar to
    /// `clear_ambiguous_times` but for all files in the dirstate map), and
    /// serialize bytes to write a dirstate data file to disk in dirstate-v2
    /// format.
    ///
    /// Returns new data and metadata together with whether that data should be
    /// appended to the existing data file whose content is at
    /// `self.on_disk` (true), instead of written to a new data file
    /// (false).
    ///
    /// Note: this is only supported by the tree dirstate map.
    fn pack_v2(
        &mut self,
        now: Timestamp,
        can_append: bool,
    ) -> Result<(Vec<u8>, Vec<u8>, bool), DirstateError>;

    /// Run the status algorithm.
    ///
    /// This is not sematically a method of the dirstate map, but a different
    /// algorithm is used for the flat v.s. tree dirstate map so having it in
    /// this trait enables the same dynamic dispatch as with other methods.
    fn status<'a>(
        &'a mut self,
        matcher: &'a (dyn Matcher + Sync),
        root_dir: PathBuf,
        ignore_files: Vec<PathBuf>,
        options: StatusOptions,
    ) -> Result<(DirstateStatus<'a>, Vec<PatternFileWarning>), StatusError>;

    /// Returns how many files in the dirstate map have a recorded copy source.
    fn copy_map_len(&self) -> usize;

    /// Returns an iterator of `(path, copy_source)` for all files that have a
    /// copy source.
    fn copy_map_iter(&self) -> CopyMapIter<'_>;

    /// Returns whether the givef file has a copy source.
    fn copy_map_contains_key(
        &self,
        key: &HgPath,
    ) -> Result<bool, DirstateV2ParseError>;

    /// Returns the copy source for the given file.
    fn copy_map_get(
        &self,
        key: &HgPath,
    ) -> Result<Option<&HgPath>, DirstateV2ParseError>;

    /// Removes the recorded copy source if any for the given file, and returns
    /// it.
    fn copy_map_remove(
        &mut self,
        key: &HgPath,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError>;

    /// Set the given `value` copy source for the given `key` file.
    fn copy_map_insert(
        &mut self,
        key: HgPathBuf,
        value: HgPathBuf,
    ) -> Result<Option<HgPathBuf>, DirstateV2ParseError>;

    /// Returns the number of files that have an entry.
    fn len(&self) -> usize;

    /// Returns whether the given file has an entry.
    fn contains_key(&self, key: &HgPath)
        -> Result<bool, DirstateV2ParseError>;

    /// Returns the entry, if any, for the given file.
    fn get(
        &self,
        key: &HgPath,
    ) -> Result<Option<DirstateEntry>, DirstateV2ParseError>;

    /// Returns a `(path, entry)` iterator of files that have an entry.
    ///
    /// Because parse errors can happen during iteration, the iterated items
    /// are `Result`s.
    fn iter(&self) -> StateMapIter<'_>;

    /// Returns an iterator of tracked directories.
    ///
    /// This is the paths for which `has_tracked_dir` would return true.
    /// Or, in other words, the union of ancestor paths of all paths that have
    /// an associated entry in a "tracked" state in this dirstate map.
    ///
    /// Because parse errors can happen during iteration, the iterated items
    /// are `Result`s.
    fn iter_tracked_dirs(
        &mut self,
    ) -> Result<
        Box<
            dyn Iterator<Item = Result<&HgPath, DirstateV2ParseError>>
                + Send
                + '_,
        >,
        DirstateError,
    >;

    /// Return an iterator of `(path, (state, mode, size, mtime))` for every
    /// node stored in this dirstate map, for the purpose of the `hg
    /// debugdirstate` command.
    ///
    /// For nodes that don’t have an entry, `state` is the ASCII space.
    /// An `mtime` may still be present. It is used to optimize `status`.
    ///
    /// Because parse errors can happen during iteration, the iterated items
    /// are `Result`s.
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
    >;
}

impl DirstateMapMethods for DirstateMap {
    fn clear(&mut self) {
        self.clear()
    }

    /// Used to set a value directory.
    ///
    /// XXX Is temporary during a refactor of V1 dirstate and will disappear
    /// shortly.
    fn set_v1(&mut self, filename: &HgPath, entry: DirstateEntry) {
        self.set_v1_inner(&filename, entry)
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
        self.add_file(filename, entry, added, merged, from_p2, possibly_dirty)
    }

    fn remove_file(
        &mut self,
        filename: &HgPath,
        in_merge: bool,
    ) -> Result<(), DirstateError> {
        self.remove_file(filename, in_merge)
    }

    fn drop_file(&mut self, filename: &HgPath) -> Result<bool, DirstateError> {
        self.drop_file(filename)
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

    fn non_normal_entries_remove(&mut self, key: &HgPath) -> bool {
        self.non_normal_entries_remove(key)
    }

    fn non_normal_entries_add(&mut self, key: &HgPath) {
        self.non_normal_entries_add(key)
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
        _now: Timestamp,
        _can_append: bool,
    ) -> Result<(Vec<u8>, Vec<u8>, bool), DirstateError> {
        panic!(
            "should have used dirstate_tree::DirstateMap to use the v2 format"
        )
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
        self.set_all_dirs()?;
        Ok(Box::new(
            self.all_dirs
                .as_ref()
                .unwrap()
                .iter()
                .map(|path| Ok(&**path)),
        ))
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
        Box::new(
            (&**self)
                .iter()
                .map(|(path, entry)| Ok((&**path, entry.debug_tuple()))),
        )
    }
}

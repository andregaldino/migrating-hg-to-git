use crate::errors::{HgError, IoResultExt};
use crate::operations::{find_root, FindRootError};
use crate::requirements;
use memmap::{Mmap, MmapOptions};
use std::path::{Path, PathBuf};

/// A repository on disk
pub struct Repo {
    working_directory: PathBuf,
    dot_hg: PathBuf,
    store: PathBuf,
}

/// Filesystem access abstraction for the contents of a given "base" diretory
#[derive(Clone, Copy)]
pub(crate) struct Vfs<'a> {
    base: &'a Path,
}

impl Repo {
    /// Returns `None` if the given path doesn’t look like a repository
    /// (doesn’t contain a `.hg` sub-directory).
    pub fn for_path(root: impl Into<PathBuf>) -> Self {
        let working_directory = root.into();
        let dot_hg = working_directory.join(".hg");
        Self {
            store: dot_hg.join("store"),
            dot_hg,
            working_directory,
        }
    }

    pub fn find() -> Result<Self, FindRootError> {
        find_root().map(Self::for_path)
    }

    pub fn check_requirements(&self) -> Result<(), HgError> {
        requirements::check(self)
    }

    pub fn working_directory_path(&self) -> &Path {
        &self.working_directory
    }

    /// For accessing repository files (in `.hg`), except for the store
    /// (`.hg/store`).
    pub(crate) fn hg_vfs(&self) -> Vfs<'_> {
        Vfs { base: &self.dot_hg }
    }

    /// For accessing repository store files (in `.hg/store`)
    pub(crate) fn store_vfs(&self) -> Vfs<'_> {
        Vfs { base: &self.store }
    }

    /// For accessing the working copy

    // The undescore prefix silences the "never used" warning. Remove before
    // using.
    pub(crate) fn _working_directory_vfs(&self) -> Vfs<'_> {
        Vfs {
            base: &self.working_directory,
        }
    }
}

impl Vfs<'_> {
    pub(crate) fn read(
        &self,
        relative_path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, HgError> {
        let path = self.base.join(relative_path);
        std::fs::read(&path).for_file(&path)
    }

    pub(crate) fn mmap_open(
        &self,
        relative_path: impl AsRef<Path>,
    ) -> Result<Mmap, HgError> {
        let path = self.base.join(relative_path);
        let file = std::fs::File::open(&path).for_file(&path)?;
        // TODO: what are the safety requirements here?
        let mmap = unsafe { MmapOptions::new().map(&file) }.for_file(&path)?;
        Ok(mmap)
    }
}

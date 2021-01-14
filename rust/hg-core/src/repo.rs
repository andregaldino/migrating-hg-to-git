use crate::errors::{HgError, IoResultExt};
use crate::requirements;
use crate::utils::files::get_path_from_bytes;
use memmap::{Mmap, MmapOptions};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

/// A repository on disk
pub struct Repo {
    working_directory: PathBuf,
    dot_hg: PathBuf,
    store: PathBuf,
    requirements: HashSet<String>,
}

#[derive(Debug, derive_more::From)]
pub enum RepoFindError {
    NotFoundInCurrentDirectoryOrAncestors {
        current_directory: PathBuf,
    },
    #[from]
    Other(HgError),
}

/// Filesystem access abstraction for the contents of a given "base" diretory
#[derive(Clone, Copy)]
pub(crate) struct Vfs<'a> {
    base: &'a Path,
}

impl Repo {
    /// Search the current directory and its ancestores for a repository:
    /// a working directory that contains a `.hg` sub-directory.
    pub fn find() -> Result<Self, RepoFindError> {
        let current_directory = crate::utils::current_dir()?;
        // ancestors() is inclusive: it first yields `current_directory` as-is.
        for ancestor in current_directory.ancestors() {
            if ancestor.join(".hg").is_dir() {
                return Ok(Self::new_at_path(ancestor.to_owned())?);
            }
        }
        Err(RepoFindError::NotFoundInCurrentDirectoryOrAncestors {
            current_directory,
        })
    }

    /// To be called after checking that `.hg` is a sub-directory
    fn new_at_path(working_directory: PathBuf) -> Result<Self, HgError> {
        let dot_hg = working_directory.join(".hg");
        let hg_vfs = Vfs { base: &dot_hg };
        let reqs = requirements::load_if_exists(hg_vfs)?;
        let relative =
            reqs.contains(requirements::RELATIVE_SHARED_REQUIREMENT);
        let shared =
            reqs.contains(requirements::SHARED_REQUIREMENT) || relative;
        let store_path;
        if !shared {
            store_path = dot_hg.join("store");
        } else {
            let bytes = hg_vfs.read("sharedpath")?;
            let mut shared_path = get_path_from_bytes(&bytes).to_owned();
            if relative {
                shared_path = dot_hg.join(shared_path)
            }
            if !shared_path.is_dir() {
                return Err(HgError::corrupted(format!(
                    ".hg/sharedpath points to nonexistent directory {}",
                    shared_path.display()
                )));
            }

            store_path = shared_path.join("store");
        }

        let repo = Self {
            requirements: reqs,
            working_directory,
            store: store_path,
            dot_hg,
        };

        requirements::check(&repo)?;

        Ok(repo)
    }

    pub fn working_directory_path(&self) -> &Path {
        &self.working_directory
    }

    pub fn requirements(&self) -> &HashSet<String> {
        &self.requirements
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
    pub(crate) fn join(&self, relative_path: impl AsRef<Path>) -> PathBuf {
        self.base.join(relative_path)
    }

    pub(crate) fn read(
        &self,
        relative_path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, HgError> {
        let path = self.join(relative_path);
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

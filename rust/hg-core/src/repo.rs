use crate::config::{Config, ConfigError, ConfigParseError};
use crate::errors::{HgError, IoErrorContext, IoResultExt};
use crate::requirements;
use crate::utils::current_dir;
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
    config: Config,
}

#[derive(Debug, derive_more::From)]
pub enum RepoError {
    NotFound {
        at: PathBuf,
    },
    #[from]
    ConfigParseError(ConfigParseError),
    #[from]
    Other(HgError),
}

impl From<ConfigError> for RepoError {
    fn from(error: ConfigError) -> Self {
        match error {
            ConfigError::Parse(error) => error.into(),
            ConfigError::Other(error) => error.into(),
        }
    }
}

/// Filesystem access abstraction for the contents of a given "base" diretory
#[derive(Clone, Copy)]
pub struct Vfs<'a> {
    pub(crate) base: &'a Path,
}

impl Repo {
    /// Find a repository, either at the given path (which must contain a `.hg`
    /// sub-directory) or by searching the current directory and its
    /// ancestors.
    ///
    /// A method with two very different "modes" like this usually a code smell
    /// to make two methods instead, but in this case an `Option` is what rhg
    /// sub-commands get from Clap for the `-R` / `--repository` CLI argument.
    /// Having two methods would just move that `if` to almost all callers.
    pub fn find(
        config: &Config,
        explicit_path: Option<&Path>,
    ) -> Result<Self, RepoError> {
        if let Some(root) = explicit_path {
            // Having an absolute path isn’t necessary here but can help code
            // elsewhere
            let root = current_dir()?.join(root);
            if root.join(".hg").is_dir() {
                Self::new_at_path(root, config)
            } else {
                Err(RepoError::NotFound {
                    at: root.to_owned(),
                })
            }
        } else {
            let current_directory = crate::utils::current_dir()?;
            // ancestors() is inclusive: it first yields `current_directory`
            // as-is.
            for ancestor in current_directory.ancestors() {
                if ancestor.join(".hg").is_dir() {
                    return Self::new_at_path(ancestor.to_owned(), config);
                }
            }
            Err(RepoError::NotFound {
                at: current_directory,
            })
        }
    }

    /// To be called after checking that `.hg` is a sub-directory
    fn new_at_path(
        working_directory: PathBuf,
        config: &Config,
    ) -> Result<Self, RepoError> {
        let dot_hg = working_directory.join(".hg");

        let mut repo_config_files = Vec::new();
        repo_config_files.push(dot_hg.join("hgrc"));
        repo_config_files.push(dot_hg.join("hgrc-not-shared"));

        let hg_vfs = Vfs { base: &dot_hg };
        let mut reqs = requirements::load_if_exists(hg_vfs)?;
        let relative =
            reqs.contains(requirements::RELATIVE_SHARED_REQUIREMENT);
        let shared =
            reqs.contains(requirements::SHARED_REQUIREMENT) || relative;

        // From `mercurial/localrepo.py`:
        //
        // if .hg/requires contains the sharesafe requirement, it means
        // there exists a `.hg/store/requires` too and we should read it
        // NOTE: presence of SHARESAFE_REQUIREMENT imply that store requirement
        // is present. We never write SHARESAFE_REQUIREMENT for a repo if store
        // is not present, refer checkrequirementscompat() for that
        //
        // However, if SHARESAFE_REQUIREMENT is not present, it means that the
        // repository was shared the old way. We check the share source
        // .hg/requires for SHARESAFE_REQUIREMENT to detect whether the
        // current repository needs to be reshared
        let share_safe = reqs.contains(requirements::SHARESAFE_REQUIREMENT);

        let store_path;
        if !shared {
            store_path = dot_hg.join("store");
            if share_safe {
                reqs.extend(requirements::load(Vfs { base: &store_path })?);
            }
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
                ))
                .into());
            }

            store_path = shared_path.join("store");

            let source_is_share_safe =
                requirements::load(Vfs { base: &shared_path })?
                    .contains(requirements::SHARESAFE_REQUIREMENT);

            if share_safe && !source_is_share_safe {
                return Err(match config
                    .get(b"safe-mismatch", b"source-not-safe")
                {
                    Some(b"abort") | None => HgError::abort(
                        "share source does not support share-safe requirement",
                    ),
                    _ => HgError::unsupported("share-safe downgrade"),
                }
                .into());
            } else if source_is_share_safe && !share_safe {
                return Err(
                    match config.get(b"safe-mismatch", b"source-safe") {
                        Some(b"abort") | None => HgError::abort(
                            "version mismatch: source uses share-safe \
                            functionality while the current share does not",
                        ),
                        _ => HgError::unsupported("share-safe upgrade"),
                    }
                    .into(),
                );
            }

            if share_safe {
                repo_config_files.insert(0, shared_path.join("hgrc"))
            }
        }

        let repo_config = config.combine_with_repo(&repo_config_files)?;

        let repo = Self {
            requirements: reqs,
            working_directory,
            store: store_path,
            dot_hg,
            config: repo_config,
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

    pub fn config(&self) -> &Config {
        &self.config
    }

    /// For accessing repository files (in `.hg`), except for the store
    /// (`.hg/store`).
    pub fn hg_vfs(&self) -> Vfs<'_> {
        Vfs { base: &self.dot_hg }
    }

    /// For accessing repository store files (in `.hg/store`)
    pub fn store_vfs(&self) -> Vfs<'_> {
        Vfs { base: &self.store }
    }

    /// For accessing the working copy

    // The undescore prefix silences the "never used" warning. Remove before
    // using.
    pub fn _working_directory_vfs(&self) -> Vfs<'_> {
        Vfs {
            base: &self.working_directory,
        }
    }

    pub fn dirstate_parents(
        &self,
    ) -> Result<crate::dirstate::DirstateParents, HgError> {
        let dirstate = self.hg_vfs().mmap_open("dirstate")?;
        let parents =
            crate::dirstate::parsers::parse_dirstate_parents(&dirstate)?;
        Ok(parents.clone())
    }
}

impl Vfs<'_> {
    pub fn join(&self, relative_path: impl AsRef<Path>) -> PathBuf {
        self.base.join(relative_path)
    }

    pub fn read(
        &self,
        relative_path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, HgError> {
        let path = self.join(relative_path);
        std::fs::read(&path).when_reading_file(&path)
    }

    pub fn mmap_open(
        &self,
        relative_path: impl AsRef<Path>,
    ) -> Result<Mmap, HgError> {
        let path = self.base.join(relative_path);
        let file = std::fs::File::open(&path).when_reading_file(&path)?;
        // TODO: what are the safety requirements here?
        let mmap = unsafe { MmapOptions::new().map(&file) }
            .when_reading_file(&path)?;
        Ok(mmap)
    }

    pub fn rename(
        &self,
        relative_from: impl AsRef<Path>,
        relative_to: impl AsRef<Path>,
    ) -> Result<(), HgError> {
        let from = self.join(relative_from);
        let to = self.join(relative_to);
        std::fs::rename(&from, &to)
            .with_context(|| IoErrorContext::RenamingFile { from, to })
    }
}

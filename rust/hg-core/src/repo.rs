use crate::changelog::Changelog;
use crate::config::{Config, ConfigError, ConfigParseError};
use crate::dirstate::DirstateParents;
use crate::dirstate_tree::dirstate_map::DirstateMap;
use crate::dirstate_tree::owning::OwningDirstateMap;
use crate::errors::HgError;
use crate::errors::HgResultExt;
use crate::exit_codes;
use crate::manifest::{Manifest, Manifestlog};
use crate::revlog::filelog::Filelog;
use crate::revlog::revlog::RevlogError;
use crate::utils::files::get_path_from_bytes;
use crate::utils::hg_path::HgPath;
use crate::utils::SliceExt;
use crate::vfs::{is_dir, is_file, Vfs};
use crate::{requirements, NodePrefix};
use crate::{DirstateError, Revision};
use std::cell::{Cell, Ref, RefCell, RefMut};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

/// A repository on disk
pub struct Repo {
    working_directory: PathBuf,
    dot_hg: PathBuf,
    store: PathBuf,
    requirements: HashSet<String>,
    config: Config,
    // None means not known/initialized yet
    dirstate_parents: Cell<Option<DirstateParents>>,
    dirstate_map: LazyCell<OwningDirstateMap, DirstateError>,
    changelog: LazyCell<Changelog, HgError>,
    manifestlog: LazyCell<Manifestlog, HgError>,
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

impl Repo {
    /// tries to find nearest repository root in current working directory or
    /// its ancestors
    pub fn find_repo_root() -> Result<PathBuf, RepoError> {
        let current_directory = crate::utils::current_dir()?;
        // ancestors() is inclusive: it first yields `current_directory`
        // as-is.
        for ancestor in current_directory.ancestors() {
            if is_dir(ancestor.join(".hg"))? {
                return Ok(ancestor.to_path_buf());
            }
        }
        return Err(RepoError::NotFound {
            at: current_directory,
        });
    }

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
        explicit_path: Option<PathBuf>,
    ) -> Result<Self, RepoError> {
        if let Some(root) = explicit_path {
            if is_dir(root.join(".hg"))? {
                Self::new_at_path(root.to_owned(), config)
            } else if is_file(&root)? {
                Err(HgError::unsupported("bundle repository").into())
            } else {
                Err(RepoError::NotFound {
                    at: root.to_owned(),
                })
            }
        } else {
            let root = Self::find_repo_root()?;
            Self::new_at_path(root, config)
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
        } else {
            let bytes = hg_vfs.read("sharedpath")?;
            let mut shared_path =
                get_path_from_bytes(bytes.trim_end_matches(|b| b == b'\n'))
                    .to_owned();
            if relative {
                shared_path = dot_hg.join(shared_path)
            }
            if !is_dir(&shared_path)? {
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
                    .get(b"share", b"safe-mismatch.source-not-safe")
                {
                    Some(b"abort") | None => HgError::abort(
                        "abort: share source does not support share-safe requirement\n\
                        (see `hg help config.format.use-share-safe` for more information)",
                        exit_codes::ABORT,
                    ),
                    _ => HgError::unsupported("share-safe downgrade"),
                }
                .into());
            } else if source_is_share_safe && !share_safe {
                return Err(
                    match config.get(b"share", b"safe-mismatch.source-safe") {
                        Some(b"abort") | None => HgError::abort(
                            "abort: version mismatch: source uses share-safe \
                            functionality while the current share does not\n\
                            (see `hg help config.format.use-share-safe` for more information)",
                        exit_codes::ABORT,
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
        if share_safe {
            reqs.extend(requirements::load(Vfs { base: &store_path })?);
        }

        let repo_config = if std::env::var_os("HGRCSKIPREPO").is_none() {
            config.combine_with_repo(&repo_config_files)?
        } else {
            config.clone()
        };

        let repo = Self {
            requirements: reqs,
            working_directory,
            store: store_path,
            dot_hg,
            config: repo_config,
            dirstate_parents: Cell::new(None),
            dirstate_map: LazyCell::new(Self::new_dirstate_map),
            changelog: LazyCell::new(Changelog::open),
            manifestlog: LazyCell::new(Manifestlog::open),
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
    pub fn working_directory_vfs(&self) -> Vfs<'_> {
        Vfs {
            base: &self.working_directory,
        }
    }

    pub fn has_dirstate_v2(&self) -> bool {
        self.requirements
            .contains(requirements::DIRSTATE_V2_REQUIREMENT)
    }

    pub fn has_sparse(&self) -> bool {
        self.requirements.contains(requirements::SPARSE_REQUIREMENT)
    }

    pub fn has_narrow(&self) -> bool {
        self.requirements.contains(requirements::NARROW_REQUIREMENT)
    }

    fn dirstate_file_contents(&self) -> Result<Vec<u8>, HgError> {
        Ok(self
            .hg_vfs()
            .read("dirstate")
            .io_not_found_as_none()?
            .unwrap_or(Vec::new()))
    }

    pub fn dirstate_parents(&self) -> Result<DirstateParents, HgError> {
        if let Some(parents) = self.dirstate_parents.get() {
            return Ok(parents);
        }
        let dirstate = self.dirstate_file_contents()?;
        let parents = if dirstate.is_empty() {
            DirstateParents::NULL
        } else if self.has_dirstate_v2() {
            crate::dirstate_tree::on_disk::read_docket(&dirstate)?.parents()
        } else {
            crate::dirstate::parsers::parse_dirstate_parents(&dirstate)?
                .clone()
        };
        self.dirstate_parents.set(Some(parents));
        Ok(parents)
    }

    fn new_dirstate_map(&self) -> Result<OwningDirstateMap, DirstateError> {
        let dirstate_file_contents = self.dirstate_file_contents()?;
        if dirstate_file_contents.is_empty() {
            self.dirstate_parents.set(Some(DirstateParents::NULL));
            Ok(OwningDirstateMap::new_empty(Vec::new()))
        } else if self.has_dirstate_v2() {
            let docket = crate::dirstate_tree::on_disk::read_docket(
                &dirstate_file_contents,
            )?;
            self.dirstate_parents.set(Some(docket.parents()));
            let data_size = docket.data_size();
            let metadata = docket.tree_metadata();
            let mut map = if let Some(data_mmap) = self
                .hg_vfs()
                .mmap_open(docket.data_filename())
                .io_not_found_as_none()?
            {
                OwningDirstateMap::new_empty(data_mmap)
            } else {
                OwningDirstateMap::new_empty(Vec::new())
            };
            let (on_disk, placeholder) = map.get_pair_mut();
            *placeholder = DirstateMap::new_v2(on_disk, data_size, metadata)?;
            Ok(map)
        } else {
            let mut map = OwningDirstateMap::new_empty(dirstate_file_contents);
            let (on_disk, placeholder) = map.get_pair_mut();
            let (inner, parents) = DirstateMap::new_v1(on_disk)?;
            self.dirstate_parents
                .set(Some(parents.unwrap_or(DirstateParents::NULL)));
            *placeholder = inner;
            Ok(map)
        }
    }

    pub fn dirstate_map(
        &self,
    ) -> Result<Ref<OwningDirstateMap>, DirstateError> {
        self.dirstate_map.get_or_init(self)
    }

    pub fn dirstate_map_mut(
        &self,
    ) -> Result<RefMut<OwningDirstateMap>, DirstateError> {
        self.dirstate_map.get_mut_or_init(self)
    }

    pub fn changelog(&self) -> Result<Ref<Changelog>, HgError> {
        self.changelog.get_or_init(self)
    }

    pub fn changelog_mut(&self) -> Result<RefMut<Changelog>, HgError> {
        self.changelog.get_mut_or_init(self)
    }

    pub fn manifestlog(&self) -> Result<Ref<Manifestlog>, HgError> {
        self.manifestlog.get_or_init(self)
    }

    pub fn manifestlog_mut(&self) -> Result<RefMut<Manifestlog>, HgError> {
        self.manifestlog.get_mut_or_init(self)
    }

    /// Returns the manifest of the *changeset* with the given node ID
    pub fn manifest_for_node(
        &self,
        node: impl Into<NodePrefix>,
    ) -> Result<Manifest, RevlogError> {
        self.manifestlog()?.data_for_node(
            self.changelog()?
                .data_for_node(node.into())?
                .manifest_node()?
                .into(),
        )
    }

    /// Returns the manifest of the *changeset* with the given revision number
    pub fn manifest_for_rev(
        &self,
        revision: Revision,
    ) -> Result<Manifest, RevlogError> {
        self.manifestlog()?.data_for_node(
            self.changelog()?
                .data_for_rev(revision)?
                .manifest_node()?
                .into(),
        )
    }

    pub fn filelog(&self, path: &HgPath) -> Result<Filelog, HgError> {
        Filelog::open(self, path)
    }
}

/// Lazily-initialized component of `Repo` with interior mutability
///
/// This differs from `OnceCell` in that the value can still be "deinitialized"
/// later by setting its inner `Option` to `None`.
struct LazyCell<T, E> {
    value: RefCell<Option<T>>,
    // `Fn`s that don’t capture environment are zero-size, so this box does
    // not allocate:
    init: Box<dyn Fn(&Repo) -> Result<T, E>>,
}

impl<T, E> LazyCell<T, E> {
    fn new(init: impl Fn(&Repo) -> Result<T, E> + 'static) -> Self {
        Self {
            value: RefCell::new(None),
            init: Box::new(init),
        }
    }

    fn get_or_init(&self, repo: &Repo) -> Result<Ref<T>, E> {
        let mut borrowed = self.value.borrow();
        if borrowed.is_none() {
            drop(borrowed);
            // Only use `borrow_mut` if it is really needed to avoid panic in
            // case there is another outstanding borrow but mutation is not
            // needed.
            *self.value.borrow_mut() = Some((self.init)(repo)?);
            borrowed = self.value.borrow()
        }
        Ok(Ref::map(borrowed, |option| option.as_ref().unwrap()))
    }

    pub fn get_mut_or_init(&self, repo: &Repo) -> Result<RefMut<T>, E> {
        let mut borrowed = self.value.borrow_mut();
        if borrowed.is_none() {
            *borrowed = Some((self.init)(repo)?);
        }
        Ok(RefMut::map(borrowed, |option| option.as_mut().unwrap()))
    }
}

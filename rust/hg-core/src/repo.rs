use crate::changelog::Changelog;
use crate::config::{Config, ConfigError, ConfigParseError};
use crate::dirstate::DirstateParents;
use crate::dirstate_tree::on_disk::Docket as DirstateDocket;
use crate::dirstate_tree::owning::OwningDirstateMap;
use crate::errors::HgResultExt;
use crate::errors::{HgError, IoResultExt};
use crate::lock::{try_with_lock_no_wait, LockError};
use crate::manifest::{Manifest, Manifestlog};
use crate::revlog::filelog::Filelog;
use crate::revlog::revlog::RevlogError;
use crate::utils::files::get_path_from_bytes;
use crate::utils::hg_path::HgPath;
use crate::utils::SliceExt;
use crate::vfs::{is_dir, is_file, Vfs};
use crate::{requirements, NodePrefix};
use crate::{DirstateError, Revision};
use std::cell::{Ref, RefCell, RefMut};
use std::collections::HashSet;
use std::io::Seek;
use std::io::SeekFrom;
use std::io::Write as IoWrite;
use std::path::{Path, PathBuf};

/// A repository on disk
pub struct Repo {
    working_directory: PathBuf,
    dot_hg: PathBuf,
    store: PathBuf,
    requirements: HashSet<String>,
    config: Config,
    dirstate_parents: LazyCell<DirstateParents>,
    dirstate_data_file_uuid: LazyCell<Option<Vec<u8>>>,
    dirstate_map: LazyCell<OwningDirstateMap>,
    changelog: LazyCell<Changelog>,
    manifestlog: LazyCell<Manifestlog>,
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

            if share_safe != source_is_share_safe {
                return Err(HgError::unsupported("share-safe mismatch").into());
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
            dirstate_parents: LazyCell::new(),
            dirstate_data_file_uuid: LazyCell::new(),
            dirstate_map: LazyCell::new(),
            changelog: LazyCell::new(),
            manifestlog: LazyCell::new(),
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

    pub fn try_with_wlock_no_wait<R>(
        &self,
        f: impl FnOnce() -> R,
    ) -> Result<R, LockError> {
        try_with_lock_no_wait(self.hg_vfs(), "wlock", f)
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

    pub fn has_nodemap(&self) -> bool {
        self.requirements
            .contains(requirements::NODEMAP_REQUIREMENT)
    }

    fn dirstate_file_contents(&self) -> Result<Vec<u8>, HgError> {
        Ok(self
            .hg_vfs()
            .read("dirstate")
            .io_not_found_as_none()?
            .unwrap_or(Vec::new()))
    }

    pub fn dirstate_parents(&self) -> Result<DirstateParents, HgError> {
        Ok(*self
            .dirstate_parents
            .get_or_init(|| self.read_dirstate_parents())?)
    }

    fn read_dirstate_parents(&self) -> Result<DirstateParents, HgError> {
        let dirstate = self.dirstate_file_contents()?;
        let parents = if dirstate.is_empty() {
            if self.has_dirstate_v2() {
                self.dirstate_data_file_uuid.set(None);
            }
            DirstateParents::NULL
        } else if self.has_dirstate_v2() {
            let docket =
                crate::dirstate_tree::on_disk::read_docket(&dirstate)?;
            self.dirstate_data_file_uuid
                .set(Some(docket.uuid.to_owned()));
            docket.parents()
        } else {
            crate::dirstate::parsers::parse_dirstate_parents(&dirstate)?
                .clone()
        };
        self.dirstate_parents.set(parents);
        Ok(parents)
    }

    fn read_dirstate_data_file_uuid(
        &self,
    ) -> Result<Option<Vec<u8>>, HgError> {
        assert!(
            self.has_dirstate_v2(),
            "accessing dirstate data file ID without dirstate-v2"
        );
        let dirstate = self.dirstate_file_contents()?;
        if dirstate.is_empty() {
            self.dirstate_parents.set(DirstateParents::NULL);
            Ok(None)
        } else {
            let docket =
                crate::dirstate_tree::on_disk::read_docket(&dirstate)?;
            self.dirstate_parents.set(docket.parents());
            Ok(Some(docket.uuid.to_owned()))
        }
    }

    fn new_dirstate_map(&self) -> Result<OwningDirstateMap, DirstateError> {
        let dirstate_file_contents = self.dirstate_file_contents()?;
        if dirstate_file_contents.is_empty() {
            self.dirstate_parents.set(DirstateParents::NULL);
            if self.has_dirstate_v2() {
                self.dirstate_data_file_uuid.set(None);
            }
            Ok(OwningDirstateMap::new_empty(Vec::new()))
        } else if self.has_dirstate_v2() {
            let docket = crate::dirstate_tree::on_disk::read_docket(
                &dirstate_file_contents,
            )?;
            self.dirstate_parents.set(docket.parents());
            self.dirstate_data_file_uuid
                .set(Some(docket.uuid.to_owned()));
            let data_size = docket.data_size();
            let metadata = docket.tree_metadata();
            if let Some(data_mmap) = self
                .hg_vfs()
                .mmap_open(docket.data_filename())
                .io_not_found_as_none()?
            {
                OwningDirstateMap::new_v2(data_mmap, data_size, metadata)
            } else {
                OwningDirstateMap::new_v2(Vec::new(), data_size, metadata)
            }
        } else {
            let (map, parents) =
                OwningDirstateMap::new_v1(dirstate_file_contents)?;
            self.dirstate_parents.set(parents);
            Ok(map)
        }
    }

    pub fn dirstate_map(
        &self,
    ) -> Result<Ref<OwningDirstateMap>, DirstateError> {
        self.dirstate_map.get_or_init(|| self.new_dirstate_map())
    }

    pub fn dirstate_map_mut(
        &self,
    ) -> Result<RefMut<OwningDirstateMap>, DirstateError> {
        self.dirstate_map
            .get_mut_or_init(|| self.new_dirstate_map())
    }

    fn new_changelog(&self) -> Result<Changelog, HgError> {
        Changelog::open(&self.store_vfs(), self.has_nodemap())
    }

    pub fn changelog(&self) -> Result<Ref<Changelog>, HgError> {
        self.changelog.get_or_init(|| self.new_changelog())
    }

    pub fn changelog_mut(&self) -> Result<RefMut<Changelog>, HgError> {
        self.changelog.get_mut_or_init(|| self.new_changelog())
    }

    fn new_manifestlog(&self) -> Result<Manifestlog, HgError> {
        Manifestlog::open(&self.store_vfs(), self.has_nodemap())
    }

    pub fn manifestlog(&self) -> Result<Ref<Manifestlog>, HgError> {
        self.manifestlog.get_or_init(|| self.new_manifestlog())
    }

    pub fn manifestlog_mut(&self) -> Result<RefMut<Manifestlog>, HgError> {
        self.manifestlog.get_mut_or_init(|| self.new_manifestlog())
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

    pub fn has_subrepos(&self) -> Result<bool, DirstateError> {
        if let Some(entry) = self.dirstate_map()?.get(HgPath::new(".hgsub"))? {
            Ok(entry.tracked())
        } else {
            Ok(false)
        }
    }

    pub fn filelog(&self, path: &HgPath) -> Result<Filelog, HgError> {
        Filelog::open(self, path)
    }

    /// Write to disk any updates that were made through `dirstate_map_mut`.
    ///
    /// The "wlock" must be held while calling this.
    /// See for example `try_with_wlock_no_wait`.
    ///
    /// TODO: have a `WritableRepo` type only accessible while holding the
    /// lock?
    pub fn write_dirstate(&self) -> Result<(), DirstateError> {
        let map = self.dirstate_map()?;
        // TODO: Maintain a `DirstateMap::dirty` flag, and return early here if
        // it’s unset
        let parents = self.dirstate_parents()?;
        let (packed_dirstate, old_uuid_to_remove) = if self.has_dirstate_v2() {
            let uuid_opt = self
                .dirstate_data_file_uuid
                .get_or_init(|| self.read_dirstate_data_file_uuid())?;
            let uuid_opt = uuid_opt.as_ref();
            let can_append = uuid_opt.is_some();
            let (data, tree_metadata, append, old_data_size) =
                map.pack_v2(can_append)?;

            // Reuse the uuid, or generate a new one, keeping the old for
            // deletion.
            let (uuid, old_uuid) = match uuid_opt {
                Some(uuid) => {
                    let as_str = std::str::from_utf8(uuid)
                        .map_err(|_| {
                            HgError::corrupted(
                                "non-UTF-8 dirstate data file ID",
                            )
                        })?
                        .to_owned();
                    if append {
                        (as_str, None)
                    } else {
                        (DirstateDocket::new_uid(), Some(as_str))
                    }
                }
                None => (DirstateDocket::new_uid(), None),
            };

            let data_filename = format!("dirstate.{}", uuid);
            let data_filename = self.hg_vfs().join(data_filename);
            let mut options = std::fs::OpenOptions::new();
            options.write(true);

            // Why are we not using the O_APPEND flag when appending?
            //
            // - O_APPEND makes it trickier to deal with garbage at the end of
            //   the file, left by a previous uncommitted transaction. By
            //   starting the write at [old_data_size] we make sure we erase
            //   all such garbage.
            //
            // - O_APPEND requires to special-case 0-byte writes, whereas we
            //   don't need that.
            //
            // - Some OSes have bugs in implementation O_APPEND:
            //   revlog.py talks about a Solaris bug, but we also saw some ZFS
            //   bug: https://github.com/openzfs/zfs/pull/3124,
            //   https://github.com/openzfs/zfs/issues/13370
            //
            if !append {
                options.create_new(true);
            }

            let data_size = (|| {
                // TODO: loop and try another random ID if !append and this
                // returns `ErrorKind::AlreadyExists`? Collision chance of two
                // random IDs is one in 2**32
                let mut file = options.open(&data_filename)?;
                if append {
                    file.seek(SeekFrom::Start(old_data_size as u64))?;
                }
                file.write_all(&data)?;
                file.flush()?;
                file.seek(SeekFrom::Current(0))
            })()
            .when_writing_file(&data_filename)?;

            let packed_dirstate = DirstateDocket::serialize(
                parents,
                tree_metadata,
                data_size,
                uuid.as_bytes(),
            )
            .map_err(|_: std::num::TryFromIntError| {
                HgError::corrupted("overflow in dirstate docket serialization")
            })?;

            (packed_dirstate, old_uuid)
        } else {
            (map.pack_v1(parents)?, None)
        };

        let vfs = self.hg_vfs();
        vfs.atomic_write("dirstate", &packed_dirstate)?;
        if let Some(uuid) = old_uuid_to_remove {
            // Remove the old data file after the new docket pointing to the
            // new data file was written.
            vfs.remove_file(format!("dirstate.{}", uuid))?;
        }
        Ok(())
    }
}

/// Lazily-initialized component of `Repo` with interior mutability
///
/// This differs from `OnceCell` in that the value can still be "deinitialized"
/// later by setting its inner `Option` to `None`. It also takes the
/// initialization function as an argument when the value is requested, not
/// when the instance is created.
struct LazyCell<T> {
    value: RefCell<Option<T>>,
}

impl<T> LazyCell<T> {
    fn new() -> Self {
        Self {
            value: RefCell::new(None),
        }
    }

    fn set(&self, value: T) {
        *self.value.borrow_mut() = Some(value)
    }

    fn get_or_init<E>(
        &self,
        init: impl Fn() -> Result<T, E>,
    ) -> Result<Ref<T>, E> {
        let mut borrowed = self.value.borrow();
        if borrowed.is_none() {
            drop(borrowed);
            // Only use `borrow_mut` if it is really needed to avoid panic in
            // case there is another outstanding borrow but mutation is not
            // needed.
            *self.value.borrow_mut() = Some(init()?);
            borrowed = self.value.borrow()
        }
        Ok(Ref::map(borrowed, |option| option.as_ref().unwrap()))
    }

    fn get_mut_or_init<E>(
        &self,
        init: impl Fn() -> Result<T, E>,
    ) -> Result<RefMut<T>, E> {
        let mut borrowed = self.value.borrow_mut();
        if borrowed.is_none() {
            *borrowed = Some(init()?);
        }
        Ok(RefMut::map(borrowed, |option| option.as_mut().unwrap()))
    }
}

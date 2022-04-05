use crate::errors::{HgError, HgResultExt};
use crate::repo::Repo;
use crate::utils::join_display;
use crate::vfs::Vfs;
use std::collections::HashSet;

fn parse(bytes: &[u8]) -> Result<HashSet<String>, HgError> {
    // The Python code reading this file uses `str.splitlines`
    // which looks for a number of line separators (even including a couple of
    // non-ASCII ones), but Python code writing it always uses `\n`.
    let lines = bytes.split(|&byte| byte == b'\n');

    lines
        .filter(|line| !line.is_empty())
        .map(|line| {
            // Python uses Unicode `str.isalnum` but feature names are all
            // ASCII
            if line[0].is_ascii_alphanumeric() && line.is_ascii() {
                Ok(String::from_utf8(line.into()).unwrap())
            } else {
                Err(HgError::corrupted("parse error in 'requires' file"))
            }
        })
        .collect()
}

pub(crate) fn load(hg_vfs: Vfs) -> Result<HashSet<String>, HgError> {
    parse(&hg_vfs.read("requires")?)
}

pub(crate) fn load_if_exists(hg_vfs: Vfs) -> Result<HashSet<String>, HgError> {
    if let Some(bytes) = hg_vfs.read("requires").io_not_found_as_none()? {
        parse(&bytes)
    } else {
        // Treat a missing file the same as an empty file.
        // From `mercurial/localrepo.py`:
        // > requires file contains a newline-delimited list of
        // > features/capabilities the opener (us) must have in order to use
        // > the repository. This file was introduced in Mercurial 0.9.2,
        // > which means very old repositories may not have one. We assume
        // > a missing file translates to no requirements.
        Ok(HashSet::new())
    }
}

pub(crate) fn check(repo: &Repo) -> Result<(), HgError> {
    let unknown: Vec<_> = repo
        .requirements()
        .iter()
        .map(String::as_str)
        // .filter(|feature| !ALL_SUPPORTED.contains(feature.as_str()))
        .filter(|feature| {
            !REQUIRED.contains(feature) && !SUPPORTED.contains(feature)
        })
        .collect();
    if !unknown.is_empty() {
        return Err(HgError::unsupported(format!(
            "repository requires feature unknown to this Mercurial: {}",
            join_display(&unknown, ", ")
        )));
    }
    let missing: Vec<_> = REQUIRED
        .iter()
        .filter(|&&feature| !repo.requirements().contains(feature))
        .collect();
    if !missing.is_empty() {
        return Err(HgError::unsupported(format!(
            "repository is missing feature required by this Mercurial: {}",
            join_display(&missing, ", ")
        )));
    }
    Ok(())
}

/// rhg does not support repositories that are *missing* any of these features
const REQUIRED: &[&str] = &["revlogv1", "store", "fncache", "dotencode"];

/// rhg supports repository with or without these
const SUPPORTED: &[&str] = &[
    "generaldelta",
    SHARED_REQUIREMENT,
    SHARESAFE_REQUIREMENT,
    SPARSEREVLOG_REQUIREMENT,
    RELATIVE_SHARED_REQUIREMENT,
    REVLOG_COMPRESSION_ZSTD,
    DIRSTATE_V2_REQUIREMENT,
    // As of this writing everything rhg does is read-only.
    // When it starts writing to the repository, it’ll need to either keep the
    // persistent nodemap up to date or remove this entry:
    NODEMAP_REQUIREMENT,
    // Not all commands support `sparse` and `narrow`. The commands that do
    // not should opt out by checking `has_sparse` and `has_narrow`.
    SPARSE_REQUIREMENT,
    NARROW_REQUIREMENT,
    // rhg doesn't care about bookmarks at all yet
    BOOKMARKS_IN_STORE_REQUIREMENT,
];

// Copied from mercurial/requirements.py:

pub const DIRSTATE_V2_REQUIREMENT: &str = "dirstate-v2";

/// A repository that uses the tracked hint dirstate file
#[allow(unused)]
pub const DIRSTATE_TRACKED_HINT_V1: &str = "dirstate-tracked-key-v1";

/// When narrowing is finalized and no longer subject to format changes,
/// we should move this to just "narrow" or similar.
#[allow(unused)]
pub const NARROW_REQUIREMENT: &str = "narrowhg-experimental";

/// Bookmarks must be stored in the `store` part of the repository and will be
/// share accross shares
#[allow(unused)]
pub const BOOKMARKS_IN_STORE_REQUIREMENT: &str = "bookmarksinstore";

/// Enables sparse working directory usage
#[allow(unused)]
pub const SPARSE_REQUIREMENT: &str = "exp-sparse";

/// Enables the internal phase which is used to hide changesets instead
/// of stripping them
#[allow(unused)]
pub const INTERNAL_PHASE_REQUIREMENT: &str = "internal-phase";

/// Stores manifest in Tree structure
#[allow(unused)]
pub const TREEMANIFEST_REQUIREMENT: &str = "treemanifest";

/// Increment the sub-version when the revlog v2 format changes to lock out old
/// clients.
#[allow(unused)]
pub const REVLOGV2_REQUIREMENT: &str = "exp-revlogv2.1";

/// A repository with the sparserevlog feature will have delta chains that
/// can spread over a larger span. Sparse reading cuts these large spans into
/// pieces, so that each piece isn't too big.
/// Without the sparserevlog capability, reading from the repository could use
/// huge amounts of memory, because the whole span would be read at once,
/// including all the intermediate revisions that aren't pertinent for the
/// chain. This is why once a repository has enabled sparse-read, it becomes
/// required.
#[allow(unused)]
pub const SPARSEREVLOG_REQUIREMENT: &str = "sparserevlog";

/// A repository with the the copies-sidedata-changeset requirement will store
/// copies related information in changeset's sidedata.
#[allow(unused)]
pub const COPIESSDC_REQUIREMENT: &str = "exp-copies-sidedata-changeset";

/// The repository use persistent nodemap for the changelog and the manifest.
#[allow(unused)]
pub const NODEMAP_REQUIREMENT: &str = "persistent-nodemap";

/// Denotes that the current repository is a share
#[allow(unused)]
pub const SHARED_REQUIREMENT: &str = "shared";

/// Denotes that current repository is a share and the shared source path is
/// relative to the current repository root path
#[allow(unused)]
pub const RELATIVE_SHARED_REQUIREMENT: &str = "relshared";

/// A repository with share implemented safely. The repository has different
/// store and working copy requirements i.e. both `.hg/requires` and
/// `.hg/store/requires` are present.
#[allow(unused)]
pub const SHARESAFE_REQUIREMENT: &str = "share-safe";

/// A repository that use zstd compression inside its revlog
#[allow(unused)]
pub const REVLOG_COMPRESSION_ZSTD: &str = "revlog-compression-zstd";

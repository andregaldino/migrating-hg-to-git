use crate::errors::{HgError, HgResultExt, IoResultExt};
use crate::repo::Repo;

fn parse(bytes: &[u8]) -> Result<Vec<String>, HgError> {
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

pub fn load(repo: &Repo) -> Result<Vec<String>, HgError> {
    if let Some(bytes) = repo
        .hg_vfs()
        .read("requires")
        .for_file("requires".as_ref())
        .io_not_found_as_none()?
    {
        parse(&bytes)
    } else {
        // Treat a missing file the same as an empty file.
        // From `mercurial/localrepo.py`:
        // > requires file contains a newline-delimited list of
        // > features/capabilities the opener (us) must have in order to use
        // > the repository. This file was introduced in Mercurial 0.9.2,
        // > which means very old repositories may not have one. We assume
        // > a missing file translates to no requirements.
        Ok(Vec::new())
    }
}

pub fn check(repo: &Repo) -> Result<(), HgError> {
    for feature in load(repo)? {
        if !SUPPORTED.contains(&&*feature) {
            // TODO: collect and all unknown features and include them in the
            // error message?
            return Err(HgError::UnsupportedFeature(format!(
                "repository requires feature unknown to this Mercurial: {}",
                feature
            )));
        }
    }
    Ok(())
}

// TODO: set this to actually-supported features
const SUPPORTED: &[&str] = &[
    "dotencode",
    "fncache",
    "generaldelta",
    "revlogv1",
    "sparserevlog",
    "store",
    // As of this writing everything rhg does is read-only.
    // When it starts writing to the repository, it’ll need to either keep the
    // persistent nodemap up to date or remove this entry:
    "persistent-nodemap",
];

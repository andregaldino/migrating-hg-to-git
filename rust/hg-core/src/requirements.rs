use std::io;
use std::path::Path;

#[derive(Debug)]
pub enum RequirementsError {
    // TODO: include a path?
    Io(io::Error),
    /// The `requires` file is corrupted
    Corrupted,
    /// The repository requires a feature that we don’t support
    Unsupported {
        feature: String,
    },
}

fn parse(bytes: &[u8]) -> Result<Vec<String>, ()> {
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
                Err(())
            }
        })
        .collect()
}

pub fn load(repo_root: &Path) -> Result<Vec<String>, RequirementsError> {
    match std::fs::read(repo_root.join(".hg").join("requires")) {
        Ok(bytes) => parse(&bytes).map_err(|()| RequirementsError::Corrupted),

        // Treat a missing file the same as an empty file.
        // From `mercurial/localrepo.py`:
        // > requires file contains a newline-delimited list of
        // > features/capabilities the opener (us) must have in order to use
        // > the repository. This file was introduced in Mercurial 0.9.2,
        // > which means very old repositories may not have one. We assume
        // > a missing file translates to no requirements.
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            Ok(Vec::new())
        }

        Err(error) => Err(RequirementsError::Io(error))?,
    }
}

pub fn check(repo_root: &Path) -> Result<(), RequirementsError> {
    for feature in load(repo_root)? {
        if !SUPPORTED.contains(&&*feature) {
            return Err(RequirementsError::Unsupported { feature })
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
];

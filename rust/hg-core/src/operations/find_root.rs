use super::Operation;
use std::fmt;
use std::path::{Path, PathBuf};

/// Kind of error encoutered by FindRoot
#[derive(Debug)]
pub enum FindRootErrorKind {
    /// Root of the repository has not been found
    /// Contains the current directory used by FindRoot
    RootNotFound(PathBuf),
    /// The current directory does not exists or permissions are insufficient
    /// to get access to it
    GetCurrentDirError(std::io::Error),
}

/// A FindRoot error
#[derive(Debug)]
pub struct FindRootError {
    /// Kind of error encoutered by FindRoot
    pub kind: FindRootErrorKind,
}

impl std::error::Error for FindRootError {}

impl fmt::Display for FindRootError {
    fn fmt(&self, _f: &mut fmt::Formatter<'_>) -> fmt::Result {
        unimplemented!()
    }
}

/// Find the root of the repository
/// by searching for a .hg directory in the current directory and its
/// ancestors
pub struct FindRoot<'a> {
    current_dir: Option<&'a Path>,
}

impl<'a> FindRoot<'a> {
    pub fn new() -> Self {
        Self { current_dir: None }
    }

    pub fn new_from_path(current_dir: &'a Path) -> Self {
        Self {
            current_dir: Some(current_dir),
        }
    }
}

impl<'a> Operation<PathBuf> for FindRoot<'a> {
    type Error = FindRootError;

    fn run(&self) -> Result<PathBuf, Self::Error> {
        let current_dir = match self.current_dir {
            None => std::env::current_dir().or_else(|e| {
                Err(FindRootError {
                    kind: FindRootErrorKind::GetCurrentDirError(e),
                })
            })?,
            Some(path) => path.into(),
        };

        if current_dir.join(".hg").exists() {
            return Ok(current_dir.into());
        }
        let mut ancestors = current_dir.ancestors();
        while let Some(parent) = ancestors.next() {
            if parent.join(".hg").exists() {
                return Ok(parent.into());
            }
        }
        Err(FindRootError {
            kind: FindRootErrorKind::RootNotFound(current_dir.to_path_buf()),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile;

    #[test]
    fn dot_hg_not_found() {
        let tmp_dir = tempfile::tempdir().unwrap();
        let path = tmp_dir.path();

        let err = FindRoot::new_from_path(&path).run().unwrap_err();

        // TODO do something better
        assert!(match err {
            FindRootError { kind } => match kind {
                FindRootErrorKind::RootNotFound(p) => p == path.to_path_buf(),
                _ => false,
            },
        })
    }

    #[test]
    fn dot_hg_in_current_path() {
        let tmp_dir = tempfile::tempdir().unwrap();
        let root = tmp_dir.path();
        fs::create_dir_all(root.join(".hg")).unwrap();

        let result = FindRoot::new_from_path(&root).run().unwrap();

        assert_eq!(result, root)
    }

    #[test]
    fn dot_hg_in_parent() {
        let tmp_dir = tempfile::tempdir().unwrap();
        let root = tmp_dir.path();
        fs::create_dir_all(root.join(".hg")).unwrap();

        let result =
            FindRoot::new_from_path(&root.join("some/nested/directory"))
                .run()
                .unwrap();

        assert_eq!(result, root)
    }
} /* tests */

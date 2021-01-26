use std::path::{Path, PathBuf};

/// Error type for `find_root`
#[derive(Debug)]
pub enum FindRootError {
    /// Root of the repository has not been found
    /// Contains the current directory used by FindRoot
    RootNotFound(PathBuf),
    /// The current directory does not exists or permissions are insufficient
    /// to get access to it
    GetCurrentDirError(std::io::Error),
}

/// Find the root of the repository
/// by searching for a .hg directory in the process’ current directory and its
/// ancestors
pub fn find_root() -> Result<PathBuf, FindRootError> {
    let current_dir = std::env::current_dir()
        .map_err(|e| FindRootError::GetCurrentDirError(e))?;
    Ok(find_root_from_path(&current_dir)?.into())
}

/// Find the root of the repository
/// by searching for a .hg directory in the given directory and its ancestors
pub fn find_root_from_path(start: &Path) -> Result<&Path, FindRootError> {
    if start.join(".hg").exists() {
        return Ok(start);
    }
    for ancestor in start.ancestors() {
        if ancestor.join(".hg").exists() {
            return Ok(ancestor);
        }
    }
    Err(FindRootError::RootNotFound(start.into()))
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

        let err = find_root_from_path(&path).unwrap_err();

        // TODO do something better
        assert!(match err {
            FindRootError::RootNotFound(p) => p == path.to_path_buf(),
            _ => false,
        })
    }

    #[test]
    fn dot_hg_in_current_path() {
        let tmp_dir = tempfile::tempdir().unwrap();
        let root = tmp_dir.path();
        fs::create_dir_all(root.join(".hg")).unwrap();

        let result = find_root_from_path(&root).unwrap();

        assert_eq!(result, root)
    }

    #[test]
    fn dot_hg_in_parent() {
        let tmp_dir = tempfile::tempdir().unwrap();
        let root = tmp_dir.path();
        fs::create_dir_all(root.join(".hg")).unwrap();

        let directory = root.join("some/nested/directory");
        let result = find_root_from_path(&directory).unwrap();

        assert_eq!(result, root)
    }
} /* tests */

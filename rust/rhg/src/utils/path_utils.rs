// path utils module
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use hg::errors::HgError;
use hg::repo::Repo;
use hg::utils::current_dir;
use hg::utils::files::{get_bytes_from_path, relativize_path};
use hg::utils::hg_path::HgPath;
use hg::utils::hg_path::HgPathBuf;
use std::borrow::Cow;

pub struct RelativizePaths {
    repo_root: HgPathBuf,
    cwd: HgPathBuf,
    outside_repo: bool,
}

impl RelativizePaths {
    pub fn new(repo: &Repo) -> Result<Self, HgError> {
        let cwd = current_dir()?;
        let repo_root = repo.working_directory_path();
        let repo_root = cwd.join(repo_root); // Make it absolute
        let repo_root_hgpath =
            HgPathBuf::from(get_bytes_from_path(repo_root.to_owned()));

        if let Ok(cwd_relative_to_repo) = cwd.strip_prefix(&repo_root) {
            // The current directory is inside the repo, so we can work with
            // relative paths
            Ok(Self {
                repo_root: repo_root_hgpath,
                cwd: HgPathBuf::from(get_bytes_from_path(
                    cwd_relative_to_repo,
                )),
                outside_repo: false,
            })
        } else {
            Ok(Self {
                repo_root: repo_root_hgpath,
                cwd: HgPathBuf::from(get_bytes_from_path(cwd)),
                outside_repo: true,
            })
        }
    }

    pub fn relativize<'a>(&self, path: &'a HgPath) -> Cow<'a, [u8]> {
        if self.outside_repo {
            let joined = self.repo_root.join(path);
            Cow::Owned(relativize_path(&joined, &self.cwd).into_owned())
        } else {
            relativize_path(path, &self.cwd)
        }
    }
}

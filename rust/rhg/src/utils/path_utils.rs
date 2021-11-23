// path utils module
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::error::CommandError;
use crate::ui::UiError;
use hg::errors::HgError;
use hg::repo::Repo;
use hg::utils::current_dir;
use hg::utils::files::{get_bytes_from_path, relativize_path};
use hg::utils::hg_path::HgPath;
use hg::utils::hg_path::HgPathBuf;
use std::borrow::Cow;

pub fn relativize_paths(
    repo: &Repo,
    paths: impl IntoIterator<Item = Result<impl AsRef<HgPath>, HgError>>,
    mut callback: impl FnMut(Cow<[u8]>) -> Result<(), UiError>,
) -> Result<(), CommandError> {
    let cwd = current_dir()?;
    let repo_root = repo.working_directory_path();
    let repo_root = cwd.join(repo_root); // Make it absolute
    let repo_root_hgpath =
        HgPathBuf::from(get_bytes_from_path(repo_root.to_owned()));
    let outside_repo: bool;
    let cwd_hgpath: HgPathBuf;

    if let Ok(cwd_relative_to_repo) = cwd.strip_prefix(&repo_root) {
        // The current directory is inside the repo, so we can work with
        // relative paths
        outside_repo = false;
        cwd_hgpath =
            HgPathBuf::from(get_bytes_from_path(cwd_relative_to_repo));
    } else {
        outside_repo = true;
        cwd_hgpath = HgPathBuf::from(get_bytes_from_path(cwd));
    }

    for file in paths {
        if outside_repo {
            let file = repo_root_hgpath.join(file?.as_ref());
            callback(relativize_path(&file, &cwd_hgpath))?;
        } else {
            callback(relativize_path(file?.as_ref(), &cwd_hgpath))?;
        }
    }
    Ok(())
}

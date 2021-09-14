// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::repo::Repo;
use crate::revlog::revlog::RevlogError;
use crate::revlog::Node;

use crate::utils::hg_path::HgPathBuf;

pub struct CatOutput {
    /// Whether any file in the manifest matched the paths given as CLI
    /// arguments
    pub found_any: bool,
    /// The contents of matching files, in manifest order
    pub concatenated: Vec<u8>,
    /// Which of the CLI arguments did not match any manifest file
    pub missing: Vec<HgPathBuf>,
    /// The node ID that the given revset was resolved to
    pub node: Node,
}

/// Output the given revision of files
///
/// * `root`: Repository root
/// * `rev`: The revision to cat the files from.
/// * `files`: The files to output.
pub fn cat<'a>(
    repo: &Repo,
    revset: &str,
    files: &'a [HgPathBuf],
) -> Result<CatOutput, RevlogError> {
    let rev = crate::revset::resolve_single(revset, repo)?;
    let manifest = repo.manifest_for_rev(rev)?;
    let node = *repo
        .changelog()?
        .node_from_rev(rev)
        .expect("should succeed when repo.manifest did");
    let mut bytes = vec![];
    let mut matched = vec![false; files.len()];
    let mut found_any = false;

    for (manifest_file, node_bytes) in manifest.files_with_nodes() {
        for (cat_file, is_matched) in files.iter().zip(&mut matched) {
            if cat_file.as_bytes() == manifest_file.as_bytes() {
                *is_matched = true;
                found_any = true;
                let file_log = repo.filelog(manifest_file)?;
                let file_node = Node::from_hex_for_repo(node_bytes)?;
                let entry = file_log.data_for_node(file_node)?;
                bytes.extend(entry.data()?)
            }
        }
    }

    let missing: Vec<_> = files
        .iter()
        .zip(&matched)
        .filter(|pair| !*pair.1)
        .map(|pair| pair.0.clone())
        .collect();
    Ok(CatOutput {
        found_any,
        concatenated: bytes,
        missing,
        node,
    })
}

// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::repo::Repo;
use crate::revlog::revlog::RevlogError;
use crate::revlog::Node;

use crate::utils::hg_path::HgPath;
use crate::utils::hg_path::HgPathBuf;

use itertools::put_back;
use itertools::PutBack;
use std::cmp::Ordering;

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

// Find an item in an iterator over a sorted collection.
fn find_item<'a, 'b, 'c, D, I: Iterator<Item = (&'a HgPath, D)>>(
    i: &mut PutBack<I>,
    needle: &'b HgPath,
) -> Option<I::Item> {
    loop {
        match i.next() {
            None => return None,
            Some(val) => match needle.as_bytes().cmp(val.0.as_bytes()) {
                Ordering::Less => {
                    i.put_back(val);
                    return None;
                }
                Ordering::Greater => continue,
                Ordering::Equal => return Some(val),
            },
        }
    }
}

fn find_files_in_manifest<
    'a,
    'b,
    D,
    I: Iterator<Item = (&'a HgPath, D)>,
    J: Iterator<Item = &'b HgPath>,
>(
    manifest: I,
    files: J,
) -> (Vec<(&'a HgPath, D)>, Vec<&'b HgPath>) {
    let mut manifest = put_back(manifest);
    let mut res = vec![];
    let mut missing = vec![];

    for file in files {
        match find_item(&mut manifest, file) {
            None => missing.push(file),
            Some(item) => res.push(item),
        }
    }
    return (res, missing);
}

/// Output the given revision of files
///
/// * `root`: Repository root
/// * `rev`: The revision to cat the files from.
/// * `files`: The files to output.
pub fn cat<'a>(
    repo: &Repo,
    revset: &str,
    mut files: Vec<HgPathBuf>,
) -> Result<CatOutput, RevlogError> {
    let rev = crate::revset::resolve_single(revset, repo)?;
    let manifest = repo.manifest_for_rev(rev)?;
    let node = *repo
        .changelog()?
        .node_from_rev(rev)
        .expect("should succeed when repo.manifest did");
    let mut bytes: Vec<u8> = vec![];
    let mut found_any = false;

    files.sort_unstable();

    let (found, missing) = find_files_in_manifest(
        manifest.files_with_nodes(),
        files.iter().map(|f| f.as_ref()),
    );

    for (manifest_file, node_bytes) in found {
        found_any = true;
        let file_log = repo.filelog(manifest_file)?;
        let file_node = Node::from_hex_for_repo(node_bytes)?;
        bytes.extend(file_log.data_for_node(file_node)?.data()?);
    }

    let missing: Vec<HgPathBuf> = missing
        .iter()
        .map(|file| (*file).to_owned())
        .collect();
    Ok(CatOutput {
        found_any,
        concatenated: bytes,
        missing,
        node,
    })
}

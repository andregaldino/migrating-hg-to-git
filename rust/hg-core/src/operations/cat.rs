// list_tracked_files.rs
//
// Copyright 2020 Antoine Cezar <antoine.cezar@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use std::path::PathBuf;

use crate::repo::Repo;
use crate::revlog::changelog::Changelog;
use crate::revlog::manifest::Manifest;
use crate::revlog::path_encode::path_encode;
use crate::revlog::revlog::Revlog;
use crate::revlog::revlog::RevlogError;
use crate::revlog::Node;
use crate::utils::files::get_path_from_bytes;
use crate::utils::hg_path::{HgPath, HgPathBuf};

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

const METADATA_DELIMITER: [u8; 2] = [b'\x01', b'\n'];

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
    let changelog = Changelog::open(repo)?;
    let manifest = Manifest::open(repo)?;
    let changelog_entry = changelog.get_rev(rev)?;
    let node = *changelog
        .node_from_rev(rev)
        .expect("should succeed when changelog.get_rev did");
    let manifest_node =
        Node::from_hex_for_repo(&changelog_entry.manifest_node()?)?;
    let manifest_entry = manifest.get_node(manifest_node.into())?;
    let mut bytes = vec![];
    let mut matched = vec![false; files.len()];
    let mut found_any = false;

    for (manifest_file, node_bytes) in manifest_entry.files_with_nodes() {
        for (cat_file, is_matched) in files.iter().zip(&mut matched) {
            if cat_file.as_bytes() == manifest_file.as_bytes() {
                *is_matched = true;
                found_any = true;
                let index_path = store_path(manifest_file, b".i");
                let data_path = store_path(manifest_file, b".d");

                let file_log =
                    Revlog::open(repo, &index_path, Some(&data_path))?;
                let file_node = Node::from_hex_for_repo(node_bytes)?;
                let file_rev = file_log.get_node_rev(file_node.into())?;
                let data = file_log.get_rev_data(file_rev)?;
                if data.starts_with(&METADATA_DELIMITER) {
                    let end_delimiter_position = data
                        [METADATA_DELIMITER.len()..]
                        .windows(METADATA_DELIMITER.len())
                        .position(|bytes| bytes == METADATA_DELIMITER);
                    if let Some(position) = end_delimiter_position {
                        let offset = METADATA_DELIMITER.len() * 2;
                        bytes.extend(data[position + offset..].iter());
                    }
                } else {
                    bytes.extend(data);
                }
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

fn store_path(hg_path: &HgPath, suffix: &[u8]) -> PathBuf {
    let encoded_bytes =
        path_encode(&[b"data/", hg_path.as_bytes(), suffix].concat());
    get_path_from_bytes(&encoded_bytes).into()
}

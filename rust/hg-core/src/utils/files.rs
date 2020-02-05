// files.rs
//
// Copyright 2019
// Raphaël Gomès <rgomes@octobus.net>,
// Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Functions for fiddling with files.

use crate::utils::hg_path::{HgPath, HgPathBuf};
use std::iter::FusedIterator;

use crate::utils::replace_slice;
use lazy_static::lazy_static;
use std::fs::Metadata;
use std::path::Path;

pub fn get_path_from_bytes(bytes: &[u8]) -> &Path {
    let os_str;
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        os_str = std::ffi::OsStr::from_bytes(bytes);
    }
    // TODO Handle other platforms
    // TODO: convert from WTF8 to Windows MBCS (ANSI encoding).
    // Perhaps, the return type would have to be Result<PathBuf>.

    Path::new(os_str)
}

// TODO: need to convert from WTF8 to MBCS bytes on Windows.
// that's why Vec<u8> is returned.
#[cfg(unix)]
pub fn get_bytes_from_path(path: impl AsRef<Path>) -> Vec<u8> {
    use std::os::unix::ffi::OsStrExt;
    path.as_ref().as_os_str().as_bytes().to_vec()
}

/// An iterator over repository path yielding itself and its ancestors.
#[derive(Copy, Clone, Debug)]
pub struct Ancestors<'a> {
    next: Option<&'a HgPath>,
}

impl<'a> Iterator for Ancestors<'a> {
    type Item = &'a HgPath;

    fn next(&mut self) -> Option<Self::Item> {
        let next = self.next;
        self.next = match self.next {
            Some(s) if s.is_empty() => None,
            Some(s) => {
                let p = s.bytes().rposition(|c| *c == b'/').unwrap_or(0);
                Some(HgPath::new(&s.as_bytes()[..p]))
            }
            None => None,
        };
        next
    }
}

impl<'a> FusedIterator for Ancestors<'a> {}

/// Returns an iterator yielding ancestor directories of the given repository
/// path.
///
/// The path is separated by '/', and must not start with '/'.
///
/// The path itself isn't included unless it is b"" (meaning the root
/// directory.)
pub fn find_dirs<'a>(path: &'a HgPath) -> Ancestors<'a> {
    let mut dirs = Ancestors { next: Some(path) };
    if !path.is_empty() {
        dirs.next(); // skip itself
    }
    dirs
}

/// TODO more than ASCII?
pub fn normalize_case(path: &HgPath) -> HgPathBuf {
    #[cfg(windows)] // NTFS compares via upper()
    return path.to_ascii_uppercase();
    #[cfg(unix)]
    path.to_ascii_lowercase()
}

lazy_static! {
    static ref IGNORED_CHARS: Vec<Vec<u8>> = {
        [
            0x200c, 0x200d, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d,
            0x202e, 0x206a, 0x206b, 0x206c, 0x206d, 0x206e, 0x206f, 0xfeff,
        ]
        .iter()
        .map(|code| {
            std::char::from_u32(*code)
                .unwrap()
                .encode_utf8(&mut [0; 3])
                .bytes()
                .collect()
        })
        .collect()
    };
}

fn hfs_ignore_clean(bytes: &[u8]) -> Vec<u8> {
    let mut buf = bytes.to_owned();
    let needs_escaping = bytes.iter().any(|b| *b == b'\xe2' || *b == b'\xef');
    if needs_escaping {
        for forbidden in IGNORED_CHARS.iter() {
            replace_slice(&mut buf, forbidden, &[])
        }
        buf
    } else {
        buf
    }
}

pub fn lower_clean(bytes: &[u8]) -> Vec<u8> {
    hfs_ignore_clean(&bytes.to_ascii_lowercase())
}

#[derive(Eq, PartialEq, Ord, PartialOrd, Copy, Clone)]
pub struct HgMetadata {
    pub st_dev: u64,
    pub st_mode: u32,
    pub st_nlink: u64,
    pub st_size: u64,
    pub st_mtime: i64,
    pub st_ctime: i64,
}

// TODO support other plaforms
#[cfg(unix)]
impl HgMetadata {
    pub fn from_metadata(metadata: Metadata) -> Self {
        use std::os::unix::fs::MetadataExt;
        Self {
            st_dev: metadata.dev(),
            st_mode: metadata.mode(),
            st_nlink: metadata.nlink(),
            st_size: metadata.size(),
            st_mtime: metadata.mtime(),
            st_ctime: metadata.ctime(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn find_dirs_some() {
        let mut dirs = super::find_dirs(HgPath::new(b"foo/bar/baz"));
        assert_eq!(dirs.next(), Some(HgPath::new(b"foo/bar")));
        assert_eq!(dirs.next(), Some(HgPath::new(b"foo")));
        assert_eq!(dirs.next(), Some(HgPath::new(b"")));
        assert_eq!(dirs.next(), None);
        assert_eq!(dirs.next(), None);
    }

    #[test]
    fn find_dirs_empty() {
        // looks weird, but mercurial.pathutil.finddirs(b"") yields b""
        let mut dirs = super::find_dirs(HgPath::new(b""));
        assert_eq!(dirs.next(), Some(HgPath::new(b"")));
        assert_eq!(dirs.next(), None);
        assert_eq!(dirs.next(), None);
    }
}

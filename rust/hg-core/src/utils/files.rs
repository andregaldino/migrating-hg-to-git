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
        // looks weird, but mercurial.util.finddirs(b"") yields b""
        let mut dirs = super::find_dirs(HgPath::new(b""));
        assert_eq!(dirs.next(), Some(HgPath::new(b"")));
        assert_eq!(dirs.next(), None);
        assert_eq!(dirs.next(), None);
    }
}

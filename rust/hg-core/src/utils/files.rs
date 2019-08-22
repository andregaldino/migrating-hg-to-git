// files.rs
//
// Copyright 2019
// Raphaël Gomès <rgomes@octobus.net>,
// Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Functions for fiddling with files.

use std::iter::FusedIterator;
use std::path::Path;

pub fn get_path_from_bytes(bytes: &[u8]) -> &Path {
    let os_str;
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        os_str = std::ffi::OsStr::from_bytes(bytes);
    }
    #[cfg(windows)]
    {
        // TODO: convert from Windows MBCS (ANSI encoding) to WTF8.
        // Perhaps, the return type would have to be Result<PathBuf>.
        use std::os::windows::ffi::OsStrExt;
        os_str = std::ffi::OsString::from_wide(bytes);
    }

    Path::new(os_str)
}

/// An iterator over repository path yielding itself and its ancestors.
#[derive(Copy, Clone, Debug)]
pub struct Ancestors<'a> {
    next: Option<&'a [u8]>,
}

impl<'a> Iterator for Ancestors<'a> {
    // if we had an HgPath type, this would yield &'a HgPath
    type Item = &'a [u8];

    fn next(&mut self) -> Option<Self::Item> {
        let next = self.next;
        self.next = match self.next {
            Some(s) if s.is_empty() => None,
            Some(s) => {
                let p = s.iter().rposition(|&c| c == b'/').unwrap_or(0);
                Some(&s[..p])
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
pub fn find_dirs<'a>(path: &'a [u8]) -> Ancestors<'a> {
    let mut dirs = Ancestors { next: Some(path) };
    if !path.is_empty() {
        dirs.next(); // skip itself
    }
    dirs
}

/// TODO improve handling of utf8 file names. Our overall strategy for
/// filenames has to be revisited anyway, since Windows is UTF-16.
pub fn normalize_case(bytes: &[u8]) -> Vec<u8> {
    #[cfg(windows)] // NTFS compares via upper()
    return bytes.to_ascii_uppercase();
    #[cfg(unix)]
    bytes.to_ascii_lowercase()
}

#[cfg(test)]
mod tests {
    #[test]
    fn find_dirs_some() {
        let mut dirs = super::find_dirs(b"foo/bar/baz");
        assert_eq!(dirs.next(), Some(b"foo/bar".as_ref()));
        assert_eq!(dirs.next(), Some(b"foo".as_ref()));
        assert_eq!(dirs.next(), Some(b"".as_ref()));
        assert_eq!(dirs.next(), None);
        assert_eq!(dirs.next(), None);
    }

    #[test]
    fn find_dirs_empty() {
        // looks weird, but mercurial.util.finddirs(b"") yields b""
        let mut dirs = super::find_dirs(b"");
        assert_eq!(dirs.next(), Some(b"".as_ref()));
        assert_eq!(dirs.next(), None);
        assert_eq!(dirs.next(), None);
    }
}

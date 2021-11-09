// files.rs
//
// Copyright 2019
// Raphaël Gomès <rgomes@octobus.net>,
// Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Functions for fiddling with files.

use crate::utils::{
    hg_path::{path_to_hg_path_buf, HgPath, HgPathBuf, HgPathError},
    path_auditor::PathAuditor,
    replace_slice,
};
use lazy_static::lazy_static;
use same_file::is_same_file;
use std::borrow::{Cow, ToOwned};
use std::ffi::{OsStr, OsString};
use std::iter::FusedIterator;
use std::ops::Deref;
use std::path::{Path, PathBuf};

pub fn get_os_str_from_bytes(bytes: &[u8]) -> &OsStr {
    let os_str;
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        os_str = std::ffi::OsStr::from_bytes(bytes);
    }
    // TODO Handle other platforms
    // TODO: convert from WTF8 to Windows MBCS (ANSI encoding).
    // Perhaps, the return type would have to be Result<PathBuf>.
    os_str
}

pub fn get_path_from_bytes(bytes: &[u8]) -> &Path {
    Path::new(get_os_str_from_bytes(bytes))
}

// TODO: need to convert from WTF8 to MBCS bytes on Windows.
// that's why Vec<u8> is returned.
#[cfg(unix)]
pub fn get_bytes_from_path(path: impl AsRef<Path>) -> Vec<u8> {
    get_bytes_from_os_str(path.as_ref())
}

#[cfg(unix)]
pub fn get_bytes_from_os_str(str: impl AsRef<OsStr>) -> Vec<u8> {
    use std::os::unix::ffi::OsStrExt;
    str.as_ref().as_bytes().to_vec()
}

#[cfg(unix)]
pub fn get_bytes_from_os_string(str: OsString) -> Vec<u8> {
    use std::os::unix::ffi::OsStringExt;
    str.into_vec()
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

/// An iterator over repository path yielding itself and its ancestors.
#[derive(Copy, Clone, Debug)]
pub(crate) struct AncestorsWithBase<'a> {
    next: Option<(&'a HgPath, &'a HgPath)>,
}

impl<'a> Iterator for AncestorsWithBase<'a> {
    type Item = (&'a HgPath, &'a HgPath);

    fn next(&mut self) -> Option<Self::Item> {
        let next = self.next;
        self.next = match self.next {
            Some((s, _)) if s.is_empty() => None,
            Some((s, _)) => Some(s.split_filename()),
            None => None,
        };
        next
    }
}

impl<'a> FusedIterator for AncestorsWithBase<'a> {}

/// Returns an iterator yielding ancestor directories of the given repository
/// path.
///
/// The path is separated by '/', and must not start with '/'.
///
/// The path itself isn't included unless it is b"" (meaning the root
/// directory.)
pub fn find_dirs(path: &HgPath) -> Ancestors {
    let mut dirs = Ancestors { next: Some(path) };
    if !path.is_empty() {
        dirs.next(); // skip itself
    }
    dirs
}

/// Returns an iterator yielding ancestor directories of the given repository
/// path.
///
/// The path is separated by '/', and must not start with '/'.
///
/// The path itself isn't included unless it is b"" (meaning the root
/// directory.)
pub(crate) fn find_dirs_with_base(path: &HgPath) -> AncestorsWithBase {
    let mut dirs = AncestorsWithBase {
        next: Some((path, HgPath::new(b""))),
    };
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

/// Returns the canonical path of `name`, given `cwd` and `root`
pub fn canonical_path(
    root: impl AsRef<Path>,
    cwd: impl AsRef<Path>,
    name: impl AsRef<Path>,
) -> Result<PathBuf, HgPathError> {
    // TODO add missing normalization for other platforms
    let root = root.as_ref();
    let cwd = cwd.as_ref();
    let name = name.as_ref();

    let name = if !name.is_absolute() {
        root.join(&cwd).join(&name)
    } else {
        name.to_owned()
    };
    let auditor = PathAuditor::new(&root);
    if name != root && name.starts_with(&root) {
        let name = name.strip_prefix(&root).unwrap();
        auditor.audit_path(path_to_hg_path_buf(name)?)?;
        Ok(name.to_owned())
    } else if name == root {
        Ok("".into())
    } else {
        // Determine whether `name' is in the hierarchy at or beneath `root',
        // by iterating name=name.parent() until it returns `None` (can't
        // check name == '/', because that doesn't work on windows).
        let mut name = name.deref();
        let original_name = name.to_owned();
        loop {
            let same = is_same_file(&name, &root).unwrap_or(false);
            if same {
                if name == original_name {
                    // `name` was actually the same as root (maybe a symlink)
                    return Ok("".into());
                }
                // `name` is a symlink to root, so `original_name` is under
                // root
                let rel_path = original_name.strip_prefix(&name).unwrap();
                auditor.audit_path(path_to_hg_path_buf(&rel_path)?)?;
                return Ok(rel_path.to_owned());
            }
            name = match name.parent() {
                None => break,
                Some(p) => p,
            };
        }
        // TODO hint to the user about using --cwd
        // Bubble up the responsibility to Python for now
        Err(HgPathError::NotUnderRoot {
            path: original_name.to_owned(),
            root: root.to_owned(),
        })
    }
}

/// Returns the representation of the path relative to the current working
/// directory for display purposes.
///
/// `cwd` is a `HgPath`, so it is considered relative to the root directory
/// of the repository.
///
/// # Examples
///
/// ```
/// use hg::utils::hg_path::HgPath;
/// use hg::utils::files::relativize_path;
/// use std::borrow::Cow;
///
/// let file = HgPath::new(b"nested/file");
/// let cwd = HgPath::new(b"");
/// assert_eq!(relativize_path(file, cwd), Cow::Borrowed(b"nested/file"));
///
/// let cwd = HgPath::new(b"nested");
/// assert_eq!(relativize_path(file, cwd), Cow::Borrowed(b"file"));
///
/// let cwd = HgPath::new(b"other");
/// assert_eq!(relativize_path(file, cwd), Cow::Borrowed(b"../nested/file"));
/// ```
pub fn relativize_path(path: &HgPath, cwd: impl AsRef<HgPath>) -> Cow<[u8]> {
    if cwd.as_ref().is_empty() {
        Cow::Borrowed(path.as_bytes())
    } else {
        // This is not all accurate as to how large `res` will actually be, but
        // profiling `rhg files` on a large-ish repo shows it’s better than
        // starting from a zero-capacity `Vec` and letting `extend` reallocate
        // repeatedly.
        let guesstimate = path.as_bytes().len();

        let mut res: Vec<u8> = Vec::with_capacity(guesstimate);
        let mut path_iter = path.as_bytes().split(|b| *b == b'/').peekable();
        let mut cwd_iter =
            cwd.as_ref().as_bytes().split(|b| *b == b'/').peekable();
        loop {
            match (path_iter.peek(), cwd_iter.peek()) {
                (Some(a), Some(b)) if a == b => (),
                _ => break,
            }
            path_iter.next();
            cwd_iter.next();
        }
        let mut need_sep = false;
        for _ in cwd_iter {
            if need_sep {
                res.extend(b"/")
            } else {
                need_sep = true
            };
            res.extend(b"..");
        }
        for c in path_iter {
            if need_sep {
                res.extend(b"/")
            } else {
                need_sep = true
            };
            res.extend(c);
        }
        Cow::Owned(res)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

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

    #[test]
    fn test_find_dirs_with_base_some() {
        let mut dirs = super::find_dirs_with_base(HgPath::new(b"foo/bar/baz"));
        assert_eq!(
            dirs.next(),
            Some((HgPath::new(b"foo/bar"), HgPath::new(b"baz")))
        );
        assert_eq!(
            dirs.next(),
            Some((HgPath::new(b"foo"), HgPath::new(b"bar")))
        );
        assert_eq!(dirs.next(), Some((HgPath::new(b""), HgPath::new(b"foo"))));
        assert_eq!(dirs.next(), None);
        assert_eq!(dirs.next(), None);
    }

    #[test]
    fn test_find_dirs_with_base_empty() {
        let mut dirs = super::find_dirs_with_base(HgPath::new(b""));
        assert_eq!(dirs.next(), Some((HgPath::new(b""), HgPath::new(b""))));
        assert_eq!(dirs.next(), None);
        assert_eq!(dirs.next(), None);
    }

    #[test]
    fn test_canonical_path() {
        let root = Path::new("/repo");
        let cwd = Path::new("/dir");
        let name = Path::new("filename");
        assert_eq!(
            canonical_path(root, cwd, name),
            Err(HgPathError::NotUnderRoot {
                path: PathBuf::from("/dir/filename"),
                root: root.to_path_buf()
            })
        );

        let root = Path::new("/repo");
        let cwd = Path::new("/");
        let name = Path::new("filename");
        assert_eq!(
            canonical_path(root, cwd, name),
            Err(HgPathError::NotUnderRoot {
                path: PathBuf::from("/filename"),
                root: root.to_path_buf()
            })
        );

        let root = Path::new("/repo");
        let cwd = Path::new("/");
        let name = Path::new("repo/filename");
        assert_eq!(
            canonical_path(root, cwd, name),
            Ok(PathBuf::from("filename"))
        );

        let root = Path::new("/repo");
        let cwd = Path::new("/repo");
        let name = Path::new("filename");
        assert_eq!(
            canonical_path(root, cwd, name),
            Ok(PathBuf::from("filename"))
        );

        let root = Path::new("/repo");
        let cwd = Path::new("/repo/subdir");
        let name = Path::new("filename");
        assert_eq!(
            canonical_path(root, cwd, name),
            Ok(PathBuf::from("subdir/filename"))
        );
    }

    #[test]
    fn test_canonical_path_not_rooted() {
        use std::fs::create_dir;
        use tempfile::tempdir;

        let base_dir = tempdir().unwrap();
        let base_dir_path = base_dir.path();
        let beneath_repo = base_dir_path.join("a");
        let root = base_dir_path.join("a/b");
        let out_of_repo = base_dir_path.join("c");
        let under_repo_symlink = out_of_repo.join("d");

        create_dir(&beneath_repo).unwrap();
        create_dir(&root).unwrap();

        // TODO make portable
        std::os::unix::fs::symlink(&root, &out_of_repo).unwrap();

        assert_eq!(
            canonical_path(&root, Path::new(""), out_of_repo),
            Ok(PathBuf::from(""))
        );
        assert_eq!(
            canonical_path(&root, Path::new(""), &beneath_repo),
            Err(HgPathError::NotUnderRoot {
                path: beneath_repo.to_owned(),
                root: root.to_owned()
            })
        );
        assert_eq!(
            canonical_path(&root, Path::new(""), &under_repo_symlink),
            Ok(PathBuf::from("d"))
        );
    }
}

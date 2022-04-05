// hg_path.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::utils::SliceExt;
use std::borrow::Borrow;
use std::borrow::Cow;
use std::convert::TryFrom;
use std::ffi::{OsStr, OsString};
use std::fmt;
use std::ops::Deref;
use std::path::{Path, PathBuf};

#[derive(Debug, Eq, PartialEq)]
pub enum HgPathError {
    /// Bytes from the invalid `HgPath`
    LeadingSlash(Vec<u8>),
    ConsecutiveSlashes {
        bytes: Vec<u8>,
        second_slash_index: usize,
    },
    ContainsNullByte {
        bytes: Vec<u8>,
        null_byte_index: usize,
    },
    /// Bytes
    DecodeError(Vec<u8>),
    /// The rest come from audit errors
    EndsWithSlash(HgPathBuf),
    ContainsIllegalComponent(HgPathBuf),
    /// Path is inside the `.hg` folder
    InsideDotHg(HgPathBuf),
    IsInsideNestedRepo {
        path: HgPathBuf,
        nested_repo: HgPathBuf,
    },
    TraversesSymbolicLink {
        path: HgPathBuf,
        symlink: HgPathBuf,
    },
    NotFsCompliant(HgPathBuf),
    /// `path` is the smallest invalid path
    NotUnderRoot {
        path: PathBuf,
        root: PathBuf,
    },
}

impl fmt::Display for HgPathError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            HgPathError::LeadingSlash(bytes) => {
                write!(f, "Invalid HgPath '{:?}': has a leading slash.", bytes)
            }
            HgPathError::ConsecutiveSlashes {
                bytes,
                second_slash_index: pos,
            } => write!(
                f,
                "Invalid HgPath '{:?}': consecutive slashes at pos {}.",
                bytes, pos
            ),
            HgPathError::ContainsNullByte {
                bytes,
                null_byte_index: pos,
            } => write!(
                f,
                "Invalid HgPath '{:?}': contains null byte at pos {}.",
                bytes, pos
            ),
            HgPathError::DecodeError(bytes) => write!(
                f,
                "Invalid HgPath '{:?}': could not be decoded.",
                bytes
            ),
            HgPathError::EndsWithSlash(path) => {
                write!(f, "Audit failed for '{}': ends with a slash.", path)
            }
            HgPathError::ContainsIllegalComponent(path) => write!(
                f,
                "Audit failed for '{}': contains an illegal component.",
                path
            ),
            HgPathError::InsideDotHg(path) => write!(
                f,
                "Audit failed for '{}': is inside the '.hg' folder.",
                path
            ),
            HgPathError::IsInsideNestedRepo {
                path,
                nested_repo: nested,
            } => {
                write!(f,
                "Audit failed for '{}': is inside a nested repository '{}'.",
                path, nested
            )
            }
            HgPathError::TraversesSymbolicLink { path, symlink } => write!(
                f,
                "Audit failed for '{}': traverses symbolic link '{}'.",
                path, symlink
            ),
            HgPathError::NotFsCompliant(path) => write!(
                f,
                "Audit failed for '{}': cannot be turned into a \
                 filesystem path.",
                path
            ),
            HgPathError::NotUnderRoot { path, root } => write!(
                f,
                "Audit failed for '{}': not under root {}.",
                path.display(),
                root.display()
            ),
        }
    }
}

impl From<HgPathError> for std::io::Error {
    fn from(e: HgPathError) -> Self {
        std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())
    }
}

/// This is a repository-relative path (or canonical path):
///     - no null characters
///     - `/` separates directories
///     - no consecutive slashes
///     - no leading slash,
///     - no `.` nor `..` of special meaning
///     - stored in repository and shared across platforms
///
/// Note: there is no guarantee of any `HgPath` being well-formed at any point
/// in its lifetime for performance reasons and to ease ergonomics. It is
/// however checked using the `check_state` method before any file-system
/// operation.
///
/// This allows us to be encoding-transparent as much as possible, until really
/// needed; `HgPath` can be transformed into a platform-specific path (`OsStr`
/// or `Path`) whenever more complex operations are needed:
/// On Unix, it's just byte-to-byte conversion. On Windows, it has to be
/// decoded from MBCS to WTF-8. If WindowsUTF8Plan is implemented, the source
/// character encoding will be determined on a per-repository basis.
#[derive(Eq, Ord, PartialEq, PartialOrd, Hash)]
#[repr(transparent)]
pub struct HgPath {
    inner: [u8],
}

impl HgPath {
    pub fn new<S: AsRef<[u8]> + ?Sized>(s: &S) -> &Self {
        unsafe { &*(s.as_ref() as *const [u8] as *const Self) }
    }
    pub fn is_empty(&self) -> bool {
        self.inner.is_empty()
    }
    pub fn len(&self) -> usize {
        self.inner.len()
    }
    fn to_hg_path_buf(&self) -> HgPathBuf {
        HgPathBuf {
            inner: self.inner.to_owned(),
        }
    }
    pub fn bytes(&self) -> std::slice::Iter<u8> {
        self.inner.iter()
    }
    pub fn to_ascii_uppercase(&self) -> HgPathBuf {
        HgPathBuf::from(self.inner.to_ascii_uppercase())
    }
    pub fn to_ascii_lowercase(&self) -> HgPathBuf {
        HgPathBuf::from(self.inner.to_ascii_lowercase())
    }
    pub fn as_bytes(&self) -> &[u8] {
        &self.inner
    }
    pub fn contains(&self, other: u8) -> bool {
        self.inner.contains(&other)
    }
    pub fn starts_with(&self, needle: impl AsRef<Self>) -> bool {
        self.inner.starts_with(needle.as_ref().as_bytes())
    }
    pub fn trim_trailing_slash(&self) -> &Self {
        Self::new(if self.inner.last() == Some(&b'/') {
            &self.inner[..self.inner.len() - 1]
        } else {
            &self.inner[..]
        })
    }
    /// Returns a tuple of slices `(base, filename)` resulting from the split
    /// at the rightmost `/`, if any.
    ///
    /// # Examples:
    ///
    /// ```
    /// use hg::utils::hg_path::HgPath;
    ///
    /// let path = HgPath::new(b"cool/hg/path").split_filename();
    /// assert_eq!(path, (HgPath::new(b"cool/hg"), HgPath::new(b"path")));
    ///
    /// let path = HgPath::new(b"pathwithoutsep").split_filename();
    /// assert_eq!(path, (HgPath::new(b""), HgPath::new(b"pathwithoutsep")));
    /// ```
    pub fn split_filename(&self) -> (&Self, &Self) {
        match &self.inner.iter().rposition(|c| *c == b'/') {
            None => (HgPath::new(""), &self),
            Some(size) => (
                HgPath::new(&self.inner[..*size]),
                HgPath::new(&self.inner[*size + 1..]),
            ),
        }
    }

    pub fn join(&self, path: &HgPath) -> HgPathBuf {
        let mut buf = self.to_owned();
        buf.push(path);
        buf
    }

    pub fn components(&self) -> impl Iterator<Item = &HgPath> {
        self.inner.split(|&byte| byte == b'/').map(HgPath::new)
    }

    /// Returns the first (that is "root-most") slash-separated component of
    /// the path, and the rest after the first slash if there is one.
    pub fn split_first_component(&self) -> (&HgPath, Option<&HgPath>) {
        match self.inner.split_2(b'/') {
            Some((a, b)) => (HgPath::new(a), Some(HgPath::new(b))),
            None => (self, None),
        }
    }

    pub fn parent(&self) -> &Self {
        let inner = self.as_bytes();
        HgPath::new(match inner.iter().rposition(|b| *b == b'/') {
            Some(pos) => &inner[..pos],
            None => &[],
        })
    }
    /// Given a base directory, returns the slice of `self` relative to the
    /// base directory. If `base` is not a directory (does not end with a
    /// `b'/'`), returns `None`.
    pub fn relative_to(&self, base: impl AsRef<Self>) -> Option<&Self> {
        let base = base.as_ref();
        if base.is_empty() {
            return Some(self);
        }
        let is_dir = base.as_bytes().ends_with(b"/");
        if is_dir && self.starts_with(base) {
            Some(Self::new(&self.inner[base.len()..]))
        } else {
            None
        }
    }

    #[cfg(windows)]
    /// Copied from the Python stdlib's `os.path.splitdrive` implementation.
    ///
    /// Split a pathname into drive/UNC sharepoint and relative path
    /// specifiers. Returns a 2-tuple (drive_or_unc, path); either part may
    /// be empty.
    ///
    /// If you assign
    ///  result = split_drive(p)
    /// It is always true that:
    ///  result[0] + result[1] == p
    ///
    /// If the path contained a drive letter, drive_or_unc will contain
    /// everything up to and including the colon.
    /// e.g. split_drive("c:/dir") returns ("c:", "/dir")
    ///
    /// If the path contained a UNC path, the drive_or_unc will contain the
    /// host name and share up to but not including the fourth directory
    /// separator character.
    /// e.g. split_drive("//host/computer/dir") returns ("//host/computer",
    /// "/dir")
    ///
    /// Paths cannot contain both a drive letter and a UNC path.
    pub fn split_drive<'a>(&self) -> (&HgPath, &HgPath) {
        let bytes = self.as_bytes();
        let is_sep = |b| std::path::is_separator(b as char);

        if self.len() < 2 {
            (HgPath::new(b""), &self)
        } else if is_sep(bytes[0])
            && is_sep(bytes[1])
            && (self.len() == 2 || !is_sep(bytes[2]))
        {
            // Is a UNC path:
            // vvvvvvvvvvvvvvvvvvvv drive letter or UNC path
            // \\machine\mountpoint\directory\etc\...
            //           directory ^^^^^^^^^^^^^^^

            let machine_end_index = bytes[2..].iter().position(|b| is_sep(*b));
            let mountpoint_start_index = if let Some(i) = machine_end_index {
                i + 2
            } else {
                return (HgPath::new(b""), &self);
            };

            match bytes[mountpoint_start_index + 1..]
                .iter()
                .position(|b| is_sep(*b))
            {
                // A UNC path can't have two slashes in a row
                // (after the initial two)
                Some(0) => (HgPath::new(b""), &self),
                Some(i) => {
                    let (a, b) =
                        bytes.split_at(mountpoint_start_index + 1 + i);
                    (HgPath::new(a), HgPath::new(b))
                }
                None => (&self, HgPath::new(b"")),
            }
        } else if bytes[1] == b':' {
            // Drive path c:\directory
            let (a, b) = bytes.split_at(2);
            (HgPath::new(a), HgPath::new(b))
        } else {
            (HgPath::new(b""), &self)
        }
    }

    #[cfg(unix)]
    /// Split a pathname into drive and path. On Posix, drive is always empty.
    pub fn split_drive(&self) -> (&HgPath, &HgPath) {
        (HgPath::new(b""), &self)
    }

    /// Checks for errors in the path, short-circuiting at the first one.
    /// This generates fine-grained errors useful for debugging.
    /// To simply check if the path is valid during tests, use `is_valid`.
    pub fn check_state(&self) -> Result<(), HgPathError> {
        if self.is_empty() {
            return Ok(());
        }
        let bytes = self.as_bytes();
        let mut previous_byte = None;

        if bytes[0] == b'/' {
            return Err(HgPathError::LeadingSlash(bytes.to_vec()));
        }
        for (index, byte) in bytes.iter().enumerate() {
            match byte {
                0 => {
                    return Err(HgPathError::ContainsNullByte {
                        bytes: bytes.to_vec(),
                        null_byte_index: index,
                    })
                }
                b'/' => {
                    if previous_byte.is_some() && previous_byte == Some(b'/') {
                        return Err(HgPathError::ConsecutiveSlashes {
                            bytes: bytes.to_vec(),
                            second_slash_index: index,
                        });
                    }
                }
                _ => (),
            };
            previous_byte = Some(*byte);
        }
        Ok(())
    }

    #[cfg(test)]
    /// Only usable during tests to force developers to handle invalid states
    fn is_valid(&self) -> bool {
        self.check_state().is_ok()
    }
}

impl fmt::Debug for HgPath {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "HgPath({:?})", String::from_utf8_lossy(&self.inner))
    }
}

impl fmt::Display for HgPath {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", String::from_utf8_lossy(&self.inner))
    }
}

#[derive(
    Default, Eq, Ord, Clone, PartialEq, PartialOrd, Hash, derive_more::From,
)]
pub struct HgPathBuf {
    inner: Vec<u8>,
}

impl HgPathBuf {
    pub fn new() -> Self {
        Default::default()
    }

    pub fn push<T: ?Sized + AsRef<HgPath>>(&mut self, other: &T) -> () {
        if !self.inner.is_empty() && self.inner.last() != Some(&b'/') {
            self.inner.push(b'/');
        }
        self.inner.extend(other.as_ref().bytes())
    }

    pub fn push_byte(&mut self, byte: u8) {
        self.inner.push(byte);
    }
    pub fn from_bytes(s: &[u8]) -> HgPathBuf {
        HgPath::new(s).to_owned()
    }
    pub fn into_vec(self) -> Vec<u8> {
        self.inner
    }
}

impl fmt::Debug for HgPathBuf {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "HgPathBuf({:?})", String::from_utf8_lossy(&self.inner))
    }
}

impl fmt::Display for HgPathBuf {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", String::from_utf8_lossy(&self.inner))
    }
}

impl Deref for HgPathBuf {
    type Target = HgPath;

    #[inline]
    fn deref(&self) -> &HgPath {
        &HgPath::new(&self.inner)
    }
}

impl<T: ?Sized + AsRef<HgPath>> From<&T> for HgPathBuf {
    fn from(s: &T) -> HgPathBuf {
        s.as_ref().to_owned()
    }
}

impl Into<Vec<u8>> for HgPathBuf {
    fn into(self) -> Vec<u8> {
        self.inner
    }
}

impl Borrow<HgPath> for HgPathBuf {
    fn borrow(&self) -> &HgPath {
        &HgPath::new(self.as_bytes())
    }
}

impl ToOwned for HgPath {
    type Owned = HgPathBuf;

    fn to_owned(&self) -> HgPathBuf {
        self.to_hg_path_buf()
    }
}

impl AsRef<HgPath> for HgPath {
    fn as_ref(&self) -> &HgPath {
        self
    }
}

impl AsRef<HgPath> for HgPathBuf {
    fn as_ref(&self) -> &HgPath {
        self
    }
}

impl Extend<u8> for HgPathBuf {
    fn extend<T: IntoIterator<Item = u8>>(&mut self, iter: T) {
        self.inner.extend(iter);
    }
}

/// TODO: Once https://www.mercurial-scm.org/wiki/WindowsUTF8Plan is
/// implemented, these conversion utils will have to work differently depending
/// on the repository encoding: either `UTF-8` or `MBCS`.

pub fn hg_path_to_os_string<P: AsRef<HgPath>>(
    hg_path: P,
) -> Result<OsString, HgPathError> {
    hg_path.as_ref().check_state()?;
    let os_str;
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        os_str = std::ffi::OsStr::from_bytes(&hg_path.as_ref().as_bytes());
    }
    // TODO Handle other platforms
    // TODO: convert from WTF8 to Windows MBCS (ANSI encoding).
    Ok(os_str.to_os_string())
}

pub fn hg_path_to_path_buf<P: AsRef<HgPath>>(
    hg_path: P,
) -> Result<PathBuf, HgPathError> {
    Ok(Path::new(&hg_path_to_os_string(hg_path)?).to_path_buf())
}

pub fn os_string_to_hg_path_buf<S: AsRef<OsStr>>(
    os_string: S,
) -> Result<HgPathBuf, HgPathError> {
    let buf;
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        buf = HgPathBuf::from_bytes(&os_string.as_ref().as_bytes());
    }
    // TODO Handle other platforms
    // TODO: convert from WTF8 to Windows MBCS (ANSI encoding).

    buf.check_state()?;
    Ok(buf)
}

pub fn path_to_hg_path_buf<P: AsRef<Path>>(
    path: P,
) -> Result<HgPathBuf, HgPathError> {
    let buf;
    let os_str = path.as_ref().as_os_str();
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        buf = HgPathBuf::from_bytes(&os_str.as_bytes());
    }
    // TODO Handle other platforms
    // TODO: convert from WTF8 to Windows MBCS (ANSI encoding).

    buf.check_state()?;
    Ok(buf)
}

impl TryFrom<PathBuf> for HgPathBuf {
    type Error = HgPathError;
    fn try_from(path: PathBuf) -> Result<Self, Self::Error> {
        path_to_hg_path_buf(path)
    }
}

impl From<HgPathBuf> for Cow<'_, HgPath> {
    fn from(path: HgPathBuf) -> Self {
        Cow::Owned(path)
    }
}

impl<'a> From<&'a HgPath> for Cow<'a, HgPath> {
    fn from(path: &'a HgPath) -> Self {
        Cow::Borrowed(path)
    }
}

impl<'a> From<&'a HgPathBuf> for Cow<'a, HgPath> {
    fn from(path: &'a HgPathBuf) -> Self {
        Cow::Borrowed(&**path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn test_path_states() {
        assert_eq!(
            Err(HgPathError::LeadingSlash(b"/".to_vec())),
            HgPath::new(b"/").check_state()
        );
        assert_eq!(
            Err(HgPathError::ConsecutiveSlashes {
                bytes: b"a/b//c".to_vec(),
                second_slash_index: 4
            }),
            HgPath::new(b"a/b//c").check_state()
        );
        assert_eq!(
            Err(HgPathError::ContainsNullByte {
                bytes: b"a/b/\0c".to_vec(),
                null_byte_index: 4
            }),
            HgPath::new(b"a/b/\0c").check_state()
        );
        // TODO test HgPathError::DecodeError for the Windows implementation.
        assert_eq!(true, HgPath::new(b"").is_valid());
        assert_eq!(true, HgPath::new(b"a/b/c").is_valid());
        // Backslashes in paths are not significant, but allowed
        assert_eq!(true, HgPath::new(br"a\b/c").is_valid());
        // Dots in paths are not significant, but allowed
        assert_eq!(true, HgPath::new(b"a/b/../c/").is_valid());
        assert_eq!(true, HgPath::new(b"./a/b/../c/").is_valid());
    }

    #[test]
    fn test_iter() {
        let path = HgPath::new(b"a");
        let mut iter = path.bytes();
        assert_eq!(Some(&b'a'), iter.next());
        assert_eq!(None, iter.next_back());
        assert_eq!(None, iter.next());

        let path = HgPath::new(b"a");
        let mut iter = path.bytes();
        assert_eq!(Some(&b'a'), iter.next_back());
        assert_eq!(None, iter.next_back());
        assert_eq!(None, iter.next());

        let path = HgPath::new(b"abc");
        let mut iter = path.bytes();
        assert_eq!(Some(&b'a'), iter.next());
        assert_eq!(Some(&b'c'), iter.next_back());
        assert_eq!(Some(&b'b'), iter.next_back());
        assert_eq!(None, iter.next_back());
        assert_eq!(None, iter.next());

        let path = HgPath::new(b"abc");
        let mut iter = path.bytes();
        assert_eq!(Some(&b'a'), iter.next());
        assert_eq!(Some(&b'b'), iter.next());
        assert_eq!(Some(&b'c'), iter.next());
        assert_eq!(None, iter.next_back());
        assert_eq!(None, iter.next());

        let path = HgPath::new(b"abc");
        let iter = path.bytes();
        let mut vec = Vec::new();
        vec.extend(iter);
        assert_eq!(vec![b'a', b'b', b'c'], vec);

        let path = HgPath::new(b"abc");
        let mut iter = path.bytes();
        assert_eq!(Some(2), iter.rposition(|c| *c == b'c'));

        let path = HgPath::new(b"abc");
        let mut iter = path.bytes();
        assert_eq!(None, iter.rposition(|c| *c == b'd'));
    }

    #[test]
    fn test_join() {
        let path = HgPathBuf::from_bytes(b"a").join(HgPath::new(b"b"));
        assert_eq!(b"a/b", path.as_bytes());

        let path = HgPathBuf::from_bytes(b"a/").join(HgPath::new(b"b/c"));
        assert_eq!(b"a/b/c", path.as_bytes());

        // No leading slash if empty before join
        let path = HgPathBuf::new().join(HgPath::new(b"b/c"));
        assert_eq!(b"b/c", path.as_bytes());

        // The leading slash is an invalid representation of an `HgPath`, but
        // it can happen. This creates another invalid representation of
        // consecutive bytes.
        // TODO What should be done in this case? Should we silently remove
        // the extra slash? Should we change the signature to a problematic
        // `Result<HgPathBuf, HgPathError>`, or should we just keep it so and
        // let the error happen upon filesystem interaction?
        let path = HgPathBuf::from_bytes(b"a/").join(HgPath::new(b"/b"));
        assert_eq!(b"a//b", path.as_bytes());
        let path = HgPathBuf::from_bytes(b"a").join(HgPath::new(b"/b"));
        assert_eq!(b"a//b", path.as_bytes());
    }

    #[test]
    fn test_relative_to() {
        let path = HgPath::new(b"");
        let base = HgPath::new(b"");
        assert_eq!(Some(path), path.relative_to(base));

        let path = HgPath::new(b"path");
        let base = HgPath::new(b"");
        assert_eq!(Some(path), path.relative_to(base));

        let path = HgPath::new(b"a");
        let base = HgPath::new(b"b");
        assert_eq!(None, path.relative_to(base));

        let path = HgPath::new(b"a/b");
        let base = HgPath::new(b"a");
        assert_eq!(None, path.relative_to(base));

        let path = HgPath::new(b"a/b");
        let base = HgPath::new(b"a/");
        assert_eq!(Some(HgPath::new(b"b")), path.relative_to(base));

        let path = HgPath::new(b"nested/path/to/b");
        let base = HgPath::new(b"nested/path/");
        assert_eq!(Some(HgPath::new(b"to/b")), path.relative_to(base));

        let path = HgPath::new(b"ends/with/dir/");
        let base = HgPath::new(b"ends/");
        assert_eq!(Some(HgPath::new(b"with/dir/")), path.relative_to(base));
    }

    #[test]
    #[cfg(unix)]
    fn test_split_drive() {
        // Taken from the Python stdlib's tests
        assert_eq!(
            HgPath::new(br"/foo/bar").split_drive(),
            (HgPath::new(b""), HgPath::new(br"/foo/bar"))
        );
        assert_eq!(
            HgPath::new(br"foo:bar").split_drive(),
            (HgPath::new(b""), HgPath::new(br"foo:bar"))
        );
        assert_eq!(
            HgPath::new(br":foo:bar").split_drive(),
            (HgPath::new(b""), HgPath::new(br":foo:bar"))
        );
        // Also try NT paths; should not split them
        assert_eq!(
            HgPath::new(br"c:\foo\bar").split_drive(),
            (HgPath::new(b""), HgPath::new(br"c:\foo\bar"))
        );
        assert_eq!(
            HgPath::new(b"c:/foo/bar").split_drive(),
            (HgPath::new(b""), HgPath::new(br"c:/foo/bar"))
        );
        assert_eq!(
            HgPath::new(br"\\conky\mountpoint\foo\bar").split_drive(),
            (
                HgPath::new(b""),
                HgPath::new(br"\\conky\mountpoint\foo\bar")
            )
        );
    }

    #[test]
    #[cfg(windows)]
    fn test_split_drive() {
        assert_eq!(
            HgPath::new(br"c:\foo\bar").split_drive(),
            (HgPath::new(br"c:"), HgPath::new(br"\foo\bar"))
        );
        assert_eq!(
            HgPath::new(b"c:/foo/bar").split_drive(),
            (HgPath::new(br"c:"), HgPath::new(br"/foo/bar"))
        );
        assert_eq!(
            HgPath::new(br"\\conky\mountpoint\foo\bar").split_drive(),
            (
                HgPath::new(br"\\conky\mountpoint"),
                HgPath::new(br"\foo\bar")
            )
        );
        assert_eq!(
            HgPath::new(br"//conky/mountpoint/foo/bar").split_drive(),
            (
                HgPath::new(br"//conky/mountpoint"),
                HgPath::new(br"/foo/bar")
            )
        );
        assert_eq!(
            HgPath::new(br"\\\conky\mountpoint\foo\bar").split_drive(),
            (
                HgPath::new(br""),
                HgPath::new(br"\\\conky\mountpoint\foo\bar")
            )
        );
        assert_eq!(
            HgPath::new(br"///conky/mountpoint/foo/bar").split_drive(),
            (
                HgPath::new(br""),
                HgPath::new(br"///conky/mountpoint/foo/bar")
            )
        );
        assert_eq!(
            HgPath::new(br"\\conky\\mountpoint\foo\bar").split_drive(),
            (
                HgPath::new(br""),
                HgPath::new(br"\\conky\\mountpoint\foo\bar")
            )
        );
        assert_eq!(
            HgPath::new(br"//conky//mountpoint/foo/bar").split_drive(),
            (
                HgPath::new(br""),
                HgPath::new(br"//conky//mountpoint/foo/bar")
            )
        );
        // UNC part containing U+0130
        assert_eq!(
            HgPath::new(b"//conky/MOUNTPO\xc4\xb0NT/foo/bar").split_drive(),
            (
                HgPath::new(b"//conky/MOUNTPO\xc4\xb0NT"),
                HgPath::new(br"/foo/bar")
            )
        );
    }

    #[test]
    fn test_parent() {
        let path = HgPath::new(b"");
        assert_eq!(path.parent(), path);

        let path = HgPath::new(b"a");
        assert_eq!(path.parent(), HgPath::new(b""));

        let path = HgPath::new(b"a/b");
        assert_eq!(path.parent(), HgPath::new(b"a"));

        let path = HgPath::new(b"a/other/b");
        assert_eq!(path.parent(), HgPath::new(b"a/other"));
    }
}

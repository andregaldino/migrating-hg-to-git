// hg_path.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use std::borrow::Borrow;
use std::ffi::{OsStr, OsString};
use std::ops::Deref;
use std::path::{Path, PathBuf};

#[derive(Debug, Eq, PartialEq)]
pub enum HgPathError {
    /// Bytes from the invalid `HgPath`
    LeadingSlash(Vec<u8>),
    /// Bytes and index of the second slash
    ConsecutiveSlashes(Vec<u8>, usize),
    /// Bytes and index of the null byte
    ContainsNullByte(Vec<u8>, usize),
    /// Bytes
    DecodeError(Vec<u8>),
}

impl ToString for HgPathError {
    fn to_string(&self) -> String {
        match self {
            HgPathError::LeadingSlash(bytes) => {
                format!("Invalid HgPath '{:?}': has a leading slash.", bytes)
            }
            HgPathError::ConsecutiveSlashes(bytes, pos) => format!(
                "Invalid HgPath '{:?}': consecutive slahes at pos {}.",
                bytes, pos
            ),
            HgPathError::ContainsNullByte(bytes, pos) => format!(
                "Invalid HgPath '{:?}': contains null byte at pos {}.",
                bytes, pos
            ),
            HgPathError::DecodeError(bytes) => {
                format!("Invalid HgPath '{:?}': could not be decoded.", bytes)
            }
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
//
// FIXME: (adapted from a comment in the stdlib)
// `HgPath::new()` current implementation relies on `Slice` being
// layout-compatible with `[u8]`.
// When attribute privacy is implemented, `Slice` should be annotated as
// `#[repr(transparent)]`.
// Anyway, `Slice` representation and layout are considered implementation
// detail, are not documented and must not be relied upon.
#[derive(Eq, Ord, PartialEq, PartialOrd, Debug, Hash)]
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
    pub fn join<T: ?Sized + AsRef<HgPath>>(&self, other: &T) -> HgPathBuf {
        let mut inner = self.inner.to_owned();
        if inner.len() != 0 && inner.last() != Some(&b'/') {
            inner.push(b'/');
        }
        inner.extend(other.as_ref().bytes());
        HgPathBuf::from_bytes(&inner)
    }
    /// Checks for errors in the path, short-circuiting at the first one.
    /// This generates fine-grained errors useful for debugging.
    /// To simply check if the path is valid during tests, use `is_valid`.
    pub fn check_state(&self) -> Result<(), HgPathError> {
        if self.len() == 0 {
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
                    return Err(HgPathError::ContainsNullByte(
                        bytes.to_vec(),
                        index,
                    ))
                }
                b'/' => {
                    if previous_byte.is_some() && previous_byte == Some(b'/') {
                        return Err(HgPathError::ConsecutiveSlashes(
                            bytes.to_vec(),
                            index,
                        ));
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

#[derive(Eq, Ord, Clone, PartialEq, PartialOrd, Debug, Hash)]
pub struct HgPathBuf {
    inner: Vec<u8>,
}

impl HgPathBuf {
    pub fn new() -> Self {
        Self { inner: Vec::new() }
    }
    pub fn push(&mut self, byte: u8) {
        self.inner.push(byte);
    }
    pub fn from_bytes(s: &[u8]) -> HgPathBuf {
        HgPath::new(s).to_owned()
    }
    pub fn into_vec(self) -> Vec<u8> {
        self.inner
    }
    pub fn as_ref(&self) -> &[u8] {
        self.inner.as_ref()
    }
}

impl Deref for HgPathBuf {
    type Target = HgPath;

    #[inline]
    fn deref(&self) -> &HgPath {
        &HgPath::new(&self.inner)
    }
}

impl From<Vec<u8>> for HgPathBuf {
    fn from(vec: Vec<u8>) -> Self {
        Self { inner: vec }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_path_states() {
        assert_eq!(
            Err(HgPathError::LeadingSlash(b"/".to_vec())),
            HgPath::new(b"/").check_state()
        );
        assert_eq!(
            Err(HgPathError::ConsecutiveSlashes(b"a/b//c".to_vec(), 4)),
            HgPath::new(b"a/b//c").check_state()
        );
        assert_eq!(
            Err(HgPathError::ContainsNullByte(b"a/b/\0c".to_vec(), 4)),
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
}

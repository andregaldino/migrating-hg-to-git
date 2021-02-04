// utils module
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Contains useful functions, traits, structs, etc. for use in core.

use crate::errors::{HgError, IoErrorContext};
use crate::utils::hg_path::HgPath;
use std::{io::Write, ops::Deref};

pub mod files;
pub mod hg_path;
pub mod path_auditor;

/// Useful until rust/issues/56345 is stable
///
/// # Examples
///
/// ```
/// use crate::hg::utils::find_slice_in_slice;
///
/// let haystack = b"This is the haystack".to_vec();
/// assert_eq!(find_slice_in_slice(&haystack, b"the"), Some(8));
/// assert_eq!(find_slice_in_slice(&haystack, b"not here"), None);
/// ```
pub fn find_slice_in_slice<T>(slice: &[T], needle: &[T]) -> Option<usize>
where
    for<'a> &'a [T]: PartialEq,
{
    slice
        .windows(needle.len())
        .position(|window| window == needle)
}

/// Replaces the `from` slice with the `to` slice inside the `buf` slice.
///
/// # Examples
///
/// ```
/// use crate::hg::utils::replace_slice;
/// let mut line = b"I hate writing tests!".to_vec();
/// replace_slice(&mut line, b"hate", b"love");
/// assert_eq!(
///     line,
///     b"I love writing tests!".to_vec()
/// );
/// ```
pub fn replace_slice<T>(buf: &mut [T], from: &[T], to: &[T])
where
    T: Clone + PartialEq,
{
    if buf.len() < from.len() || from.len() != to.len() {
        return;
    }
    for i in 0..=buf.len() - from.len() {
        if buf[i..].starts_with(from) {
            buf[i..(i + from.len())].clone_from_slice(to);
        }
    }
}

pub trait SliceExt {
    fn trim_end(&self) -> &Self;
    fn trim_start(&self) -> &Self;
    fn trim(&self) -> &Self;
    fn drop_prefix(&self, needle: &Self) -> Option<&Self>;
}

#[allow(clippy::trivially_copy_pass_by_ref)]
fn is_not_whitespace(c: &u8) -> bool {
    !(*c as char).is_whitespace()
}

impl SliceExt for [u8] {
    fn trim_end(&self) -> &[u8] {
        if let Some(last) = self.iter().rposition(is_not_whitespace) {
            &self[..=last]
        } else {
            &[]
        }
    }
    fn trim_start(&self) -> &[u8] {
        if let Some(first) = self.iter().position(is_not_whitespace) {
            &self[first..]
        } else {
            &[]
        }
    }

    /// ```
    /// use hg::utils::SliceExt;
    /// assert_eq!(
    ///     b"  to trim  ".trim(),
    ///     b"to trim"
    /// );
    /// assert_eq!(
    ///     b"to trim  ".trim(),
    ///     b"to trim"
    /// );
    /// assert_eq!(
    ///     b"  to trim".trim(),
    ///     b"to trim"
    /// );
    /// ```
    fn trim(&self) -> &[u8] {
        self.trim_start().trim_end()
    }

    fn drop_prefix(&self, needle: &Self) -> Option<&Self> {
        if self.starts_with(needle) {
            Some(&self[needle.len()..])
        } else {
            None
        }
    }
}

pub trait Escaped {
    /// Return bytes escaped for display to the user
    fn escaped_bytes(&self) -> Vec<u8>;
}

impl Escaped for u8 {
    fn escaped_bytes(&self) -> Vec<u8> {
        let mut acc = vec![];
        match self {
            c @ b'\'' | c @ b'\\' => {
                acc.push(b'\\');
                acc.push(*c);
            }
            b'\t' => {
                acc.extend(br"\\t");
            }
            b'\n' => {
                acc.extend(br"\\n");
            }
            b'\r' => {
                acc.extend(br"\\r");
            }
            c if (*c < b' ' || *c >= 127) => {
                write!(acc, "\\x{:x}", self).unwrap();
            }
            c => {
                acc.push(*c);
            }
        }
        acc
    }
}

impl<'a, T: Escaped> Escaped for &'a [T] {
    fn escaped_bytes(&self) -> Vec<u8> {
        self.iter().flat_map(Escaped::escaped_bytes).collect()
    }
}

impl<T: Escaped> Escaped for Vec<T> {
    fn escaped_bytes(&self) -> Vec<u8> {
        self.deref().escaped_bytes()
    }
}

impl<'a> Escaped for &'a HgPath {
    fn escaped_bytes(&self) -> Vec<u8> {
        self.as_bytes().escaped_bytes()
    }
}

// TODO: use the str method when we require Rust 1.45
pub(crate) fn strip_suffix<'a>(s: &'a str, suffix: &str) -> Option<&'a str> {
    if s.ends_with(suffix) {
        Some(&s[..s.len() - suffix.len()])
    } else {
        None
    }
}

pub fn current_dir() -> Result<std::path::PathBuf, HgError> {
    std::env::current_dir().map_err(|error| HgError::IoError {
        error,
        context: IoErrorContext::CurrentDir,
    })
}

pub fn current_exe() -> Result<std::path::PathBuf, HgError> {
    std::env::current_exe().map_err(|error| HgError::IoError {
        error,
        context: IoErrorContext::CurrentExe,
    })
}

// utils module
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Contains useful functions, traits, structs, etc. for use in core.

use crate::errors::{HgError, IoErrorContext};
use crate::utils::hg_path::HgPath;
use im_rc::ordmap::DiffItem;
use im_rc::ordmap::OrdMap;
use std::cell::Cell;
use std::fmt;
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
    fn trim_end_newlines(&self) -> &Self;
    fn trim_end(&self) -> &Self;
    fn trim_start(&self) -> &Self;
    fn trim(&self) -> &Self;
    fn drop_prefix(&self, needle: &Self) -> Option<&Self>;
    fn split_2(&self, separator: u8) -> Option<(&[u8], &[u8])>;
}

#[allow(clippy::trivially_copy_pass_by_ref)]
fn is_not_whitespace(c: &u8) -> bool {
    !(*c as char).is_whitespace()
}

impl SliceExt for [u8] {
    fn trim_end_newlines(&self) -> &[u8] {
        if let Some(last) = self.iter().rposition(|&byte| byte != b'\n') {
            &self[..=last]
        } else {
            &[]
        }
    }
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

    fn split_2(&self, separator: u8) -> Option<(&[u8], &[u8])> {
        let mut iter = self.splitn(2, |&byte| byte == separator);
        let a = iter.next()?;
        let b = iter.next()?;
        Some((a, b))
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

#[cfg(unix)]
pub fn shell_quote(value: &[u8]) -> Vec<u8> {
    // TODO: Use the `matches!` macro when we require Rust 1.42+
    if value.iter().all(|&byte| match byte {
        b'a'..=b'z'
        | b'A'..=b'Z'
        | b'0'..=b'9'
        | b'.'
        | b'_'
        | b'/'
        | b'+'
        | b'-' => true,
        _ => false,
    }) {
        value.to_owned()
    } else {
        let mut quoted = Vec::with_capacity(value.len() + 2);
        quoted.push(b'\'');
        for &byte in value {
            if byte == b'\'' {
                quoted.push(b'\\');
            }
            quoted.push(byte);
        }
        quoted.push(b'\'');
        quoted
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

pub(crate) enum MergeResult<V> {
    UseLeftValue,
    UseRightValue,
    UseNewValue(V),
}

/// Return the union of the two given maps,
/// calling `merge(key, left_value, right_value)` to resolve keys that exist in
/// both.
///
/// CC https://github.com/bodil/im-rs/issues/166
pub(crate) fn ordmap_union_with_merge<K, V>(
    left: OrdMap<K, V>,
    right: OrdMap<K, V>,
    mut merge: impl FnMut(&K, &V, &V) -> MergeResult<V>,
) -> OrdMap<K, V>
where
    K: Clone + Ord,
    V: Clone + PartialEq,
{
    if left.ptr_eq(&right) {
        // One of the two maps is an unmodified clone of the other
        left
    } else if left.len() / 2 > right.len() {
        // When two maps have different sizes,
        // their size difference is a lower bound on
        // how many keys of the larger map are not also in the smaller map.
        // This in turn is a lower bound on the number of differences in
        // `OrdMap::diff` and the "amount of work" that would be done
        // by `ordmap_union_with_merge_by_diff`.
        //
        // Here `left` is more than twice the size of `right`,
        // so the number of differences is more than the total size of
        // `right`. Therefore an algorithm based on iterating `right`
        // is more efficient.
        //
        // This helps a lot when a tiny (or empty) map is merged
        // with a large one.
        ordmap_union_with_merge_by_iter(left, right, merge)
    } else if left.len() < right.len() / 2 {
        // Same as above but with `left` and `right` swapped
        ordmap_union_with_merge_by_iter(right, left, |key, a, b| {
            // Also swapped in `merge` arguments:
            match merge(key, b, a) {
                MergeResult::UseNewValue(v) => MergeResult::UseNewValue(v),
                // … and swap back in `merge` result:
                MergeResult::UseLeftValue => MergeResult::UseRightValue,
                MergeResult::UseRightValue => MergeResult::UseLeftValue,
            }
        })
    } else {
        // For maps of similar size, use the algorithm based on `OrdMap::diff`
        ordmap_union_with_merge_by_diff(left, right, merge)
    }
}

/// Efficient if `right` is much smaller than `left`
fn ordmap_union_with_merge_by_iter<K, V>(
    mut left: OrdMap<K, V>,
    right: OrdMap<K, V>,
    mut merge: impl FnMut(&K, &V, &V) -> MergeResult<V>,
) -> OrdMap<K, V>
where
    K: Clone + Ord,
    V: Clone,
{
    for (key, right_value) in right {
        match left.get(&key) {
            None => {
                left.insert(key, right_value);
            }
            Some(left_value) => match merge(&key, left_value, &right_value) {
                MergeResult::UseLeftValue => {}
                MergeResult::UseRightValue => {
                    left.insert(key, right_value);
                }
                MergeResult::UseNewValue(new_value) => {
                    left.insert(key, new_value);
                }
            },
        }
    }
    left
}

/// Fallback when both maps are of similar size
fn ordmap_union_with_merge_by_diff<K, V>(
    mut left: OrdMap<K, V>,
    mut right: OrdMap<K, V>,
    mut merge: impl FnMut(&K, &V, &V) -> MergeResult<V>,
) -> OrdMap<K, V>
where
    K: Clone + Ord,
    V: Clone + PartialEq,
{
    // (key, value) pairs that would need to be inserted in either map
    // in order to turn it into the union.
    //
    // TODO: if/when https://github.com/bodil/im-rs/pull/168 is accepted,
    // change these from `Vec<(K, V)>` to `Vec<(&K, Cow<V>)>`
    // with `left_updates` only borrowing from `right` and `right_updates` from
    // `left`, and with `Cow::Owned` used for `MergeResult::UseNewValue`.
    //
    // This would allow moving all `.clone()` calls to after we’ve decided
    // which of `right_updates` or `left_updates` to use
    // (value ones becoming `Cow::into_owned`),
    // and avoid making clones we don’t end up using.
    let mut left_updates = Vec::new();
    let mut right_updates = Vec::new();

    for difference in left.diff(&right) {
        match difference {
            DiffItem::Add(key, value) => {
                left_updates.push((key.clone(), value.clone()))
            }
            DiffItem::Remove(key, value) => {
                right_updates.push((key.clone(), value.clone()))
            }
            DiffItem::Update {
                old: (key, left_value),
                new: (_, right_value),
            } => match merge(key, left_value, right_value) {
                MergeResult::UseLeftValue => {
                    right_updates.push((key.clone(), left_value.clone()))
                }
                MergeResult::UseRightValue => {
                    left_updates.push((key.clone(), right_value.clone()))
                }
                MergeResult::UseNewValue(new_value) => {
                    left_updates.push((key.clone(), new_value.clone()));
                    right_updates.push((key.clone(), new_value))
                }
            },
        }
    }
    if left_updates.len() < right_updates.len() {
        for (key, value) in left_updates {
            left.insert(key, value);
        }
        left
    } else {
        for (key, value) in right_updates {
            right.insert(key, value);
        }
        right
    }
}

/// Join items of the iterable with the given separator, similar to Python’s
/// `separator.join(iter)`.
///
/// Formatting the return value consumes the iterator.
/// Formatting it again will produce an empty string.
pub fn join_display(
    iter: impl IntoIterator<Item = impl fmt::Display>,
    separator: impl fmt::Display,
) -> impl fmt::Display {
    JoinDisplay {
        iter: Cell::new(Some(iter.into_iter())),
        separator,
    }
}

struct JoinDisplay<I, S> {
    iter: Cell<Option<I>>,
    separator: S,
}

impl<I, T, S> fmt::Display for JoinDisplay<I, S>
where
    I: Iterator<Item = T>,
    T: fmt::Display,
    S: fmt::Display,
{
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if let Some(mut iter) = self.iter.take() {
            if let Some(first) = iter.next() {
                first.fmt(f)?;
            }
            for value in iter {
                self.separator.fmt(f)?;
                value.fmt(f)?;
            }
        }
        Ok(())
    }
}

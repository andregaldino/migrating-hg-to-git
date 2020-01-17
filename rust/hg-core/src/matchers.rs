// matchers.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Structs and types for matching files and directories.

#[cfg(feature = "with-re2")]
use crate::re2::Re2;
use crate::{
    filepatterns::PatternResult, utils::hg_path::HgPath, DirsMultiset,
    DirstateMapError, PatternError,
};
use std::collections::HashSet;
use std::iter::FromIterator;
use std::ops::Deref;

#[derive(Debug, PartialEq)]
pub enum VisitChildrenSet<'a> {
    /// Don't visit anything
    Empty,
    /// Only visit this directory
    This,
    /// Visit this directory and these subdirectories
    /// TODO Should we implement a `NonEmptyHashSet`?
    Set(HashSet<&'a HgPath>),
    /// Visit this directory and all subdirectories
    Recursive,
}

pub trait Matcher {
    /// Explicitly listed files
    fn file_set(&self) -> Option<&HashSet<&HgPath>>;
    /// Returns whether `filename` is in `file_set`
    fn exact_match(&self, filename: impl AsRef<HgPath>) -> bool;
    /// Returns whether `filename` is matched by this matcher
    fn matches(&self, filename: impl AsRef<HgPath>) -> bool;
    /// Decides whether a directory should be visited based on whether it
    /// has potential matches in it or one of its subdirectories, and
    /// potentially lists which subdirectories of that directory should be
    /// visited. This is based on the match's primary, included, and excluded
    /// patterns.
    ///
    /// # Example
    ///
    /// Assume matchers `['path:foo/bar', 'rootfilesin:qux']`, we would
    /// return the following values (assuming the implementation of
    /// visit_children_set is capable of recognizing this; some implementations
    /// are not).
    ///
    /// ```text
    /// ```ignore
    /// '' -> {'foo', 'qux'}
    /// 'baz' -> set()
    /// 'foo' -> {'bar'}
    /// // Ideally this would be `Recursive`, but since the prefix nature of
    /// // matchers is applied to the entire matcher, we have to downgrade this
    /// // to `This` due to the (yet to be implemented in Rust) non-prefix
    /// // `RootFilesIn'-kind matcher being mixed in.
    /// 'foo/bar' -> 'this'
    /// 'qux' -> 'this'
    /// ```
    /// # Important
    ///
    /// Most matchers do not know if they're representing files or
    /// directories. They see `['path:dir/f']` and don't know whether `f` is a
    /// file or a directory, so `visit_children_set('dir')` for most matchers
    /// will return `HashSet{ HgPath { "f" } }`, but if the matcher knows it's
    /// a file (like the yet to be implemented in Rust `ExactMatcher` does),
    /// it may return `VisitChildrenSet::This`.
    /// Do not rely on the return being a `HashSet` indicating that there are
    /// no files in this dir to investigate (or equivalently that if there are
    /// files to investigate in 'dir' that it will always return
    /// `VisitChildrenSet::This`).
    fn visit_children_set(
        &self,
        directory: impl AsRef<HgPath>,
    ) -> VisitChildrenSet;
    /// Matcher will match everything and `files_set()` will be empty:
    /// optimization might be possible.
    fn matches_everything(&self) -> bool;
    /// Matcher will match exactly the files in `files_set()`: optimization
    /// might be possible.
    fn is_exact(&self) -> bool;
}

/// Matches everything.
///```
/// use hg::{ matchers::{Matcher, AlwaysMatcher}, utils::hg_path::HgPath };
///
/// let matcher = AlwaysMatcher;
///
/// assert_eq!(matcher.matches(HgPath::new(b"whatever")), true);
/// assert_eq!(matcher.matches(HgPath::new(b"b.txt")), true);
/// assert_eq!(matcher.matches(HgPath::new(b"main.c")), true);
/// assert_eq!(matcher.matches(HgPath::new(br"re:.*\.c$")), true);
/// ```
#[derive(Debug)]
pub struct AlwaysMatcher;

impl Matcher for AlwaysMatcher {
    fn file_set(&self) -> Option<&HashSet<&HgPath>> {
        None
    }
    fn exact_match(&self, _filename: impl AsRef<HgPath>) -> bool {
        false
    }
    fn matches(&self, _filename: impl AsRef<HgPath>) -> bool {
        true
    }
    fn visit_children_set(
        &self,
        _directory: impl AsRef<HgPath>,
    ) -> VisitChildrenSet {
        VisitChildrenSet::Recursive
    }
    fn matches_everything(&self) -> bool {
        true
    }
    fn is_exact(&self) -> bool {
        false
    }
}

/// Matches the input files exactly. They are interpreted as paths, not
/// patterns.
///
///```
/// use hg::{ matchers::{Matcher, FileMatcher}, utils::hg_path::HgPath };
///
/// let files = [HgPath::new(b"a.txt"), HgPath::new(br"re:.*\.c$")];
/// let matcher = FileMatcher::new(&files).unwrap();
///
/// assert_eq!(matcher.matches(HgPath::new(b"a.txt")), true);
/// assert_eq!(matcher.matches(HgPath::new(b"b.txt")), false);
/// assert_eq!(matcher.matches(HgPath::new(b"main.c")), false);
/// assert_eq!(matcher.matches(HgPath::new(br"re:.*\.c$")), true);
/// ```
#[derive(Debug)]
pub struct FileMatcher<'a> {
    files: HashSet<&'a HgPath>,
    dirs: DirsMultiset,
}

impl<'a> FileMatcher<'a> {
    pub fn new(
        files: &'a [impl AsRef<HgPath>],
    ) -> Result<Self, DirstateMapError> {
        Ok(Self {
            files: HashSet::from_iter(files.iter().map(|f| f.as_ref())),
            dirs: DirsMultiset::from_manifest(files)?,
        })
    }
    fn inner_matches(&self, filename: impl AsRef<HgPath>) -> bool {
        self.files.contains(filename.as_ref())
    }
}

impl<'a> Matcher for FileMatcher<'a> {
    fn file_set(&self) -> Option<&HashSet<&HgPath>> {
        Some(&self.files)
    }
    fn exact_match(&self, filename: impl AsRef<HgPath>) -> bool {
        self.inner_matches(filename)
    }
    fn matches(&self, filename: impl AsRef<HgPath>) -> bool {
        self.inner_matches(filename)
    }
    fn visit_children_set(
        &self,
        directory: impl AsRef<HgPath>,
    ) -> VisitChildrenSet {
        if self.files.is_empty() || !self.dirs.contains(&directory) {
            return VisitChildrenSet::Empty;
        }
        let dirs_as_set = self.dirs.iter().map(|k| k.deref()).collect();

        let mut candidates: HashSet<&HgPath> =
            self.files.union(&dirs_as_set).map(|k| *k).collect();
        candidates.remove(HgPath::new(b""));

        if !directory.as_ref().is_empty() {
            let directory = [directory.as_ref().as_bytes(), b"/"].concat();
            candidates = candidates
                .iter()
                .filter_map(|c| {
                    if c.as_bytes().starts_with(&directory) {
                        Some(HgPath::new(&c.as_bytes()[directory.len()..]))
                    } else {
                        None
                    }
                })
                .collect();
        }

        // `self.dirs` includes all of the directories, recursively, so if
        // we're attempting to match 'foo/bar/baz.txt', it'll have '', 'foo',
        // 'foo/bar' in it. Thus we can safely ignore a candidate that has a
        // '/' in it, indicating it's for a subdir-of-a-subdir; the immediate
        // subdir will be in there without a slash.
        VisitChildrenSet::Set(
            candidates
                .iter()
                .filter_map(|c| {
                    if c.bytes().all(|b| *b != b'/') {
                        Some(*c)
                    } else {
                        None
                    }
                })
                .collect(),
        )
    }
    fn matches_everything(&self) -> bool {
        false
    }
    fn is_exact(&self) -> bool {
        true
    }
}

#[cfg(feature = "with-re2")]
/// Returns a function that matches an `HgPath` against the given regex
/// pattern.
///
/// This can fail when the pattern is invalid or not supported by the
/// underlying engine `Re2`, for instance anything with back-references.
fn re_matcher(
    pattern: &[u8],
) -> PatternResult<impl Fn(&HgPath) -> bool + Sync> {
    let regex = Re2::new(pattern);
    let regex = regex.map_err(|e| PatternError::UnsupportedSyntax(e))?;
    Ok(move |path: &HgPath| regex.is_match(path.as_bytes()))
}

#[cfg(not(feature = "with-re2"))]
fn re_matcher(_: &[u8]) -> PatternResult<Box<dyn Fn(&HgPath) -> bool + Sync>> {
    Err(PatternError::Re2NotInstalled)
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn test_filematcher_visit_children_set() {
        // Visitchildrenset
        let files = vec![HgPath::new(b"dir/subdir/foo.txt")];
        let matcher = FileMatcher::new(&files).unwrap();

        let mut set = HashSet::new();
        set.insert(HgPath::new(b"dir"));
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"")),
            VisitChildrenSet::Set(set)
        );

        let mut set = HashSet::new();
        set.insert(HgPath::new(b"subdir"));
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir")),
            VisitChildrenSet::Set(set)
        );

        let mut set = HashSet::new();
        set.insert(HgPath::new(b"foo.txt"));
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir/subdir")),
            VisitChildrenSet::Set(set)
        );

        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir/subdir/x")),
            VisitChildrenSet::Empty
        );
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir/subdir/foo.txt")),
            VisitChildrenSet::Empty
        );
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"folder")),
            VisitChildrenSet::Empty
        );
    }

    #[test]
    fn test_filematcher_visit_children_set_files_and_dirs() {
        let files = vec![
            HgPath::new(b"rootfile.txt"),
            HgPath::new(b"a/file1.txt"),
            HgPath::new(b"a/b/file2.txt"),
            // No file in a/b/c
            HgPath::new(b"a/b/c/d/file4.txt"),
        ];
        let matcher = FileMatcher::new(&files).unwrap();

        let mut set = HashSet::new();
        set.insert(HgPath::new(b"a"));
        set.insert(HgPath::new(b"rootfile.txt"));
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"")),
            VisitChildrenSet::Set(set)
        );

        let mut set = HashSet::new();
        set.insert(HgPath::new(b"b"));
        set.insert(HgPath::new(b"file1.txt"));
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"a")),
            VisitChildrenSet::Set(set)
        );

        let mut set = HashSet::new();
        set.insert(HgPath::new(b"c"));
        set.insert(HgPath::new(b"file2.txt"));
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"a/b")),
            VisitChildrenSet::Set(set)
        );

        let mut set = HashSet::new();
        set.insert(HgPath::new(b"d"));
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"a/b/c")),
            VisitChildrenSet::Set(set)
        );
        let mut set = HashSet::new();
        set.insert(HgPath::new(b"file4.txt"));
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"a/b/c/d")),
            VisitChildrenSet::Set(set)
        );

        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"a/b/c/d/e")),
            VisitChildrenSet::Empty
        );
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"folder")),
            VisitChildrenSet::Empty
        );
    }
}

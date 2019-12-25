// matchers.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Structs and types for matching files and directories.

use crate::{utils::hg_path::HgPath, DirsMultiset, DirstateMapError};
use std::collections::HashSet;
use std::iter::FromIterator;

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
        _directory: impl AsRef<HgPath>,
    ) -> VisitChildrenSet {
        // TODO implement once we have `status.traverse`
        // This is useless until unknown files are taken into account
        // Which will not need to happen before the `IncludeMatcher`.
        unimplemented!()
    }
    fn matches_everything(&self) -> bool {
        false
    }
    fn is_exact(&self) -> bool {
        true
    }
}

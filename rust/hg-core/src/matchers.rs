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
    dirstate::dirs_multiset::DirsChildrenMultiset,
    filepatterns::{
        build_single_regex, filter_subincludes, get_patterns_from_file,
        PatternFileWarning, PatternResult, SubInclude,
    },
    utils::{
        files::find_dirs,
        hg_path::{HgPath, HgPathBuf},
        Escaped,
    },
    DirsMultiset, DirstateMapError, FastHashMap, IgnorePattern, PatternError,
    PatternSyntax,
};

use crate::filepatterns::normalize_path_bytes;
use std::borrow::ToOwned;
use std::collections::HashSet;
use std::fmt::{Display, Error, Formatter};
use std::iter::FromIterator;
use std::ops::Deref;
use std::path::{Path, PathBuf};

use micro_timer::timed;

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

/// Matches files that are included in the ignore rules.
#[cfg_attr(
    feature = "with-re2",
    doc = r##"
```
use hg::{
    matchers::{IncludeMatcher, Matcher},
    IgnorePattern,
    PatternSyntax,
    utils::hg_path::HgPath
};
use std::path::Path;
///
let ignore_patterns =
vec![IgnorePattern::new(PatternSyntax::RootGlob, b"this*", Path::new(""))];
let (matcher, _) = IncludeMatcher::new(ignore_patterns, "").unwrap();
///
assert_eq!(matcher.matches(HgPath::new(b"testing")), false);
assert_eq!(matcher.matches(HgPath::new(b"this should work")), true);
assert_eq!(matcher.matches(HgPath::new(b"this also")), true);
assert_eq!(matcher.matches(HgPath::new(b"but not this")), false);
```
"##
)]
pub struct IncludeMatcher<'a> {
    patterns: Vec<u8>,
    match_fn: Box<dyn for<'r> Fn(&'r HgPath) -> bool + 'a + Sync>,
    /// Whether all the patterns match a prefix (i.e. recursively)
    prefix: bool,
    roots: HashSet<HgPathBuf>,
    dirs: HashSet<HgPathBuf>,
    parents: HashSet<HgPathBuf>,
}

impl<'a> Matcher for IncludeMatcher<'a> {
    fn file_set(&self) -> Option<&HashSet<&HgPath>> {
        None
    }

    fn exact_match(&self, _filename: impl AsRef<HgPath>) -> bool {
        false
    }

    fn matches(&self, filename: impl AsRef<HgPath>) -> bool {
        (self.match_fn)(filename.as_ref())
    }

    fn visit_children_set(
        &self,
        directory: impl AsRef<HgPath>,
    ) -> VisitChildrenSet {
        let dir = directory.as_ref();
        if self.prefix && self.roots.contains(dir) {
            return VisitChildrenSet::Recursive;
        }
        if self.roots.contains(HgPath::new(b""))
            || self.roots.contains(dir)
            || self.dirs.contains(dir)
            || find_dirs(dir).any(|parent_dir| self.roots.contains(parent_dir))
        {
            return VisitChildrenSet::This;
        }

        if self.parents.contains(directory.as_ref()) {
            let multiset = self.get_all_parents_children();
            if let Some(children) = multiset.get(dir) {
                return VisitChildrenSet::Set(children.to_owned());
            }
        }
        VisitChildrenSet::Empty
    }

    fn matches_everything(&self) -> bool {
        false
    }

    fn is_exact(&self) -> bool {
        false
    }
}

#[cfg(feature = "with-re2")]
/// Returns a function that matches an `HgPath` against the given regex
/// pattern.
///
/// This can fail when the pattern is invalid or not supported by the
/// underlying engine `Re2`, for instance anything with back-references.
#[timed]
fn re_matcher(
    pattern: &[u8],
) -> PatternResult<impl Fn(&HgPath) -> bool + Sync> {
    let regex = Re2::new(pattern);
    let regex = regex.map_err(|e| PatternError::UnsupportedSyntax(e))?;
    Ok(move |path: &HgPath| regex.is_match(path.as_bytes()))
}

#[cfg(not(feature = "with-re2"))]
/// Returns a function that matches an `HgPath` against the given regex
/// pattern.
///
/// This can fail when the pattern is invalid or not supported by the
/// underlying engine (the `regex` crate), for instance anything with
/// back-references.
#[timed]
fn re_matcher(
    pattern: &[u8],
) -> PatternResult<impl Fn(&HgPath) -> bool + Sync> {
    use std::io::Write;

    let mut escaped_bytes = vec![];
    for byte in pattern {
        if *byte > 127 {
            write!(escaped_bytes, "\\x{:x}", *byte).unwrap();
        } else {
            escaped_bytes.push(*byte);
        }
    }

    // Avoid the cost of UTF8 checking
    //
    // # Safety
    // This is safe because we escaped all non-ASCII bytes.
    let pattern_string = unsafe { String::from_utf8_unchecked(escaped_bytes) };
    let re = regex::bytes::RegexBuilder::new(&pattern_string)
        .unicode(false)
        .build()
        .map_err(|e| PatternError::UnsupportedSyntax(e.to_string()))?;

    Ok(move |path: &HgPath| re.is_match(path.as_bytes()))
}

/// Returns the regex pattern and a function that matches an `HgPath` against
/// said regex formed by the given ignore patterns.
fn build_regex_match<'a>(
    ignore_patterns: &'a [&'a IgnorePattern],
) -> PatternResult<(Vec<u8>, Box<dyn Fn(&HgPath) -> bool + Sync>)> {
    let mut regexps = vec![];
    let mut exact_set = HashSet::new();

    for pattern in ignore_patterns {
        if let Some(re) = build_single_regex(pattern)? {
            regexps.push(re);
        } else {
            let exact = normalize_path_bytes(&pattern.pattern);
            exact_set.insert(HgPathBuf::from_bytes(&exact));
        }
    }

    let full_regex = regexps.join(&b'|');

    // An empty pattern would cause the regex engine to incorrectly match the
    // (empty) root directory
    let func = if !(regexps.is_empty()) {
        let matcher = re_matcher(&full_regex)?;
        let func = move |filename: &HgPath| {
            exact_set.contains(filename) || matcher(filename)
        };
        Box::new(func) as Box<dyn Fn(&HgPath) -> bool + Sync>
    } else {
        let func = move |filename: &HgPath| exact_set.contains(filename);
        Box::new(func) as Box<dyn Fn(&HgPath) -> bool + Sync>
    };

    Ok((full_regex, func))
}

/// Returns roots and directories corresponding to each pattern.
///
/// This calculates the roots and directories exactly matching the patterns and
/// returns a tuple of (roots, dirs). It does not return other directories
/// which may also need to be considered, like the parent directories.
fn roots_and_dirs(
    ignore_patterns: &[IgnorePattern],
) -> (Vec<HgPathBuf>, Vec<HgPathBuf>) {
    let mut roots = Vec::new();
    let mut dirs = Vec::new();

    for ignore_pattern in ignore_patterns {
        let IgnorePattern {
            syntax, pattern, ..
        } = ignore_pattern;
        match syntax {
            PatternSyntax::RootGlob | PatternSyntax::Glob => {
                let mut root = vec![];

                for p in pattern.split(|c| *c == b'/') {
                    if p.iter().any(|c| match *c {
                        b'[' | b'{' | b'*' | b'?' => true,
                        _ => false,
                    }) {
                        break;
                    }
                    root.push(HgPathBuf::from_bytes(p));
                }
                let buf =
                    root.iter().fold(HgPathBuf::new(), |acc, r| acc.join(r));
                roots.push(buf);
            }
            PatternSyntax::Path | PatternSyntax::RelPath => {
                let pat = HgPath::new(if pattern == b"." {
                    &[] as &[u8]
                } else {
                    pattern
                });
                roots.push(pat.to_owned());
            }
            PatternSyntax::RootFiles => {
                let pat = if pattern == b"." {
                    &[] as &[u8]
                } else {
                    pattern
                };
                dirs.push(HgPathBuf::from_bytes(pat));
            }
            _ => {
                roots.push(HgPathBuf::new());
            }
        }
    }
    (roots, dirs)
}

/// Paths extracted from patterns
#[derive(Debug, PartialEq)]
struct RootsDirsAndParents {
    /// Directories to match recursively
    pub roots: HashSet<HgPathBuf>,
    /// Directories to match non-recursively
    pub dirs: HashSet<HgPathBuf>,
    /// Implicitly required directories to go to items in either roots or dirs
    pub parents: HashSet<HgPathBuf>,
}

/// Extract roots, dirs and parents from patterns.
fn roots_dirs_and_parents(
    ignore_patterns: &[IgnorePattern],
) -> PatternResult<RootsDirsAndParents> {
    let (roots, dirs) = roots_and_dirs(ignore_patterns);

    let mut parents = HashSet::new();

    parents.extend(
        DirsMultiset::from_manifest(&dirs)
            .map_err(|e| match e {
                DirstateMapError::InvalidPath(e) => e,
                _ => unreachable!(),
            })?
            .iter()
            .map(|k| k.to_owned()),
    );
    parents.extend(
        DirsMultiset::from_manifest(&roots)
            .map_err(|e| match e {
                DirstateMapError::InvalidPath(e) => e,
                _ => unreachable!(),
            })?
            .iter()
            .map(|k| k.to_owned()),
    );

    Ok(RootsDirsAndParents {
        roots: HashSet::from_iter(roots),
        dirs: HashSet::from_iter(dirs),
        parents,
    })
}

/// Returns a function that checks whether a given file (in the general sense)
/// should be matched.
fn build_match<'a, 'b>(
    ignore_patterns: &'a [IgnorePattern],
    root_dir: impl AsRef<Path>,
) -> PatternResult<(
    Vec<u8>,
    Box<dyn Fn(&HgPath) -> bool + 'b + Sync>,
    Vec<PatternFileWarning>,
)> {
    let mut match_funcs: Vec<Box<dyn Fn(&HgPath) -> bool + Sync>> = vec![];
    // For debugging and printing
    let mut patterns = vec![];
    let mut all_warnings = vec![];

    let (subincludes, ignore_patterns) =
        filter_subincludes(ignore_patterns, root_dir)?;

    if !subincludes.is_empty() {
        // Build prefix-based matcher functions for subincludes
        let mut submatchers = FastHashMap::default();
        let mut prefixes = vec![];

        for SubInclude { prefix, root, path } in subincludes.into_iter() {
            let (match_fn, warnings) =
                get_ignore_function(vec![path.to_path_buf()], root)?;
            all_warnings.extend(warnings);
            prefixes.push(prefix.to_owned());
            submatchers.insert(prefix.to_owned(), match_fn);
        }

        let match_subinclude = move |filename: &HgPath| {
            for prefix in prefixes.iter() {
                if let Some(rel) = filename.relative_to(prefix) {
                    if (submatchers.get(prefix).unwrap())(rel) {
                        return true;
                    }
                }
            }
            false
        };

        match_funcs.push(Box::new(match_subinclude));
    }

    if !ignore_patterns.is_empty() {
        // Either do dumb matching if all patterns are rootfiles, or match
        // with a regex.
        if ignore_patterns
            .iter()
            .all(|k| k.syntax == PatternSyntax::RootFiles)
        {
            let dirs: HashSet<_> = ignore_patterns
                .iter()
                .map(|k| k.pattern.to_owned())
                .collect();
            let mut dirs_vec: Vec<_> = dirs.iter().cloned().collect();

            let match_func = move |path: &HgPath| -> bool {
                let path = path.as_bytes();
                let i = path.iter().rfind(|a| **a == b'/');
                let dir = if let Some(i) = i {
                    &path[..*i as usize]
                } else {
                    b"."
                };
                dirs.contains(dir.deref())
            };
            match_funcs.push(Box::new(match_func));

            patterns.extend(b"rootfilesin: ");
            dirs_vec.sort();
            patterns.extend(dirs_vec.escaped_bytes());
        } else {
            let (new_re, match_func) = build_regex_match(&ignore_patterns)?;
            patterns = new_re;
            match_funcs.push(match_func)
        }
    }

    Ok(if match_funcs.len() == 1 {
        (patterns, match_funcs.remove(0), all_warnings)
    } else {
        (
            patterns,
            Box::new(move |f: &HgPath| -> bool {
                match_funcs.iter().any(|match_func| match_func(f))
            }),
            all_warnings,
        )
    })
}

/// Parses all "ignore" files with their recursive includes and returns a
/// function that checks whether a given file (in the general sense) should be
/// ignored.
pub fn get_ignore_function<'a>(
    all_pattern_files: Vec<PathBuf>,
    root_dir: impl AsRef<Path>,
) -> PatternResult<(
    Box<dyn for<'r> Fn(&'r HgPath) -> bool + Sync + 'a>,
    Vec<PatternFileWarning>,
)> {
    let mut all_patterns = vec![];
    let mut all_warnings = vec![];

    for pattern_file in all_pattern_files.into_iter() {
        let (patterns, warnings) =
            get_patterns_from_file(pattern_file, &root_dir)?;

        all_patterns.extend(patterns.to_owned());
        all_warnings.extend(warnings);
    }
    let (matcher, warnings) = IncludeMatcher::new(all_patterns, root_dir)?;
    all_warnings.extend(warnings);
    Ok((
        Box::new(move |path: &HgPath| matcher.matches(path)),
        all_warnings,
    ))
}

impl<'a> IncludeMatcher<'a> {
    pub fn new(
        ignore_patterns: Vec<IgnorePattern>,
        root_dir: impl AsRef<Path>,
    ) -> PatternResult<(Self, Vec<PatternFileWarning>)> {
        let (patterns, match_fn, warnings) =
            build_match(&ignore_patterns, root_dir)?;
        let RootsDirsAndParents {
            roots,
            dirs,
            parents,
        } = roots_dirs_and_parents(&ignore_patterns)?;

        let prefix = ignore_patterns.iter().any(|k| match k.syntax {
            PatternSyntax::Path | PatternSyntax::RelPath => true,
            _ => false,
        });

        Ok((
            Self {
                patterns,
                match_fn,
                prefix,
                roots,
                dirs,
                parents,
            },
            warnings,
        ))
    }

    fn get_all_parents_children(&self) -> DirsChildrenMultiset {
        // TODO cache
        let thing = self
            .dirs
            .iter()
            .chain(self.roots.iter())
            .chain(self.parents.iter());
        DirsChildrenMultiset::new(thing, Some(&self.parents))
    }
}

impl<'a> Display for IncludeMatcher<'a> {
    fn fmt(&self, f: &mut Formatter<'_>) -> Result<(), Error> {
        write!(
            f,
            "IncludeMatcher(includes='{}')",
            String::from_utf8_lossy(&self.patterns.escaped_bytes())
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use std::path::Path;

    #[test]
    fn test_roots_and_dirs() {
        let pats = vec![
            IgnorePattern::new(PatternSyntax::Glob, b"g/h/*", Path::new("")),
            IgnorePattern::new(PatternSyntax::Glob, b"g/h", Path::new("")),
            IgnorePattern::new(PatternSyntax::Glob, b"g*", Path::new("")),
        ];
        let (roots, dirs) = roots_and_dirs(&pats);

        assert_eq!(
            roots,
            vec!(
                HgPathBuf::from_bytes(b"g/h"),
                HgPathBuf::from_bytes(b"g/h"),
                HgPathBuf::new()
            ),
        );
        assert_eq!(dirs, vec!());
    }

    #[test]
    fn test_roots_dirs_and_parents() {
        let pats = vec![
            IgnorePattern::new(PatternSyntax::Glob, b"g/h/*", Path::new("")),
            IgnorePattern::new(PatternSyntax::Glob, b"g/h", Path::new("")),
            IgnorePattern::new(PatternSyntax::Glob, b"g*", Path::new("")),
        ];

        let mut roots = HashSet::new();
        roots.insert(HgPathBuf::from_bytes(b"g/h"));
        roots.insert(HgPathBuf::new());

        let dirs = HashSet::new();

        let mut parents = HashSet::new();
        parents.insert(HgPathBuf::new());
        parents.insert(HgPathBuf::from_bytes(b"g"));

        assert_eq!(
            roots_dirs_and_parents(&pats).unwrap(),
            RootsDirsAndParents {
                roots,
                dirs,
                parents
            }
        );
    }

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

    #[cfg(feature = "with-re2")]
    #[test]
    fn test_includematcher() {
        // VisitchildrensetPrefix
        let (matcher, _) = IncludeMatcher::new(
            vec![IgnorePattern::new(
                PatternSyntax::RelPath,
                b"dir/subdir",
                Path::new(""),
            )],
            "",
        )
        .unwrap();

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
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir/subdir")),
            VisitChildrenSet::Recursive
        );
        // OPT: This should probably be 'all' if its parent is?
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir/subdir/x")),
            VisitChildrenSet::This
        );
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"folder")),
            VisitChildrenSet::Empty
        );

        // VisitchildrensetRootfilesin
        let (matcher, _) = IncludeMatcher::new(
            vec![IgnorePattern::new(
                PatternSyntax::RootFiles,
                b"dir/subdir",
                Path::new(""),
            )],
            "",
        )
        .unwrap();

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

        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir/subdir")),
            VisitChildrenSet::This
        );
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir/subdir/x")),
            VisitChildrenSet::Empty
        );
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"folder")),
            VisitChildrenSet::Empty
        );

        // VisitchildrensetGlob
        let (matcher, _) = IncludeMatcher::new(
            vec![IgnorePattern::new(
                PatternSyntax::Glob,
                b"dir/z*",
                Path::new(""),
            )],
            "",
        )
        .unwrap();

        let mut set = HashSet::new();
        set.insert(HgPath::new(b"dir"));
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"")),
            VisitChildrenSet::Set(set)
        );
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"folder")),
            VisitChildrenSet::Empty
        );
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir")),
            VisitChildrenSet::This
        );
        // OPT: these should probably be set().
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir/subdir")),
            VisitChildrenSet::This
        );
        assert_eq!(
            matcher.visit_children_set(HgPath::new(b"dir/subdir/x")),
            VisitChildrenSet::This
        );
    }
}

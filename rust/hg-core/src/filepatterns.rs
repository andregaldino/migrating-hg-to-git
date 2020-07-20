// filepatterns.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Handling of Mercurial-specific patterns.

use crate::{
    utils::{
        files::{canonical_path, get_bytes_from_path, get_path_from_bytes},
        hg_path::{path_to_hg_path_buf, HgPathBuf, HgPathError},
        SliceExt,
    },
    FastHashMap, PatternError,
};
use lazy_static::lazy_static;
use regex::bytes::{NoExpand, Regex};
use std::fs::File;
use std::io::Read;
use std::ops::Deref;
use std::path::{Path, PathBuf};
use std::vec::Vec;

lazy_static! {
    static ref RE_ESCAPE: Vec<Vec<u8>> = {
        let mut v: Vec<Vec<u8>> = (0..=255).map(|byte| vec![byte]).collect();
        let to_escape = b"()[]{}?*+-|^$\\.&~# \t\n\r\x0b\x0c";
        for byte in to_escape {
            v[*byte as usize].insert(0, b'\\');
        }
        v
    };
}

/// These are matched in order
const GLOB_REPLACEMENTS: &[(&[u8], &[u8])] =
    &[(b"*/", b"(?:.*/)?"), (b"*", b".*"), (b"", b"[^/]*")];

/// Appended to the regexp of globs
const GLOB_SUFFIX: &[u8; 7] = b"(?:/|$)";

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum PatternSyntax {
    /// A regular expression
    Regexp,
    /// Glob that matches at the front of the path
    RootGlob,
    /// Glob that matches at any suffix of the path (still anchored at
    /// slashes)
    Glob,
    /// a path relative to repository root, which is matched recursively
    Path,
    /// A path relative to cwd
    RelPath,
    /// an unrooted glob (*.rs matches Rust files in all dirs)
    RelGlob,
    /// A regexp that needn't match the start of a name
    RelRegexp,
    /// A path relative to repository root, which is matched non-recursively
    /// (will not match subdirectories)
    RootFiles,
    /// A file of patterns to read and include
    Include,
    /// A file of patterns to match against files under the same directory
    SubInclude,
}

/// Transforms a glob pattern into a regex
fn glob_to_re(pat: &[u8]) -> Vec<u8> {
    let mut input = pat;
    let mut res: Vec<u8> = vec![];
    let mut group_depth = 0;

    while let Some((c, rest)) = input.split_first() {
        input = rest;

        match c {
            b'*' => {
                for (source, repl) in GLOB_REPLACEMENTS {
                    if let Some(rest) = input.drop_prefix(source) {
                        input = rest;
                        res.extend(*repl);
                        break;
                    }
                }
            }
            b'?' => res.extend(b"."),
            b'[' => {
                match input.iter().skip(1).position(|b| *b == b']') {
                    None => res.extend(b"\\["),
                    Some(end) => {
                        // Account for the one we skipped
                        let end = end + 1;

                        res.extend(b"[");

                        for (i, b) in input[..end].iter().enumerate() {
                            if *b == b'!' && i == 0 {
                                res.extend(b"^")
                            } else if *b == b'^' && i == 0 {
                                res.extend(b"\\^")
                            } else if *b == b'\\' {
                                res.extend(b"\\\\")
                            } else {
                                res.push(*b)
                            }
                        }
                        res.extend(b"]");
                        input = &input[end + 1..];
                    }
                }
            }
            b'{' => {
                group_depth += 1;
                res.extend(b"(?:")
            }
            b'}' if group_depth > 0 => {
                group_depth -= 1;
                res.extend(b")");
            }
            b',' if group_depth > 0 => res.extend(b"|"),
            b'\\' => {
                let c = {
                    if let Some((c, rest)) = input.split_first() {
                        input = rest;
                        c
                    } else {
                        c
                    }
                };
                res.extend(&RE_ESCAPE[*c as usize])
            }
            _ => res.extend(&RE_ESCAPE[*c as usize]),
        }
    }
    res
}

fn escape_pattern(pattern: &[u8]) -> Vec<u8> {
    pattern
        .iter()
        .flat_map(|c| RE_ESCAPE[*c as usize].clone())
        .collect()
}

pub fn parse_pattern_syntax(
    kind: &[u8],
) -> Result<PatternSyntax, PatternError> {
    match kind {
        b"re:" => Ok(PatternSyntax::Regexp),
        b"path:" => Ok(PatternSyntax::Path),
        b"relpath:" => Ok(PatternSyntax::RelPath),
        b"rootfilesin:" => Ok(PatternSyntax::RootFiles),
        b"relglob:" => Ok(PatternSyntax::RelGlob),
        b"relre:" => Ok(PatternSyntax::RelRegexp),
        b"glob:" => Ok(PatternSyntax::Glob),
        b"rootglob:" => Ok(PatternSyntax::RootGlob),
        b"include:" => Ok(PatternSyntax::Include),
        b"subinclude:" => Ok(PatternSyntax::SubInclude),
        _ => Err(PatternError::UnsupportedSyntax(
            String::from_utf8_lossy(kind).to_string(),
        )),
    }
}

/// Builds the regex that corresponds to the given pattern.
/// If within a `syntax: regexp` context, returns the pattern,
/// otherwise, returns the corresponding regex.
fn _build_single_regex(entry: &IgnorePattern) -> Vec<u8> {
    let IgnorePattern {
        syntax, pattern, ..
    } = entry;
    if pattern.is_empty() {
        return vec![];
    }
    match syntax {
        PatternSyntax::Regexp => pattern.to_owned(),
        PatternSyntax::RelRegexp => {
            // The `regex` crate accepts `**` while `re2` and Python's `re`
            // do not. Checking for `*` correctly triggers the same error all
            // engines.
            if pattern[0] == b'^'
                || pattern[0] == b'*'
                || pattern.starts_with(b".*")
            {
                return pattern.to_owned();
            }
            [&b".*"[..], pattern].concat()
        }
        PatternSyntax::Path | PatternSyntax::RelPath => {
            if pattern == b"." {
                return vec![];
            }
            [escape_pattern(pattern).as_slice(), b"(?:/|$)"].concat()
        }
        PatternSyntax::RootFiles => {
            let mut res = if pattern == b"." {
                vec![]
            } else {
                // Pattern is a directory name.
                [escape_pattern(pattern).as_slice(), b"/"].concat()
            };

            // Anything after the pattern must be a non-directory.
            res.extend(b"[^/]+$");
            res
        }
        PatternSyntax::RelGlob => {
            let glob_re = glob_to_re(pattern);
            if let Some(rest) = glob_re.drop_prefix(b"[^/]*") {
                [b".*", rest, GLOB_SUFFIX].concat()
            } else {
                [b"(?:.*/)?", glob_re.as_slice(), GLOB_SUFFIX].concat()
            }
        }
        PatternSyntax::Glob | PatternSyntax::RootGlob => {
            [glob_to_re(pattern).as_slice(), GLOB_SUFFIX].concat()
        }
        PatternSyntax::Include | PatternSyntax::SubInclude => unreachable!(),
    }
}

const GLOB_SPECIAL_CHARACTERS: [u8; 7] =
    [b'*', b'?', b'[', b']', b'{', b'}', b'\\'];

/// TODO support other platforms
#[cfg(unix)]
pub fn normalize_path_bytes(bytes: &[u8]) -> Vec<u8> {
    if bytes.is_empty() {
        return b".".to_vec();
    }
    let sep = b'/';

    let mut initial_slashes = bytes.iter().take_while(|b| **b == sep).count();
    if initial_slashes > 2 {
        // POSIX allows one or two initial slashes, but treats three or more
        // as single slash.
        initial_slashes = 1;
    }
    let components = bytes
        .split(|b| *b == sep)
        .filter(|c| !(c.is_empty() || c == b"."))
        .fold(vec![], |mut acc, component| {
            if component != b".."
                || (initial_slashes == 0 && acc.is_empty())
                || (!acc.is_empty() && acc[acc.len() - 1] == b"..")
            {
                acc.push(component)
            } else if !acc.is_empty() {
                acc.pop();
            }
            acc
        });
    let mut new_bytes = components.join(&sep);

    if initial_slashes > 0 {
        let mut buf: Vec<_> = (0..initial_slashes).map(|_| sep).collect();
        buf.extend(new_bytes);
        new_bytes = buf;
    }
    if new_bytes.is_empty() {
        b".".to_vec()
    } else {
        new_bytes
    }
}

/// Wrapper function to `_build_single_regex` that short-circuits 'exact' globs
/// that don't need to be transformed into a regex.
pub fn build_single_regex(
    entry: &IgnorePattern,
) -> Result<Option<Vec<u8>>, PatternError> {
    let IgnorePattern {
        pattern, syntax, ..
    } = entry;
    let pattern = match syntax {
        PatternSyntax::RootGlob
        | PatternSyntax::Path
        | PatternSyntax::RelGlob
        | PatternSyntax::RootFiles => normalize_path_bytes(&pattern),
        PatternSyntax::Include | PatternSyntax::SubInclude => {
            return Err(PatternError::NonRegexPattern(entry.clone()))
        }
        _ => pattern.to_owned(),
    };
    if *syntax == PatternSyntax::RootGlob
        && !pattern.iter().any(|b| GLOB_SPECIAL_CHARACTERS.contains(b))
    {
        Ok(None)
    } else {
        let mut entry = entry.clone();
        entry.pattern = pattern;
        Ok(Some(_build_single_regex(&entry)))
    }
}

lazy_static! {
    static ref SYNTAXES: FastHashMap<&'static [u8], &'static [u8]> = {
        let mut m = FastHashMap::default();

        m.insert(b"re".as_ref(), b"relre:".as_ref());
        m.insert(b"regexp".as_ref(), b"relre:".as_ref());
        m.insert(b"glob".as_ref(), b"relglob:".as_ref());
        m.insert(b"rootglob".as_ref(), b"rootglob:".as_ref());
        m.insert(b"include".as_ref(), b"include:".as_ref());
        m.insert(b"subinclude".as_ref(), b"subinclude:".as_ref());
        m
    };
}

#[derive(Debug)]
pub enum PatternFileWarning {
    /// (file path, syntax bytes)
    InvalidSyntax(PathBuf, Vec<u8>),
    /// File path
    NoSuchFile(PathBuf),
}

pub fn parse_pattern_file_contents<P: AsRef<Path>>(
    lines: &[u8],
    file_path: P,
    warn: bool,
) -> Result<(Vec<IgnorePattern>, Vec<PatternFileWarning>), PatternError> {
    let comment_regex = Regex::new(r"((?:^|[^\\])(?:\\\\)*)#.*").unwrap();

    #[allow(clippy::trivial_regex)]
    let comment_escape_regex = Regex::new(r"\\#").unwrap();
    let mut inputs: Vec<IgnorePattern> = vec![];
    let mut warnings: Vec<PatternFileWarning> = vec![];

    let mut current_syntax = b"relre:".as_ref();

    for (line_number, mut line) in lines.split(|c| *c == b'\n').enumerate() {
        let line_number = line_number + 1;

        let line_buf;
        if line.contains(&b'#') {
            if let Some(cap) = comment_regex.captures(line) {
                line = &line[..cap.get(1).unwrap().end()]
            }
            line_buf = comment_escape_regex.replace_all(line, NoExpand(b"#"));
            line = &line_buf;
        }

        let mut line = line.trim_end();

        if line.is_empty() {
            continue;
        }

        if let Some(syntax) = line.drop_prefix(b"syntax:") {
            let syntax = syntax.trim();

            if let Some(rel_syntax) = SYNTAXES.get(syntax) {
                current_syntax = rel_syntax;
            } else if warn {
                warnings.push(PatternFileWarning::InvalidSyntax(
                    file_path.as_ref().to_owned(),
                    syntax.to_owned(),
                ));
            }
            continue;
        }

        let mut line_syntax: &[u8] = &current_syntax;

        for (s, rels) in SYNTAXES.iter() {
            if let Some(rest) = line.drop_prefix(rels) {
                line_syntax = rels;
                line = rest;
                break;
            }
            if let Some(rest) = line.drop_prefix(&[s, &b":"[..]].concat()) {
                line_syntax = rels;
                line = rest;
                break;
            }
        }

        inputs.push(IgnorePattern::new(
            parse_pattern_syntax(&line_syntax).map_err(|e| match e {
                PatternError::UnsupportedSyntax(syntax) => {
                    PatternError::UnsupportedSyntaxInFile(
                        syntax,
                        file_path.as_ref().to_string_lossy().into(),
                        line_number,
                    )
                }
                _ => e,
            })?,
            &line,
            &file_path,
        ));
    }
    Ok((inputs, warnings))
}

pub fn read_pattern_file<P: AsRef<Path>>(
    file_path: P,
    warn: bool,
) -> Result<(Vec<IgnorePattern>, Vec<PatternFileWarning>), PatternError> {
    let mut f = match File::open(file_path.as_ref()) {
        Ok(f) => Ok(f),
        Err(e) => match e.kind() {
            std::io::ErrorKind::NotFound => {
                return Ok((
                    vec![],
                    vec![PatternFileWarning::NoSuchFile(
                        file_path.as_ref().to_owned(),
                    )],
                ))
            }
            _ => Err(e),
        },
    }?;
    let mut contents = Vec::new();

    f.read_to_end(&mut contents)?;

    Ok(parse_pattern_file_contents(&contents, file_path, warn)?)
}

/// Represents an entry in an "ignore" file.
#[derive(Debug, Eq, PartialEq, Clone)]
pub struct IgnorePattern {
    pub syntax: PatternSyntax,
    pub pattern: Vec<u8>,
    pub source: PathBuf,
}

impl IgnorePattern {
    pub fn new(
        syntax: PatternSyntax,
        pattern: &[u8],
        source: impl AsRef<Path>,
    ) -> Self {
        Self {
            syntax,
            pattern: pattern.to_owned(),
            source: source.as_ref().to_owned(),
        }
    }
}

pub type PatternResult<T> = Result<T, PatternError>;

/// Wrapper for `read_pattern_file` that also recursively expands `include:`
/// patterns.
///
/// `subinclude:` is not treated as a special pattern here: unraveling them
/// needs to occur in the "ignore" phase.
pub fn get_patterns_from_file(
    pattern_file: impl AsRef<Path>,
    root_dir: impl AsRef<Path>,
) -> PatternResult<(Vec<IgnorePattern>, Vec<PatternFileWarning>)> {
    let (patterns, mut warnings) = read_pattern_file(&pattern_file, true)?;
    let patterns = patterns
        .into_iter()
        .flat_map(|entry| -> PatternResult<_> {
            let IgnorePattern {
                syntax, pattern, ..
            } = &entry;
            Ok(match syntax {
                PatternSyntax::Include => {
                    let inner_include =
                        root_dir.as_ref().join(get_path_from_bytes(&pattern));
                    let (inner_pats, inner_warnings) = get_patterns_from_file(
                        &inner_include,
                        root_dir.as_ref(),
                    )?;
                    warnings.extend(inner_warnings);
                    inner_pats
                }
                _ => vec![entry],
            })
        })
        .flatten()
        .collect();

    Ok((patterns, warnings))
}

/// Holds all the information needed to handle a `subinclude:` pattern.
pub struct SubInclude {
    /// Will be used for repository (hg) paths that start with this prefix.
    /// It is relative to the current working directory, so comparing against
    /// repository paths is painless.
    pub prefix: HgPathBuf,
    /// The file itself, containing the patterns
    pub path: PathBuf,
    /// Folder in the filesystem where this it applies
    pub root: PathBuf,
}

impl SubInclude {
    pub fn new(
        root_dir: impl AsRef<Path>,
        pattern: &[u8],
        source: impl AsRef<Path>,
    ) -> Result<SubInclude, HgPathError> {
        let normalized_source =
            normalize_path_bytes(&get_bytes_from_path(source));

        let source_root = get_path_from_bytes(&normalized_source);
        let source_root =
            source_root.parent().unwrap_or_else(|| source_root.deref());

        let path = source_root.join(get_path_from_bytes(pattern));
        let new_root = path.parent().unwrap_or_else(|| path.deref());

        let prefix = canonical_path(&root_dir, &root_dir, new_root)?;

        Ok(Self {
            prefix: path_to_hg_path_buf(prefix).and_then(|mut p| {
                if !p.is_empty() {
                    p.push(b'/');
                }
                Ok(p)
            })?,
            path: path.to_owned(),
            root: new_root.to_owned(),
        })
    }
}

/// Separate and pre-process subincludes from other patterns for the "ignore"
/// phase.
pub fn filter_subincludes(
    ignore_patterns: &[IgnorePattern],
    root_dir: impl AsRef<Path>,
) -> Result<(Vec<SubInclude>, Vec<&IgnorePattern>), HgPathError> {
    let mut subincludes = vec![];
    let mut others = vec![];

    for ignore_pattern in ignore_patterns.iter() {
        let IgnorePattern {
            syntax,
            pattern,
            source,
        } = ignore_pattern;
        if *syntax == PatternSyntax::SubInclude {
            subincludes.push(SubInclude::new(&root_dir, pattern, &source)?);
        } else {
            others.push(ignore_pattern)
        }
    }
    Ok((subincludes, others))
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn escape_pattern_test() {
        let untouched =
            br#"!"%',/0123456789:;<=>@ABCDEFGHIJKLMNOPQRSTUVWXYZ_`abcdefghijklmnopqrstuvwxyz"#;
        assert_eq!(escape_pattern(untouched), untouched.to_vec());
        // All escape codes
        assert_eq!(
            escape_pattern(br#"()[]{}?*+-|^$\\.&~# \t\n\r\v\f"#),
            br#"\(\)\[\]\{\}\?\*\+\-\|\^\$\\\\\.\&\~\#\ \\t\\n\\r\\v\\f"#
                .to_vec()
        );
    }

    #[test]
    fn glob_test() {
        assert_eq!(glob_to_re(br#"?"#), br#"."#);
        assert_eq!(glob_to_re(br#"*"#), br#"[^/]*"#);
        assert_eq!(glob_to_re(br#"**"#), br#".*"#);
        assert_eq!(glob_to_re(br#"**/a"#), br#"(?:.*/)?a"#);
        assert_eq!(glob_to_re(br#"a/**/b"#), br#"a/(?:.*/)?b"#);
        assert_eq!(glob_to_re(br#"[a*?!^][^b][!c]"#), br#"[a*?!^][\^b][^c]"#);
        assert_eq!(glob_to_re(br#"{a,b}"#), br#"(?:a|b)"#);
        assert_eq!(glob_to_re(br#".\*\?"#), br#"\.\*\?"#);
    }

    #[test]
    fn test_parse_pattern_file_contents() {
        let lines = b"syntax: glob\n*.elc";

        assert_eq!(
            parse_pattern_file_contents(lines, Path::new("file_path"), false)
                .unwrap()
                .0,
            vec![IgnorePattern::new(
                PatternSyntax::RelGlob,
                b"*.elc",
                Path::new("file_path")
            )],
        );

        let lines = b"syntax: include\nsyntax: glob";

        assert_eq!(
            parse_pattern_file_contents(lines, Path::new("file_path"), false)
                .unwrap()
                .0,
            vec![]
        );
        let lines = b"glob:**.o";
        assert_eq!(
            parse_pattern_file_contents(lines, Path::new("file_path"), false)
                .unwrap()
                .0,
            vec![IgnorePattern::new(
                PatternSyntax::RelGlob,
                b"**.o",
                Path::new("file_path")
            )]
        );
    }

    #[test]
    fn test_build_single_regex() {
        assert_eq!(
            build_single_regex(&IgnorePattern::new(
                PatternSyntax::RelGlob,
                b"rust/target/",
                Path::new("")
            ))
            .unwrap(),
            Some(br"(?:.*/)?rust/target(?:/|$)".to_vec()),
        );
        assert_eq!(
            build_single_regex(&IgnorePattern::new(
                PatternSyntax::Regexp,
                br"rust/target/\d+",
                Path::new("")
            ))
            .unwrap(),
            Some(br"rust/target/\d+".to_vec()),
        );
    }

    #[test]
    fn test_build_single_regex_shortcut() {
        assert_eq!(
            build_single_regex(&IgnorePattern::new(
                PatternSyntax::RootGlob,
                b"",
                Path::new("")
            ))
            .unwrap(),
            None,
        );
        assert_eq!(
            build_single_regex(&IgnorePattern::new(
                PatternSyntax::RootGlob,
                b"whatever",
                Path::new("")
            ))
            .unwrap(),
            None,
        );
        assert_eq!(
            build_single_regex(&IgnorePattern::new(
                PatternSyntax::RootGlob,
                b"*.o",
                Path::new("")
            ))
            .unwrap(),
            Some(br"[^/]*\.o(?:/|$)".to_vec()),
        );
    }
}

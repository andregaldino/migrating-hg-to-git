use crate::{
    utils::{files::get_path_from_bytes, replace_slice, SliceExt},
    LineNumber, PatternError, PatternFileError,
};
use lazy_static::lazy_static;
use regex::bytes::Regex;
use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
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

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum PatternSyntax {
    Regexp,
    /// Glob that matches at the front of the path
    RootGlob,
    /// Glob that matches at any suffix of the path (still anchored at slashes)
    Glob,
    Path,
    RelPath,
    RelGlob,
    RelRegexp,
    RootFiles,
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
                    if input.starts_with(source) {
                        input = &input[source.len()..];
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

fn parse_pattern_syntax(kind: &[u8]) -> Result<PatternSyntax, PatternError> {
    match kind {
        b"re" => Ok(PatternSyntax::Regexp),
        b"path" => Ok(PatternSyntax::Path),
        b"relpath" => Ok(PatternSyntax::RelPath),
        b"rootfilesin" => Ok(PatternSyntax::RootFiles),
        b"relglob" => Ok(PatternSyntax::RelGlob),
        b"relre" => Ok(PatternSyntax::RelRegexp),
        b"glob" => Ok(PatternSyntax::Glob),
        b"rootglob" => Ok(PatternSyntax::RootGlob),
        _ => Err(PatternError::UnsupportedSyntax(
            String::from_utf8_lossy(kind).to_string(),
        )),
    }
}

/// Builds the regex that corresponds to the given pattern.
/// If within a `syntax: regexp` context, returns the pattern,
/// otherwise, returns the corresponding regex.
fn _build_single_regex(
    syntax: PatternSyntax,
    pattern: &[u8],
    globsuffix: &[u8],
) -> Vec<u8> {
    if pattern.is_empty() {
        return vec![];
    }
    match syntax {
        PatternSyntax::Regexp => pattern.to_owned(),
        PatternSyntax::RelRegexp => {
            if pattern[0] == b'^' {
                return pattern.to_owned();
            }
            let mut res = b".*".to_vec();
            res.extend(pattern);
            res
        }
        PatternSyntax::Path | PatternSyntax::RelPath => {
            if pattern == b"." {
                return vec![];
            }
            let mut pattern = escape_pattern(pattern);
            pattern.extend(b"(?:/|$)");
            pattern
        }
        PatternSyntax::RootFiles => {
            let mut res = if pattern == b"." {
                vec![]
            } else {
                // Pattern is a directory name.
                let mut as_vec: Vec<u8> = escape_pattern(pattern);
                as_vec.push(b'/');
                as_vec
            };

            // Anything after the pattern must be a non-directory.
            res.extend(b"[^/]+$");
            res
        }
        PatternSyntax::Glob
        | PatternSyntax::RelGlob
        | PatternSyntax::RootGlob => {
            let mut res: Vec<u8> = vec![];
            if syntax == PatternSyntax::RelGlob {
                res.extend(b"(?:|.*/)");
            }

            res.extend(glob_to_re(pattern));
            res.extend(globsuffix.iter());
            res
        }
    }
}

const GLOB_SPECIAL_CHARACTERS: [u8; 7] =
    [b'*', b'?', b'[', b']', b'{', b'}', b'\\'];

/// Wrapper function to `_build_single_regex` that short-circuits 'exact' globs
/// that don't need to be transformed into a regex.
pub fn build_single_regex(
    kind: &[u8],
    pat: &[u8],
    globsuffix: &[u8],
) -> Result<Vec<u8>, PatternError> {
    let enum_kind = parse_pattern_syntax(kind)?;
    if enum_kind == PatternSyntax::RootGlob
        && !pat.iter().any(|b| GLOB_SPECIAL_CHARACTERS.contains(b))
    {
        let mut escaped = escape_pattern(pat);
        escaped.extend(b"(?:/|$)");
        Ok(escaped)
    } else {
        Ok(_build_single_regex(enum_kind, pat, globsuffix))
    }
}

lazy_static! {
    static ref SYNTAXES: HashMap<&'static [u8], &'static [u8]> = {
        let mut m = HashMap::new();

        m.insert(b"re".as_ref(), b"relre:".as_ref());
        m.insert(b"regexp".as_ref(), b"relre:".as_ref());
        m.insert(b"glob".as_ref(), b"relglob:".as_ref());
        m.insert(b"rootglob".as_ref(), b"rootglob:".as_ref());
        m.insert(b"include".as_ref(), b"include".as_ref());
        m.insert(b"subinclude".as_ref(), b"subinclude".as_ref());
        m
    };
}

pub type PatternTuple = (Vec<u8>, LineNumber, Vec<u8>);
type WarningTuple = (Vec<u8>, Vec<u8>);

pub fn parse_pattern_file_contents(
    lines: &[u8],
    file_path: &[u8],
    warn: bool,
) -> (Vec<PatternTuple>, Vec<WarningTuple>) {
    let comment_regex = Regex::new(r"((?:^|[^\\])(?:\\\\)*)#.*").unwrap();
    let mut inputs: Vec<PatternTuple> = vec![];
    let mut warnings: Vec<WarningTuple> = vec![];

    let mut current_syntax = b"relre:".as_ref();

    for (line_number, mut line) in lines.split(|c| *c == b'\n').enumerate() {
        let line_number = line_number + 1;

        if line.contains(&b'#') {
            if let Some(cap) = comment_regex.captures(line) {
                line = &line[..cap.get(1).unwrap().end()]
            }
            let mut line = line.to_owned();
            replace_slice(&mut line, br"\#", b"#");
        }

        let mut line = line.trim_end();

        if line.is_empty() {
            continue;
        }

        if line.starts_with(b"syntax:") {
            let syntax = line[b"syntax:".len()..].trim();

            if let Some(rel_syntax) = SYNTAXES.get(syntax) {
                current_syntax = rel_syntax;
            } else if warn {
                warnings.push((file_path.to_owned(), syntax.to_owned()));
            }
            continue;
        }

        let mut line_syntax: &[u8] = &current_syntax;

        for (s, rels) in SYNTAXES.iter() {
            if line.starts_with(rels) {
                line_syntax = rels;
                line = &line[rels.len()..];
                break;
            } else if line.starts_with(&[s, b":".as_ref()].concat()) {
                line_syntax = rels;
                line = &line[s.len() + 1..];
                break;
            }
        }

        inputs.push((
            [line_syntax, line].concat(),
            line_number,
            line.to_owned(),
        ));
    }
    (inputs, warnings)
}

pub fn read_pattern_file(
    file_path: &[u8],
    warn: bool,
) -> Result<(Vec<PatternTuple>, Vec<WarningTuple>), PatternFileError> {
    let mut f = File::open(get_path_from_bytes(file_path))?;
    let mut contents = Vec::new();

    f.read_to_end(&mut contents)?;

    Ok(parse_pattern_file_contents(&contents, file_path, warn))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_pattern_test() {
        let untouched = br#"!"%',/0123456789:;<=>@ABCDEFGHIJKLMNOPQRSTUVWXYZ_`abcdefghijklmnopqrstuvwxyz"#;
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
            vec![(b"relglob:*.elc".to_vec(), 2, b"*.elc".to_vec())],
            parse_pattern_file_contents(lines, b"file_path", false).0,
        );

        let lines = b"syntax: include\nsyntax: glob";

        assert_eq!(
            parse_pattern_file_contents(lines, b"file_path", false).0,
            vec![]
        );
        let lines = b"glob:**.o";
        assert_eq!(
            parse_pattern_file_contents(lines, b"file_path", false).0,
            vec![(b"relglob:**.o".to_vec(), 1, b"**.o".to_vec())]
        );
    }

    #[test]
    fn test_build_single_regex_shortcut() {
        assert_eq!(
            br"(?:/|$)".to_vec(),
            build_single_regex(b"rootglob", b"", b"").unwrap()
        );
        assert_eq!(
            br"whatever(?:/|$)".to_vec(),
            build_single_regex(b"rootglob", b"whatever", b"").unwrap()
        );
        assert_eq!(
            br"[^/]*\.o".to_vec(),
            build_single_regex(b"rootglob", b"*.o", b"").unwrap()
        );
    }
}

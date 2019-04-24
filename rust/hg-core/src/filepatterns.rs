use crate::{LineNumber, PatternError, PatternFileError};
use regex::Regex;
use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
use std::vec::Vec;

lazy_static! {
    static ref reescape: Vec<Vec<u8>> = {
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
                res.extend(&reescape[*c as usize])
            }
            _ => res.extend(&reescape[*c as usize]),
        }
    }
    res
}

fn escape_pattern(pattern: &[u8]) -> Vec<u8> {
    pattern
        .iter()
        .flat_map(|c| reescape[*c as usize].clone())
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
    kind: &str,
    pat: &[u8],
    globsuffix: &[u8],
) -> Result<Vec<u8>, PatternError> {
    let enum_kind = parse_pattern_syntax(kind.as_bytes())?;
    if enum_kind == PatternSyntax::RootGlob
        && pat.iter().all(|b| GLOB_SPECIAL_CHARACTERS.contains(b))
    {
        Ok(pat.to_vec())
    } else {
        Ok(_build_single_regex(enum_kind, pat, globsuffix))
    }
}

lazy_static! {
    static ref SYNTAXES: HashMap<&'static str, &'static str> = {
        let mut m = HashMap::new();

        m.insert("re", "relre:");
        m.insert("regexp", "relre:");
        m.insert("glob", "relglob:");
        m.insert("rootglob", "rootglob:");
        m.insert("include", "include");
        m.insert("subinclude", "subinclude");
        m
    };
}

pub type PatternTuple = (String, LineNumber, String);
type WarningTuple = (String, String);

pub fn parse_pattern_file_contents(
    lines: &str,
    file_path: &str,
    warn: bool,
) -> (Vec<PatternTuple>, Vec<WarningTuple>) {
    let comment_regex = Regex::new(r"((?:^|[^\\])(?:\\\\)*)#.*").unwrap();
    let mut inputs: Vec<PatternTuple> = vec![];
    let mut warnings: Vec<WarningTuple> = vec![];

    let mut current_syntax = "relre:";

    let mut line = String::new();
    for (line_number, line_str) in lines.split('\n').enumerate() {
        let line_number = line_number + 1;
        line.replace_range(.., line_str);

        if line.contains('#') {
            if let Some(cap) = comment_regex.captures(line.clone().as_ref()) {
                line = line[..cap.get(1).unwrap().end()].to_string()
            }
            line = line.replace(r"\#", "#");
        }

        let mut line = line.trim_end();

        if line.is_empty() {
            continue;
        }

        if line.starts_with("syntax:") {
            let syntax = line["syntax:".len()..].trim();

            if let Some(rel_syntax) = SYNTAXES.get(syntax) {
                current_syntax = rel_syntax;
            } else if warn {
                warnings.push((file_path.to_string(), syntax.to_string()));
            }
            continue;
        }

        let mut line_syntax: &str = &current_syntax;

        for (s, rels) in SYNTAXES.iter() {
            if line.starts_with(rels) {
                line_syntax = rels;
                line = &line[rels.len()..];
                break;
            } else if line.starts_with(&format!("{}:", s)) {
                line_syntax = rels;
                line = &line[s.len() + 1..];
                break;
            }
        }

        inputs.push((
            format!("{}{}", line_syntax, line),
            line_number,
            line.to_string(),
        ));
    }
    (inputs, warnings)
}

pub fn read_pattern_file(
    file_path: String,
    warn: bool,
) -> Result<(Vec<PatternTuple>, Vec<WarningTuple>), PatternFileError> {
    let mut f = File::open(&file_path)?;
    let mut contents = String::new();

    f.read_to_string(&mut contents)?;

    Ok(parse_pattern_file_contents(&contents, &file_path, warn))
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
        let lines = "syntax: glob\n*.elc";

        assert_eq!(
            vec![("relglob:*.elc".to_string(), 2, "*.elc".to_string())],
            parse_pattern_file_contents(lines, "file_path", false).0,
        );

        let lines = "syntax: include\nsyntax: glob";

        assert_eq!(
            parse_pattern_file_contents(lines, "file_path", false).0,
            vec![]
        );
    }
}

//! Parsing functions for various type of configuration values.
//!
//! Returning `None` indicates a syntax error. Using a `Result` would be more
//! correct but would take more boilerplate for converting between error types,
//! compared to using `.ok()` on inner results of various error types to
//! convert them all to options. The `Config::get_parse` method later converts
//! those options to results with `ConfigValueParseError`, which contains
//! details about where the value came from (but omits details of what’s
//! invalid inside the value).

use crate::utils::SliceExt;

pub(super) fn parse_bool(v: &[u8]) -> Option<bool> {
    match v.to_ascii_lowercase().as_slice() {
        b"1" | b"yes" | b"true" | b"on" | b"always" => Some(true),
        b"0" | b"no" | b"false" | b"off" | b"never" => Some(false),
        _ => None,
    }
}

pub(super) fn parse_byte_size(value: &[u8]) -> Option<u64> {
    let value = std::str::from_utf8(value).ok()?.to_ascii_lowercase();
    const UNITS: &[(&str, u64)] = &[
        ("g", 1 << 30),
        ("gb", 1 << 30),
        ("m", 1 << 20),
        ("mb", 1 << 20),
        ("k", 1 << 10),
        ("kb", 1 << 10),
        ("b", 1 << 0), // Needs to be last
    ];
    for &(unit, multiplier) in UNITS {
        // TODO: use `value.strip_suffix(unit)` when we require Rust 1.45+
        if value.ends_with(unit) {
            let value_before_unit = &value[..value.len() - unit.len()];
            let float: f64 = value_before_unit.trim().parse().ok()?;
            if float >= 0.0 {
                return Some((float * multiplier as f64).round() as u64);
            } else {
                return None;
            }
        }
    }
    value.parse().ok()
}

/// Parse a config value as a list of sub-values.
///
/// Ported from `parselist` in `mercurial/utils/stringutil.py`

// Note: keep behavior in sync with the Python one.

// Note: this could return `Vec<Cow<[u8]>>` instead and borrow `input` when
// possible (when there’s no backslash-escapes) but this is probably not worth
// the complexity as config is presumably not accessed inside
// preformance-sensitive loops.
pub(super) fn parse_list(input: &[u8]) -> Vec<Vec<u8>> {
    // Port of Python’s `value.lstrip(b' ,\n')`
    // TODO: is this really what we want?
    let input =
        input.trim_start_matches(|b| b == b' ' || b == b',' || b == b'\n');
    parse_list_without_trim_start(input)
}

fn parse_list_without_trim_start(input: &[u8]) -> Vec<Vec<u8>> {
    // Start of port of Python’s `_configlist`
    let input = input.trim_end_matches(|b| b == b' ' || b == b',');
    if input.is_empty() {
        return Vec::new();
    }

    // Just to make “a string” less confusable with “a list of strings”.
    type ByteString = Vec<u8>;

    // These correspond to Python’s…
    let mut mode = ParserMode::Plain; // `parser`
    let mut values = Vec::new(); // `parts[:-1]`
    let mut next_value = ByteString::new(); // `parts[-1]`
    let mut offset = 0; // `offset`

    // Setting `parser` to `None` is instead handled by returning immediately
    enum ParserMode {
        Plain,
        Quoted,
    }

    loop {
        match mode {
            ParserMode::Plain => {
                // Start of port of Python’s `_parse_plain`
                let mut whitespace = false;
                while let Some(&byte) = input.get(offset) {
                    if is_space(byte) || byte == b',' {
                        whitespace = true;
                        offset += 1;
                    } else {
                        break;
                    }
                }
                if let Some(&byte) = input.get(offset) {
                    if whitespace {
                        values.push(std::mem::take(&mut next_value))
                    }
                    if byte == b'"' && next_value.is_empty() {
                        mode = ParserMode::Quoted;
                    } else {
                        if byte == b'"' && next_value.ends_with(b"\\") {
                            next_value.pop();
                        }
                        next_value.push(byte);
                    }
                    offset += 1;
                } else {
                    values.push(next_value);
                    return values;
                }
            }
            ParserMode::Quoted => {
                // Start of port of Python’s `_parse_quote`
                if let Some(&byte) = input.get(offset) {
                    if byte == b'"' {
                        // The input contains a quoted zero-length value `""`
                        debug_assert_eq!(next_value, b"");
                        values.push(std::mem::take(&mut next_value));
                        offset += 1;
                        while let Some(&byte) = input.get(offset) {
                            if is_space(byte) || byte == b',' {
                                offset += 1;
                            } else {
                                break;
                            }
                        }
                        mode = ParserMode::Plain;
                        continue;
                    }
                }

                while let Some(&byte) = input.get(offset) {
                    if byte == b'"' {
                        break;
                    }
                    if byte == b'\\' && input.get(offset + 1) == Some(&b'"') {
                        next_value.push(b'"');
                        offset += 2;
                    } else {
                        next_value.push(byte);
                        offset += 1;
                    }
                }

                if offset >= input.len() {
                    // We didn’t find a closing double-quote,
                    // so treat the opening one as part of an unquoted value
                    // instead of delimiting the start of a quoted value.

                    // `next_value` may have had some backslash-escapes
                    // unescaped. TODO: shouldn’t we use a slice of `input`
                    // instead?
                    let mut real_values =
                        parse_list_without_trim_start(&next_value);

                    if let Some(first) = real_values.first_mut() {
                        first.insert(0, b'"');
                        // Drop `next_value`
                        values.extend(real_values)
                    } else {
                        next_value.push(b'"');
                        values.push(next_value);
                    }
                    return values;
                }

                // We’re not at the end of the input, which means the `while`
                // loop above ended at at double quote. Skip
                // over that.
                offset += 1;

                while let Some(&byte) = input.get(offset) {
                    if byte == b' ' || byte == b',' {
                        offset += 1;
                    } else {
                        break;
                    }
                }

                if offset >= input.len() {
                    values.push(next_value);
                    return values;
                }

                if offset + 1 == input.len() && input[offset] == b'"' {
                    next_value.push(b'"');
                    offset += 1;
                } else {
                    values.push(std::mem::take(&mut next_value));
                }

                mode = ParserMode::Plain;
            }
        }
    }

    // https://docs.python.org/3/library/stdtypes.html?#bytes.isspace
    fn is_space(byte: u8) -> bool {
        if let b' ' | b'\t' | b'\n' | b'\r' | b'\x0b' | b'\x0c' = byte {
            true
        } else {
            false
        }
    }
}

#[test]
fn test_parse_list() {
    // Make `assert_eq` error messages nicer
    fn as_strings(values: &[Vec<u8>]) -> Vec<String> {
        values
            .iter()
            .map(|v| std::str::from_utf8(v.as_ref()).unwrap().to_owned())
            .collect()
    }
    macro_rules! assert_parse_list {
        ( $input: expr => [ $( $output: expr ),* ] ) => {
            assert_eq!(
                as_strings(&parse_list($input)),
                as_strings(&[ $( Vec::from(&$output[..]) ),* ]),
            );
        }
    }

    // Keep these Rust tests in sync with the Python ones in
    // `tests/test-config-parselist.py`
    assert_parse_list!(b"" => []);
    assert_parse_list!(b"," => []);
    assert_parse_list!(b"A" => [b"A"]);
    assert_parse_list!(b"B,B" => [b"B", b"B"]);
    assert_parse_list!(b", C, ,C," => [b"C", b"C"]);
    assert_parse_list!(b"\"" => [b"\""]);
    assert_parse_list!(b"\"\"" => [b"", b""]);
    assert_parse_list!(b"D,\"" => [b"D", b"\""]);
    assert_parse_list!(b"E,\"\"" => [b"E", b"", b""]);
    assert_parse_list!(b"\"F,F\"" => [b"F,F"]);
    assert_parse_list!(b"\"G,G" => [b"\"G", b"G"]);
    assert_parse_list!(b"\"H \\\",\\\"H" => [b"\"H", b",", b"H"]);
    assert_parse_list!(b"I,I\"" => [b"I", b"I\""]);
    assert_parse_list!(b"J,\"J" => [b"J", b"\"J"]);
    assert_parse_list!(b"K K" => [b"K", b"K"]);
    assert_parse_list!(b"\"K\" K" => [b"K", b"K"]);
    assert_parse_list!(b"L\tL" => [b"L", b"L"]);
    assert_parse_list!(b"\"L\"\tL" => [b"L", b"", b"L"]);
    assert_parse_list!(b"M\x0bM" => [b"M", b"M"]);
    assert_parse_list!(b"\"M\"\x0bM" => [b"M", b"", b"M"]);
    assert_parse_list!(b"\"N\"  , ,\"" => [b"N\""]);
    assert_parse_list!(b"\" ,O,  " => [b"\"", b"O"]);
}

#[test]
fn test_parse_byte_size() {
    assert_eq!(parse_byte_size(b""), None);
    assert_eq!(parse_byte_size(b"b"), None);

    assert_eq!(parse_byte_size(b"12"), Some(12));
    assert_eq!(parse_byte_size(b"12b"), Some(12));
    assert_eq!(parse_byte_size(b"12 b"), Some(12));
    assert_eq!(parse_byte_size(b"12.1 b"), Some(12));
    assert_eq!(parse_byte_size(b"1.1 K"), Some(1126));
    assert_eq!(parse_byte_size(b"1.1 kB"), Some(1126));

    assert_eq!(parse_byte_size(b"-12 b"), None);
    assert_eq!(parse_byte_size(b"-0.1 b"), None);
    assert_eq!(parse_byte_size(b"0.1 b"), Some(0));
    assert_eq!(parse_byte_size(b"12.1 b"), Some(12));
}

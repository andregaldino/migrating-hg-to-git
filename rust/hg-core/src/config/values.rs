//! Parsing functions for various type of configuration values.
//!
//! Returning `None` indicates a syntax error. Using a `Result` would be more
//! correct but would take more boilerplate for converting between error types,
//! compared to using `.ok()` on inner results of various error types to
//! convert them all to options. The `Config::get_parse` method later converts
//! those options to results with `ConfigValueParseError`, which contains
//! details about where the value came from (but omits details of what’s
//! invalid inside the value).

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

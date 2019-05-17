// filepatterns.rs
//
// Copyright 2019, Georges Racinet <gracinet@anybox.fr>,
// Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::filepatterns` module provided by the
//! `hg-core` crate. From Python, this will be seen as `rustext.filepatterns`
//! and can be used as replacement for the the pure `filepatterns` Python module.
//!
use cpython::{
    exc, PyDict, PyErr, PyModule, PyResult, PyString, PyTuple, Python,
    ToPyObject,
};
use hg::{build_single_regex, read_pattern_file, PatternTuple};
use exceptions::{
    PatternError,
    PatternFileError,
};

/// Rust does not like functions with different return signatures.
/// The 3-tuple version is always returned by the hg-core function,
/// the (potential) conversion is handled at this level since it is not likely
/// to have any measurable impact on performance.
///
/// The Python implementation passes a function reference for `warn` instead
/// of a boolean that is used to emit warnings while parsing. The Rust
/// implementation chooses to accumulate the warnings and propagate them to
/// Python upon completion. See the `readpatternfile` function in `match.py`
/// for more details.
fn read_pattern_file_wrapper(
    py: Python,
    file_path: String,
    warn: bool,
    source_info: bool,
) -> PyResult<PyTuple> {
    match read_pattern_file(file_path, warn) {
        Ok((patterns, warnings)) => {
            if source_info {
                return Ok((patterns, warnings).to_py_object(py));
            }
            let itemgetter = |x: &PatternTuple| x.0.to_py_object(py);
            let results: Vec<PyString> =
                patterns.iter().map(itemgetter).collect();
            Ok((results, warnings).to_py_object(py))
        }
        Err(e) => Err(PatternFileError::pynew(py, e)),
    }
}

fn build_single_regex_wrapper(
    py: Python,
    kind: String,
    pat: String,
    globsuffix: String,
) -> PyResult<PyString> {
    match build_single_regex(
        kind.as_ref(),
        pat.as_bytes(),
        globsuffix.as_bytes(),
    ) {
        Ok(regex) => match String::from_utf8(regex) {
            Ok(regex) => Ok(regex.to_py_object(py)),
            Err(e) => Err(PyErr::new::<exc::UnicodeDecodeError, _>(
                py,
                e.to_string(),
            )),
        },
        Err(e) => Err(PatternError::pynew(py, e)),
    }
}

pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.filepatterns", package);
    let m = PyModule::new(py, dotted_name)?;

    m.add(py, "__package__", package)?;
    m.add(
        py,
        "__doc__",
        "Patterns files parsing - Rust implementation",
    )?;
    m.add(
        py,
        "build_single_regex",
        py_fn!(
            py,
            build_single_regex_wrapper(
                kind: String,
                pat: String,
                globsuffix: String
            )
        ),
    )?;
    m.add(
        py,
        "read_pattern_file",
        py_fn!(
            py,
            read_pattern_file_wrapper(
                file_path: String,
                warn: bool,
                source_info: bool
            )
        ),
    )?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;

    Ok(m)
}

// filepatterns.rs
//
// Copyright 2019, Georges Racinet <gracinet@anybox.fr>,
// Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::filepatterns` module provided by the
//! `hg-core` crate. From Python, this will be seen as `rustext.filepatterns`
//! and can be used as replacement for the the pure `filepatterns` Python
//! module.
//!
use crate::exceptions::{PatternError, PatternFileError};
use cpython::{
    PyBytes, PyDict, PyModule, PyObject, PyResult, PyString, PyTuple, Python,
    ToPyObject,
};
use hg::{
    build_single_regex, read_pattern_file, utils::files::get_path_from_bytes,
    LineNumber, PatternTuple,
};
use std::path::PathBuf;

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
    file_path: PyObject,
    warn: bool,
    source_info: bool,
) -> PyResult<PyTuple> {
    let bytes = file_path.extract::<PyBytes>(py)?;
    let path = get_path_from_bytes(bytes.data(py));
    match read_pattern_file(path, warn) {
        Ok((patterns, warnings)) => {
            if source_info {
                let itemgetter = |x: &PatternTuple| {
                    (PyBytes::new(py, &x.0), x.1, PyBytes::new(py, &x.2))
                };
                let results: Vec<(PyBytes, LineNumber, PyBytes)> =
                    patterns.iter().map(itemgetter).collect();
                return Ok((results, warnings_to_py_bytes(py, &warnings))
                    .to_py_object(py));
            }
            let itemgetter = |x: &PatternTuple| PyBytes::new(py, &x.0);
            let results: Vec<PyBytes> =
                patterns.iter().map(itemgetter).collect();
            Ok(
                (results, warnings_to_py_bytes(py, &warnings))
                    .to_py_object(py),
            )
        }
        Err(e) => Err(PatternFileError::pynew(py, e)),
    }
}

fn warnings_to_py_bytes(
    py: Python,
    warnings: &[(PathBuf, Vec<u8>)],
) -> Vec<(PyString, PyBytes)> {
    warnings
        .iter()
        .map(|(path, syn)| {
            (
                PyString::new(py, &path.to_string_lossy()),
                PyBytes::new(py, syn),
            )
        })
        .collect()
}

fn build_single_regex_wrapper(
    py: Python,
    kind: PyObject,
    pat: PyObject,
    globsuffix: PyObject,
) -> PyResult<PyBytes> {
    match build_single_regex(
        kind.extract::<PyBytes>(py)?.data(py),
        pat.extract::<PyBytes>(py)?.data(py),
        globsuffix.extract::<PyBytes>(py)?.data(py),
    ) {
        Ok(regex) => Ok(PyBytes::new(py, &regex)),
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
                kind: PyObject,
                pat: PyObject,
                globsuffix: PyObject
            )
        ),
    )?;
    m.add(
        py,
        "read_pattern_file",
        py_fn!(
            py,
            read_pattern_file_wrapper(
                file_path: PyObject,
                warn: bool,
                source_info: bool
            )
        ),
    )?;
    m.add(py, "PatternError", py.get_type::<PatternError>())?;
    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;

    Ok(m)
}

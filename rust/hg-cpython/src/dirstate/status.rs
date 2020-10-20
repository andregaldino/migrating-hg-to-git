// status.rs
//
// Copyright 2019, Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::status` module provided by the
//! `hg-core` crate. From Python, this will be seen as
//! `rustext.dirstate.status`.

use crate::{dirstate::DirstateMap, exceptions::FallbackError};
use cpython::{
    exc::ValueError, ObjectProtocol, PyBytes, PyErr, PyList, PyObject,
    PyResult, PyTuple, Python, PythonObject, ToPyObject,
};
use hg::{
    matchers::{AlwaysMatcher, FileMatcher, IncludeMatcher},
    parse_pattern_syntax, status,
    utils::{
        files::{get_bytes_from_path, get_path_from_bytes},
        hg_path::{HgPath, HgPathBuf},
    },
    BadMatch, DirstateStatus, IgnorePattern, PatternFileWarning, StatusError,
    StatusOptions,
};
use std::borrow::{Borrow, Cow};

/// This will be useless once trait impls for collection are added to `PyBytes`
/// upstream.
fn collect_pybytes_list(
    py: Python,
    collection: &[impl AsRef<HgPath>],
) -> PyList {
    let list = PyList::new(py, &[]);

    for path in collection.iter() {
        list.append(
            py,
            PyBytes::new(py, path.as_ref().as_bytes()).into_object(),
        )
    }

    list
}

fn collect_bad_matches(
    py: Python,
    collection: &[(impl AsRef<HgPath>, BadMatch)],
) -> PyResult<PyList> {
    let list = PyList::new(py, &[]);

    let os = py.import("os")?;
    let get_error_message = |code: i32| -> PyResult<_> {
        os.call(
            py,
            "strerror",
            PyTuple::new(py, &[code.to_py_object(py).into_object()]),
            None,
        )
    };

    for (path, bad_match) in collection.iter() {
        let message = match bad_match {
            BadMatch::OsError(code) => get_error_message(*code)?,
            BadMatch::BadType(bad_type) => format!(
                "unsupported file type (type is {})",
                bad_type.to_string()
            )
            .to_py_object(py)
            .into_object(),
        };
        list.append(
            py,
            (PyBytes::new(py, path.as_ref().as_bytes()), message)
                .to_py_object(py)
                .into_object(),
        )
    }

    Ok(list)
}

fn handle_fallback(py: Python, err: StatusError) -> PyErr {
    match err {
        StatusError::Pattern(e) => {
            let as_string = e.to_string();
            log::trace!("Rust status fallback: `{}`", &as_string);

            PyErr::new::<FallbackError, _>(py, &as_string)
        }
        e => PyErr::new::<ValueError, _>(py, e.to_string()),
    }
}

pub fn status_wrapper(
    py: Python,
    dmap: DirstateMap,
    matcher: PyObject,
    root_dir: PyObject,
    ignore_files: PyList,
    check_exec: bool,
    last_normal_time: i64,
    list_clean: bool,
    list_ignored: bool,
    list_unknown: bool,
    collect_traversed_dirs: bool,
) -> PyResult<PyTuple> {
    let bytes = root_dir.extract::<PyBytes>(py)?;
    let root_dir = get_path_from_bytes(bytes.data(py));

    let dmap: DirstateMap = dmap.to_py_object(py);
    let dmap = dmap.get_inner(py);

    let ignore_files: PyResult<Vec<_>> = ignore_files
        .iter(py)
        .map(|b| {
            let file = b.extract::<PyBytes>(py)?;
            Ok(get_path_from_bytes(file.data(py)).to_owned())
        })
        .collect();
    let ignore_files = ignore_files?;

    match matcher.get_type(py).name(py).borrow() {
        "alwaysmatcher" => {
            let matcher = AlwaysMatcher;
            let ((lookup, status_res), warnings) = status(
                &dmap,
                &matcher,
                root_dir.to_path_buf(),
                ignore_files,
                StatusOptions {
                    check_exec,
                    last_normal_time,
                    list_clean,
                    list_ignored,
                    list_unknown,
                    collect_traversed_dirs,
                },
            )
            .map_err(|e| handle_fallback(py, e))?;
            build_response(py, lookup, status_res, warnings)
        }
        "exactmatcher" => {
            let files = matcher.call_method(
                py,
                "files",
                PyTuple::new(py, &[]),
                None,
            )?;
            let files: PyList = files.cast_into(py)?;
            let files: PyResult<Vec<HgPathBuf>> = files
                .iter(py)
                .map(|f| {
                    Ok(HgPathBuf::from_bytes(
                        f.extract::<PyBytes>(py)?.data(py),
                    ))
                })
                .collect();

            let files = files?;
            let matcher = FileMatcher::new(files.as_ref())
                .map_err(|e| PyErr::new::<ValueError, _>(py, e.to_string()))?;
            let ((lookup, status_res), warnings) = status(
                &dmap,
                &matcher,
                root_dir.to_path_buf(),
                ignore_files,
                StatusOptions {
                    check_exec,
                    last_normal_time,
                    list_clean,
                    list_ignored,
                    list_unknown,
                    collect_traversed_dirs,
                },
            )
            .map_err(|e| handle_fallback(py, e))?;
            build_response(py, lookup, status_res, warnings)
        }
        "includematcher" => {
            // Get the patterns from Python even though most of them are
            // redundant with those we will parse later on, as they include
            // those passed from the command line.
            let ignore_patterns: PyResult<Vec<_>> = matcher
                .getattr(py, "_kindpats")?
                .iter(py)?
                .map(|k| {
                    let k = k?;
                    let syntax = parse_pattern_syntax(
                        &[
                            k.get_item(py, 0)?
                                .extract::<PyBytes>(py)?
                                .data(py),
                            &b":"[..],
                        ]
                        .concat(),
                    )
                    .map_err(|e| {
                        handle_fallback(py, StatusError::Pattern(e))
                    })?;
                    let pattern = k.get_item(py, 1)?.extract::<PyBytes>(py)?;
                    let pattern = pattern.data(py);
                    let source = k.get_item(py, 2)?.extract::<PyBytes>(py)?;
                    let source = get_path_from_bytes(source.data(py));
                    let new = IgnorePattern::new(syntax, pattern, source);
                    Ok(new)
                })
                .collect();

            let ignore_patterns = ignore_patterns?;
            let mut all_warnings = vec![];

            let (matcher, warnings) =
                IncludeMatcher::new(ignore_patterns, &root_dir)
                    .map_err(|e| handle_fallback(py, e.into()))?;
            all_warnings.extend(warnings);

            let ((lookup, status_res), warnings) = status(
                &dmap,
                &matcher,
                root_dir.to_path_buf(),
                ignore_files,
                StatusOptions {
                    check_exec,
                    last_normal_time,
                    list_clean,
                    list_ignored,
                    list_unknown,
                    collect_traversed_dirs,
                },
            )
            .map_err(|e| handle_fallback(py, e))?;

            all_warnings.extend(warnings);

            build_response(py, lookup, status_res, all_warnings)
        }
        e => Err(PyErr::new::<ValueError, _>(
            py,
            format!("Unsupported matcher {}", e),
        )),
    }
}

fn build_response(
    py: Python,
    lookup: Vec<Cow<HgPath>>,
    status_res: DirstateStatus,
    warnings: Vec<PatternFileWarning>,
) -> PyResult<PyTuple> {
    let modified = collect_pybytes_list(py, status_res.modified.as_ref());
    let added = collect_pybytes_list(py, status_res.added.as_ref());
    let removed = collect_pybytes_list(py, status_res.removed.as_ref());
    let deleted = collect_pybytes_list(py, status_res.deleted.as_ref());
    let clean = collect_pybytes_list(py, status_res.clean.as_ref());
    let ignored = collect_pybytes_list(py, status_res.ignored.as_ref());
    let unknown = collect_pybytes_list(py, status_res.unknown.as_ref());
    let lookup = collect_pybytes_list(py, lookup.as_ref());
    let bad = collect_bad_matches(py, status_res.bad.as_ref())?;
    let traversed = collect_pybytes_list(py, status_res.traversed.as_ref());
    let py_warnings = PyList::new(py, &[]);
    for warning in warnings.iter() {
        // We use duck-typing on the Python side for dispatch, good enough for
        // now.
        match warning {
            PatternFileWarning::InvalidSyntax(file, syn) => {
                py_warnings.append(
                    py,
                    (
                        PyBytes::new(py, &get_bytes_from_path(&file)),
                        PyBytes::new(py, syn),
                    )
                        .to_py_object(py)
                        .into_object(),
                );
            }
            PatternFileWarning::NoSuchFile(file) => py_warnings.append(
                py,
                PyBytes::new(py, &get_bytes_from_path(&file)).into_object(),
            ),
        }
    }

    Ok(PyTuple::new(
        py,
        &[
            lookup.into_object(),
            modified.into_object(),
            added.into_object(),
            removed.into_object(),
            deleted.into_object(),
            clean.into_object(),
            ignored.into_object(),
            unknown.into_object(),
            py_warnings.into_object(),
            bad.into_object(),
            traversed.into_object(),
        ][..],
    ))
}

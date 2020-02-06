// status.rs
//
// Copyright 2019, Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::status` module provided by the
//! `hg-core` crate. From Python, this will be seen as
//! `rustext.dirstate.status`.

use crate::dirstate::DirstateMap;
use cpython::exc::ValueError;
use cpython::{
    ObjectProtocol, PyBytes, PyErr, PyList, PyObject, PyResult, PyTuple,
    Python, PythonObject, ToPyObject,
};
use hg::utils::hg_path::HgPathBuf;
use hg::{
    matchers::{AlwaysMatcher, FileMatcher},
    status,
    utils::{files::get_path_from_bytes, hg_path::HgPath},
    DirstateStatus,
};
use std::borrow::Borrow;

/// This will be useless once trait impls for collection are added to `PyBytes`
/// upstream.
fn collect_pybytes_list<P: AsRef<HgPath>>(
    py: Python,
    collection: &[P],
) -> PyList {
    let list = PyList::new(py, &[]);

    for (i, path) in collection.iter().enumerate() {
        list.insert(
            py,
            i,
            PyBytes::new(py, path.as_ref().as_bytes()).into_object(),
        )
    }

    list
}

pub fn status_wrapper(
    py: Python,
    dmap: DirstateMap,
    matcher: PyObject,
    root_dir: PyObject,
    list_clean: bool,
    last_normal_time: i64,
    check_exec: bool,
) -> PyResult<(PyList, PyList, PyList, PyList, PyList, PyList, PyList)> {
    let bytes = root_dir.extract::<PyBytes>(py)?;
    let root_dir = get_path_from_bytes(bytes.data(py));

    let dmap: DirstateMap = dmap.to_py_object(py);
    let dmap = dmap.get_inner(py);

    match matcher.get_type(py).name(py).borrow() {
        "alwaysmatcher" => {
            let matcher = AlwaysMatcher;
            let (lookup, status_res) = status(
                &dmap,
                &matcher,
                &root_dir,
                list_clean,
                last_normal_time,
                check_exec,
            )
            .map_err(|e| PyErr::new::<ValueError, _>(py, e.to_string()))?;
            build_response(lookup, status_res, py)
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
            let matcher = FileMatcher::new(&files)
                .map_err(|e| PyErr::new::<ValueError, _>(py, e.to_string()))?;
            let (lookup, status_res) = status(
                &dmap,
                &matcher,
                &root_dir,
                list_clean,
                last_normal_time,
                check_exec,
            )
            .map_err(|e| PyErr::new::<ValueError, _>(py, e.to_string()))?;
            build_response(lookup, status_res, py)
        }
        e => {
            return Err(PyErr::new::<ValueError, _>(
                py,
                format!("Unsupported matcher {}", e),
            ));
        }
    }
}

fn build_response(
    lookup: Vec<&HgPath>,
    status_res: DirstateStatus,
    py: Python,
) -> PyResult<(PyList, PyList, PyList, PyList, PyList, PyList, PyList)> {
    let modified = collect_pybytes_list(py, status_res.modified.as_ref());
    let added = collect_pybytes_list(py, status_res.added.as_ref());
    let removed = collect_pybytes_list(py, status_res.removed.as_ref());
    let deleted = collect_pybytes_list(py, status_res.deleted.as_ref());
    let clean = collect_pybytes_list(py, status_res.clean.as_ref());
    let lookup = collect_pybytes_list(py, lookup.as_ref());
    let unknown = PyList::new(py, &[]);

    Ok((lookup, modified, added, removed, deleted, unknown, clean))
}

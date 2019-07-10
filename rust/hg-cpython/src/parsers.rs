// parsers.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::dirstate::parsers` module provided by the
//! `hg-core` package.
//!
//! From Python, this will be seen as `mercurial.rustext.parsers`
//!
use cpython::{
    exc, PyBytes, PyDict, PyErr, PyInt, PyModule, PyResult, PyTuple, Python,
    PythonObject, ToPyObject,
};
use hg::{
    pack_dirstate, parse_dirstate, CopyVecEntry, DirstateEntry,
    DirstatePackError, DirstateParents, DirstateParseError,
};
use std::collections::HashMap;

use libc::c_char;

use crate::dirstate::{decapsule_make_dirstate_tuple, extract_dirstate_vec};

fn parse_dirstate_wrapper(
    py: Python,
    dmap: PyDict,
    copymap: PyDict,
    st: PyBytes,
) -> PyResult<PyTuple> {
    match parse_dirstate(st.data(py)) {
        Ok((parents, dirstate_vec, copies)) => {
            for (filename, entry) in dirstate_vec {
                dmap.set_item(
                    py,
                    PyBytes::new(py, &filename[..]),
                    decapsule_make_dirstate_tuple(py)?(
                        entry.state as c_char,
                        entry.mode,
                        entry.size,
                        entry.mtime,
                    ),
                )?;
            }
            for CopyVecEntry { path, copy_path } in copies {
                copymap.set_item(
                    py,
                    PyBytes::new(py, path),
                    PyBytes::new(py, copy_path),
                )?;
            }
            Ok((PyBytes::new(py, parents.p1), PyBytes::new(py, parents.p2))
                .to_py_object(py))
        }
        Err(e) => Err(PyErr::new::<exc::ValueError, _>(
            py,
            match e {
                DirstateParseError::TooLittleData => {
                    "too little data for parents".to_string()
                }
                DirstateParseError::Overflow => {
                    "overflow in dirstate".to_string()
                }
                DirstateParseError::CorruptedEntry(e) => e,
            },
        )),
    }
}

fn pack_dirstate_wrapper(
    py: Python,
    dmap: PyDict,
    copymap: PyDict,
    pl: PyTuple,
    now: PyInt,
) -> PyResult<PyBytes> {
    let p1 = pl.get_item(py, 0).extract::<PyBytes>(py)?;
    let p1: &[u8] = p1.data(py);
    let p2 = pl.get_item(py, 1).extract::<PyBytes>(py)?;
    let p2: &[u8] = p2.data(py);

    let dirstate_vec = extract_dirstate_vec(py, &dmap)?;

    let copies: Result<HashMap<Vec<u8>, Vec<u8>>, PyErr> = copymap
        .items(py)
        .iter()
        .map(|(key, value)| {
            Ok((
                key.extract::<PyBytes>(py)?.data(py).to_owned(),
                value.extract::<PyBytes>(py)?.data(py).to_owned(),
            ))
        })
        .collect();

    match pack_dirstate(
        &dirstate_vec,
        &copies?,
        DirstateParents { p1, p2 },
        now.as_object().extract::<i32>(py)?,
    ) {
        Ok((packed, new_dirstate_vec)) => {
            for (
                filename,
                DirstateEntry {
                    state,
                    mode,
                    size,
                    mtime,
                },
            ) in new_dirstate_vec
            {
                dmap.set_item(
                    py,
                    PyBytes::new(py, &filename[..]),
                    decapsule_make_dirstate_tuple(py)?(
                        state as c_char,
                        mode,
                        size,
                        mtime,
                    ),
                )?;
            }
            Ok(PyBytes::new(py, &packed))
        }
        Err(error) => Err(PyErr::new::<exc::ValueError, _>(
            py,
            match error {
                DirstatePackError::CorruptedParent => {
                    "expected a 20-byte hash".to_string()
                }
                DirstatePackError::CorruptedEntry(e) => e,
                DirstatePackError::BadSize(expected, actual) => {
                    format!("bad dirstate size: {} != {}", actual, expected)
                }
            },
        )),
    }
}

/// Create the module, with `__package__` given from parent
pub fn init_parsers_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.parsers", package);
    let m = PyModule::new(py, dotted_name)?;

    m.add(py, "__package__", package)?;
    m.add(py, "__doc__", "Parsers - Rust implementation")?;

    m.add(
        py,
        "parse_dirstate",
        py_fn!(
            py,
            parse_dirstate_wrapper(dmap: PyDict, copymap: PyDict, st: PyBytes)
        ),
    )?;
    m.add(
        py,
        "pack_dirstate",
        py_fn!(
            py,
            pack_dirstate_wrapper(
                dmap: PyDict,
                copymap: PyDict,
                pl: PyTuple,
                now: PyInt
            )
        ),
    )?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;

    Ok(m)
}

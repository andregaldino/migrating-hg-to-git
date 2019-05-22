// dirstate.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::dirstate` module provided by the
//! `hg-core` package.
//!
//! From Python, this will be seen as `mercurial.rustext.dirstate`

use cpython::{
    exc, PyBytes, PyDict, PyErr, PyInt, PyModule, PyObject, PyResult,
    PySequence, PythonObject, PyTuple, Python, ToPyObject,
};
use hg::{
    pack_dirstate, parse_dirstate, CopyVecEntry, DirstateEntry,
    DirstatePackError, DirstateParents, DirstateParseError, DirstateVec,
};
use std::collections::HashMap;
use std::ffi::CStr;
#[cfg(feature = "python27")]
extern crate python27_sys as python_sys;
#[cfg(feature = "python3")]
extern crate python3_sys as python_sys;
use self::python_sys::PyCapsule_Import;
use libc::{c_char, c_int};
use std::mem::transmute;

/// C code uses a custom `dirstate_tuple` type, checks in multiple instances
/// for this type, and raises a Python `Exception` if the check does not pass.
/// Because this type differs only in name from the regular Python tuple, it
/// would be a good idea in the near future to remove it entirely to allow
/// for a pure Python tuple of the same effective structure to be used,
/// rendering this type and the capsule below useless.
type MakeDirstateTupleFn = extern "C" fn(
    state: c_char,
    mode: c_int,
    size: c_int,
    mtime: c_int,
) -> PyObject;

/// This is largely a copy/paste from cindex.rs, pending the merge of a
/// `py_capsule_fn!` macro in the rust-cpython project:
/// https://github.com/dgrunwald/rust-cpython/pull/169
fn decapsule_make_dirstate_tuple(py: Python) -> PyResult<MakeDirstateTupleFn> {
    unsafe {
        let caps_name = CStr::from_bytes_with_nul_unchecked(
            b"mercurial.cext.parsers.make_dirstate_tuple_CAPI\0",
        );
        let from_caps = PyCapsule_Import(caps_name.as_ptr(), 0);
        if from_caps.is_null() {
            return Err(PyErr::fetch(py));
        }
        Ok(transmute(from_caps))
    }
}

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

    let dirstate_vec: Result<DirstateVec, PyErr> = dmap
        .items(py)
        .iter()
        .map(|(filename, stats)| {
            let stats = stats.extract::<PySequence>(py)?;
            let state = stats.get_item(py, 0)?.extract::<PyBytes>(py)?;
            let state = state.data(py)[0] as i8;
            let mode = stats.get_item(py, 1)?.extract(py)?;
            let size = stats.get_item(py, 2)?.extract(py)?;
            let mtime = stats.get_item(py, 3)?.extract(py)?;
            let filename = filename.extract::<PyBytes>(py)?;
            let filename = filename.data(py);
            Ok((
                filename.to_owned(),
                DirstateEntry {
                    state,
                    mode,
                    size,
                    mtime,
                },
            ))
        })
        .collect();

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
        &dirstate_vec?,
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
                        state as c_char, mode, size, mtime,
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
pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.dirstate", package);
    let m = PyModule::new(py, dotted_name)?;
    m.add(py, "__package__", package)?;
    m.add(py, "__doc__", "Dirstate - Rust implementation")?;
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

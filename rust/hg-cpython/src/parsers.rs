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
use cpython::{
    exc, PyBytes, PyDict, PyErr, PyInt, PyModule, PyResult, PyTuple, Python,
    PythonObject, ToPyObject,
};
use hg::{
    pack_dirstate, parse_dirstate, utils::hg_path::HgPathBuf, DirstateEntry,
    DirstateParents, FastHashMap, PARENT_SIZE,
};
use std::convert::TryInto;

use crate::dirstate::{extract_dirstate, make_dirstate_tuple};
use std::time::Duration;

fn parse_dirstate_wrapper(
    py: Python,
    dmap: PyDict,
    copymap: PyDict,
    st: PyBytes,
) -> PyResult<PyTuple> {
    match parse_dirstate(st.data(py)) {
        Ok((parents, entries, copies)) => {
            let dirstate_map: FastHashMap<HgPathBuf, DirstateEntry> = entries
                .into_iter()
                .map(|(path, entry)| (path.to_owned(), entry))
                .collect();
            let copy_map: FastHashMap<HgPathBuf, HgPathBuf> = copies
                .into_iter()
                .map(|(path, copy)| (path.to_owned(), copy.to_owned()))
                .collect();

            for (filename, entry) in &dirstate_map {
                dmap.set_item(
                    py,
                    PyBytes::new(py, filename.as_bytes()),
                    make_dirstate_tuple(py, entry)?,
                )?;
            }
            for (path, copy_path) in copy_map {
                copymap.set_item(
                    py,
                    PyBytes::new(py, path.as_bytes()),
                    PyBytes::new(py, copy_path.as_bytes()),
                )?;
            }
            Ok(dirstate_parents_to_pytuple(py, parents))
        }
        Err(e) => Err(PyErr::new::<exc::ValueError, _>(py, e.to_string())),
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

    let mut dirstate_map = extract_dirstate(py, &dmap)?;

    let copies: Result<FastHashMap<HgPathBuf, HgPathBuf>, PyErr> = copymap
        .items(py)
        .iter()
        .map(|(key, value)| {
            Ok((
                HgPathBuf::from_bytes(key.extract::<PyBytes>(py)?.data(py)),
                HgPathBuf::from_bytes(value.extract::<PyBytes>(py)?.data(py)),
            ))
        })
        .collect();

    if p1.len() != PARENT_SIZE || p2.len() != PARENT_SIZE {
        return Err(PyErr::new::<exc::ValueError, _>(
            py,
            "expected a 20-byte hash".to_string(),
        ));
    }

    match pack_dirstate(
        &mut dirstate_map,
        &copies?,
        DirstateParents {
            p1: p1.try_into().unwrap(),
            p2: p2.try_into().unwrap(),
        },
        Duration::from_secs(now.as_object().extract::<u64>(py)?),
    ) {
        Ok(packed) => {
            for (filename, entry) in dirstate_map.iter() {
                dmap.set_item(
                    py,
                    PyBytes::new(py, filename.as_bytes()),
                    make_dirstate_tuple(py, &entry)?,
                )?;
            }
            Ok(PyBytes::new(py, &packed))
        }
        Err(error) => {
            Err(PyErr::new::<exc::ValueError, _>(py, error.to_string()))
        }
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

pub(crate) fn dirstate_parents_to_pytuple(
    py: Python,
    parents: &DirstateParents,
) -> PyTuple {
    let p1 = PyBytes::new(py, parents.p1.as_bytes());
    let p2 = PyBytes::new(py, parents.p2.as_bytes());
    (p1, p2).to_py_object(py)
}

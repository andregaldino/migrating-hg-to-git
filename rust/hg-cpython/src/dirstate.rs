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
mod copymap;
mod dirs_multiset;
mod dirstate_map;
mod non_normal_entries;
mod status;
use crate::{
    dirstate::{
        dirs_multiset::Dirs, dirstate_map::DirstateMap, status::status_wrapper,
    },
    exceptions,
};
use cpython::{
    exc, PyBytes, PyDict, PyErr, PyList, PyModule, PyObject, PyResult,
    PySequence, Python,
};
use hg::{
    utils::hg_path::HgPathBuf, DirstateEntry, DirstateParseError, EntryState,
    StateMap,
};
use libc::{c_char, c_int};
use std::convert::TryFrom;

// C code uses a custom `dirstate_tuple` type, checks in multiple instances
// for this type, and raises a Python `Exception` if the check does not pass.
// Because this type differs only in name from the regular Python tuple, it
// would be a good idea in the near future to remove it entirely to allow
// for a pure Python tuple of the same effective structure to be used,
// rendering this type and the capsule below useless.
py_capsule_fn!(
    from mercurial.cext.parsers import make_dirstate_tuple_CAPI
        as make_dirstate_tuple_capi
        signature (
            state: c_char,
            mode: c_int,
            size: c_int,
            mtime: c_int,
        ) -> *mut RawPyObject
);

pub fn make_dirstate_tuple(
    py: Python,
    entry: &DirstateEntry,
) -> PyResult<PyObject> {
    // might be silly to retrieve capsule function in hot loop
    let make = make_dirstate_tuple_capi::retrieve(py)?;

    let &DirstateEntry {
        state,
        mode,
        size,
        mtime,
    } = entry;
    // Explicitly go through u8 first, then cast to platform-specific `c_char`
    // because Into<u8> has a specific implementation while `as c_char` would
    // just do a naive enum cast.
    let state_code: u8 = state.into();

    let maybe_obj = unsafe {
        let ptr = make(state_code as c_char, mode, size, mtime);
        PyObject::from_owned_ptr_opt(py, ptr)
    };
    maybe_obj.ok_or_else(|| PyErr::fetch(py))
}

pub fn extract_dirstate(py: Python, dmap: &PyDict) -> Result<StateMap, PyErr> {
    dmap.items(py)
        .iter()
        .map(|(filename, stats)| {
            let stats = stats.extract::<PySequence>(py)?;
            let state = stats.get_item(py, 0)?.extract::<PyBytes>(py)?;
            let state = EntryState::try_from(state.data(py)[0]).map_err(
                |e: DirstateParseError| {
                    PyErr::new::<exc::ValueError, _>(py, e.to_string())
                },
            )?;
            let mode = stats.get_item(py, 1)?.extract(py)?;
            let size = stats.get_item(py, 2)?.extract(py)?;
            let mtime = stats.get_item(py, 3)?.extract(py)?;
            let filename = filename.extract::<PyBytes>(py)?;
            let filename = filename.data(py);
            Ok((
                HgPathBuf::from(filename.to_owned()),
                DirstateEntry {
                    state,
                    mode,
                    size,
                    mtime,
                },
            ))
        })
        .collect()
}

/// Create the module, with `__package__` given from parent
pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.dirstate", package);
    let m = PyModule::new(py, dotted_name)?;

    simple_logger::init_by_env();

    m.add(py, "__package__", package)?;
    m.add(py, "__doc__", "Dirstate - Rust implementation")?;

    m.add(
        py,
        "FallbackError",
        py.get_type::<exceptions::FallbackError>(),
    )?;
    m.add_class::<Dirs>(py)?;
    m.add_class::<DirstateMap>(py)?;
    m.add(
        py,
        "status",
        py_fn!(
            py,
            status_wrapper(
                dmap: DirstateMap,
                root_dir: PyObject,
                matcher: PyObject,
                ignorefiles: PyList,
                check_exec: bool,
                last_normal_time: i64,
                list_clean: bool,
                list_ignored: bool,
                list_unknown: bool
            )
        ),
    )?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;

    Ok(m)
}

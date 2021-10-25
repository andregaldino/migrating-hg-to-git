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
mod item;
mod status;
use self::item::DirstateItem;
use crate::{
    dirstate::{
        dirs_multiset::Dirs, dirstate_map::DirstateMap, status::status_wrapper,
    },
    exceptions,
};
use cpython::{PyBytes, PyDict, PyList, PyModule, PyObject, PyResult, Python};
use hg::dirstate_tree::on_disk::V2_FORMAT_MARKER;

/// Create the module, with `__package__` given from parent
pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.dirstate", package);
    let m = PyModule::new(py, dotted_name)?;

    env_logger::init();

    m.add(py, "__package__", package)?;
    m.add(py, "__doc__", "Dirstate - Rust implementation")?;

    m.add(
        py,
        "FallbackError",
        py.get_type::<exceptions::FallbackError>(),
    )?;
    m.add_class::<Dirs>(py)?;
    m.add_class::<DirstateMap>(py)?;
    m.add_class::<DirstateItem>(py)?;
    m.add(py, "V2_FORMAT_MARKER", PyBytes::new(py, V2_FORMAT_MARKER))?;
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
                list_clean: bool,
                list_ignored: bool,
                list_unknown: bool,
                collect_traversed_dirs: bool
            )
        ),
    )?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;

    Ok(m)
}

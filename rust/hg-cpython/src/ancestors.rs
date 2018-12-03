// ancestors.rs
//
// Copyright 2018 Georges Racinet <gracinet@anybox.fr>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the hg::ancestors module provided by the
//! `hg-core` crate. From Python, this will be seen as `rustext.ancestor`
use cpython::{PyDict, PyModule, PyResult, Python};

/// Create the module, with __package__ given from parent
pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.ancestor", package);
    let m = PyModule::new(py, dotted_name)?;
    m.add(py, "__package__", package)?;
    m.add(
        py,
        "__doc__",
        "Generic DAG ancestor algorithms - Rust implementation",
    )?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;
    // Example C code (see pyexpat.c and import.c) will "give away the
    // reference", but we won't because it will be consumed once the
    // Rust PyObject is dropped.
    Ok(m)
}

// lib.rs
//
// Copyright 2018 Georges Racinet <gracinet@anybox.fr>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Python bindings of `hg-core` objects using the `cpython` crate.
//! Once compiled, the resulting single shared library object can be placed in
//! the `mercurial` package directly as `rustext.so` or `rustext.dll`.
//! It holds several modules, so that from the point of view of Python,
//! it behaves as the `cext` package.
//!
//! Example:
//!
//! ```text
//! >>> from mercurial.rustext import ancestor
//! >>> ancestor.__doc__
//! 'Generic DAG ancestor algorithms - Rust implementation'
//! ```

#[macro_use]
extern crate cpython;
extern crate hg;
extern crate libc;

pub mod ancestors;
mod cindex;
pub mod exceptions;

py_module_initializer!(rustext, initrustext, PyInit_rustext, |py, m| {
    m.add(
        py,
        "__doc__",
        "Mercurial core concepts - Rust implementation",
    )?;

    let dotted_name: String = m.get(py, "__name__")?.extract(py)?;
    m.add(py, "ancestor", ancestors::init_module(py, &dotted_name)?)?;
    m.add(py, "GraphError", py.get_type::<exceptions::GraphError>())?;
    Ok(())
});

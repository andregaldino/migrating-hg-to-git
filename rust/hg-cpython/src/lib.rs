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

/// This crate uses nested private macros, `extern crate` is still needed in
/// 2018 edition.
#[macro_use]
extern crate cpython;

pub mod ancestors;
mod cindex;
mod conversion;
#[macro_use]
pub mod ref_sharing;
pub mod dagops;
pub mod dirstate;
pub mod discovery;
pub mod exceptions;
pub mod filepatterns;
pub mod parsers;
pub mod utils;

py_module_initializer!(rustext, initrustext, PyInit_rustext, |py, m| {
    m.add(
        py,
        "__doc__",
        "Mercurial core concepts - Rust implementation",
    )?;

    let dotted_name: String = m.get(py, "__name__")?.extract(py)?;
    m.add(py, "ancestor", ancestors::init_module(py, &dotted_name)?)?;
    m.add(py, "dagop", dagops::init_module(py, &dotted_name)?)?;
    m.add(py, "discovery", discovery::init_module(py, &dotted_name)?)?;
    m.add(py, "dirstate", dirstate::init_module(py, &dotted_name)?)?;
    m.add(
        py,
        "filepatterns",
        filepatterns::init_module(py, &dotted_name)?,
    )?;
    m.add(
        py,
        "parsers",
        parsers::init_parsers_module(py, &dotted_name)?,
    )?;
    m.add(py, "GraphError", py.get_type::<exceptions::GraphError>())?;
    m.add(
        py,
        "PatternFileError",
        py.get_type::<exceptions::PatternFileError>(),
    )?;
    m.add(
        py,
        "PatternError",
        py.get_type::<exceptions::PatternError>(),
    )?;
    Ok(())
});

#[cfg(not(any(feature = "python27-bin", feature = "python3-bin")))]
#[test]
#[ignore]
fn libpython_must_be_linked_to_run_tests() {
    // stub function to tell that some tests wouldn't run
}

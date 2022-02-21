// dagops.rs
//
// Copyright 2019 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::dagops` module provided by the
//! `hg-core` package.
//!
//! From Python, this will be seen as `mercurial.rustext.dagop`
use crate::{conversion::rev_pyiter_collect, exceptions::GraphError};
use cpython::{PyDict, PyModule, PyObject, PyResult, Python};
use hg::dagops;
use hg::Revision;
use std::collections::HashSet;
use vcsgraph::ancestors::node_rank;
use vcsgraph::graph::{Parents, Rank};

use crate::revlog::pyindex_to_graph;

/// Using the the `index`, return heads out of any Python iterable of Revisions
///
/// This is the Rust counterpart for `mercurial.dagop.headrevs`
pub fn headrevs(
    py: Python,
    index: PyObject,
    revs: PyObject,
) -> PyResult<HashSet<Revision>> {
    let mut as_set: HashSet<Revision> = rev_pyiter_collect(py, &revs)?;
    dagops::retain_heads(&pyindex_to_graph(py, index)?, &mut as_set)
        .map_err(|e| GraphError::pynew(py, e))?;
    Ok(as_set)
}

/// Computes the rank, i.e. the number of ancestors including itself,
/// of a node represented by its parents.
pub fn rank(
    py: Python,
    index: PyObject,
    p1r: Revision,
    p2r: Revision,
) -> PyResult<Rank> {
    node_rank(&pyindex_to_graph(py, index)?, &Parents([p1r, p2r]))
        .map_err(|e| GraphError::pynew_from_vcsgraph(py, e))
}

/// Create the module, with `__package__` given from parent
pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.dagop", package);
    let m = PyModule::new(py, dotted_name)?;
    m.add(py, "__package__", package)?;
    m.add(py, "__doc__", "DAG operations - Rust implementation")?;
    m.add(
        py,
        "headrevs",
        py_fn!(py, headrevs(index: PyObject, revs: PyObject)),
    )?;
    m.add(
        py,
        "rank",
        py_fn!(py, rank(index: PyObject, p1r: Revision, p2r: Revision)),
    )?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;
    // Example C code (see pyexpat.c and import.c) will "give away the
    // reference", but we won't because it will be consumed once the
    // Rust PyObject is dropped.
    Ok(m)
}

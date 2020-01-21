// discovery.rs
//
// Copyright 2018 Georges Racinet <gracinet@anybox.fr>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::discovery` module provided by the
//! `hg-core` crate. From Python, this will be seen as `rustext.discovery`
//!
//! # Classes visible from Python:
//! - [`PartialDiscover`] is the Rust implementation of
//!   `mercurial.setdiscovery.partialdiscovery`.

use crate::{
    cindex::Index, conversion::rev_pyiter_collect, exceptions::GraphError,
};
use cpython::{
    ObjectProtocol, PyDict, PyModule, PyObject, PyResult, PyTuple, Python,
    PythonObject, ToPyObject,
};
use hg::discovery::PartialDiscovery as CorePartialDiscovery;
use hg::Revision;
use std::collections::HashSet;

use std::cell::RefCell;

use crate::revlog::pyindex_to_graph;

py_class!(pub class PartialDiscovery |py| {
    data inner: RefCell<Box<CorePartialDiscovery<Index>>>;

    // `_respectsize` is currently only here to replicate the Python API and
    // will be used in future patches inside methods that are yet to be
    // implemented.
    def __new__(
        _cls,
        repo: PyObject,
        targetheads: PyObject,
        respectsize: bool,
        randomize: bool = true
    ) -> PyResult<PartialDiscovery> {
        let index = repo.getattr(py, "changelog")?.getattr(py, "index")?;
        Self::create_instance(
            py,
            RefCell::new(Box::new(CorePartialDiscovery::new(
                pyindex_to_graph(py, index)?,
                rev_pyiter_collect(py, &targetheads)?,
                respectsize,
                randomize,
            )))
        )
    }

    def addcommons(&self, commons: PyObject) -> PyResult<PyObject> {
        let mut inner = self.inner(py).borrow_mut();
        let commons_vec: Vec<Revision> = rev_pyiter_collect(py, &commons)?;
        inner.add_common_revisions(commons_vec)
            .map_err(|e| GraphError::pynew(py, e))?;
        Ok(py.None())
    }

    def addmissings(&self, missings: PyObject) -> PyResult<PyObject> {
        let mut inner = self.inner(py).borrow_mut();
        let missings_vec: Vec<Revision> = rev_pyiter_collect(py, &missings)?;
        inner.add_missing_revisions(missings_vec)
            .map_err(|e| GraphError::pynew(py, e))?;
        Ok(py.None())
    }

    def addinfo(&self, sample: PyObject) -> PyResult<PyObject> {
        let mut missing: Vec<Revision> = Vec::new();
        let mut common: Vec<Revision> = Vec::new();
        for info in sample.iter(py)? { // info is a pair (Revision, bool)
            let mut revknown = info?.iter(py)?;
            let rev: Revision = revknown.next().unwrap()?.extract(py)?;
            let known: bool = revknown.next().unwrap()?.extract(py)?;
            if known {
                common.push(rev);
            } else {
                missing.push(rev);
            }
        }
        let mut inner = self.inner(py).borrow_mut();
        inner.add_common_revisions(common)
            .map_err(|e| GraphError::pynew(py, e))?;
        inner.add_missing_revisions(missing)
            .map_err(|e| GraphError::pynew(py, e))?;
        Ok(py.None())
    }

    def hasinfo(&self) -> PyResult<bool> {
        Ok(self.inner(py).borrow().has_info())
    }

    def iscomplete(&self) -> PyResult<bool> {
        Ok(self.inner(py).borrow().is_complete())
    }

    def stats(&self) -> PyResult<PyDict> {
        let stats = self.inner(py).borrow().stats();
        let as_dict: PyDict = PyDict::new(py);
        as_dict.set_item(py, "undecided",
                         stats.undecided.map(
                             |l| l.to_py_object(py).into_object())
                             .unwrap_or_else(|| py.None()))?;
        Ok(as_dict)
    }

    def commonheads(&self) -> PyResult<HashSet<Revision>> {
        self.inner(py).borrow().common_heads()
            .map_err(|e| GraphError::pynew(py, e))
    }

    def takefullsample(&self, _headrevs: PyObject,
                       size: usize) -> PyResult<PyObject> {
        let mut inner = self.inner(py).borrow_mut();
        let sample = inner.take_full_sample(size)
            .map_err(|e| GraphError::pynew(py, e))?;
        let as_vec: Vec<PyObject> = sample
            .iter()
            .map(|rev| rev.to_py_object(py).into_object())
            .collect();
        Ok(PyTuple::new(py, as_vec.as_slice()).into_object())
    }

    def takequicksample(&self, headrevs: PyObject,
                        size: usize) -> PyResult<PyObject> {
        let mut inner = self.inner(py).borrow_mut();
        let revsvec: Vec<Revision> = rev_pyiter_collect(py, &headrevs)?;
        let sample = inner.take_quick_sample(revsvec, size)
            .map_err(|e| GraphError::pynew(py, e))?;
        let as_vec: Vec<PyObject> = sample
            .iter()
            .map(|rev| rev.to_py_object(py).into_object())
            .collect();
        Ok(PyTuple::new(py, as_vec.as_slice()).into_object())
    }

});

/// Create the module, with __package__ given from parent
pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.discovery", package);
    let m = PyModule::new(py, dotted_name)?;
    m.add(py, "__package__", package)?;
    m.add(
        py,
        "__doc__",
        "Discovery of common node sets - Rust implementation",
    )?;
    m.add_class::<PartialDiscovery>(py)?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;
    // Example C code (see pyexpat.c and import.c) will "give away the
    // reference", but we won't because it will be consumed once the
    // Rust PyObject is dropped.
    Ok(m)
}

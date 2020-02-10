// non_normal_other_parent_entries.rs
//
// Copyright 2020 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use cpython::{
    exc::NotImplementedError, CompareOp, ObjectProtocol, PyErr, PyList,
    PyObject, PyResult, PyString, Python, PythonObject, ToPyObject,
};

use crate::dirstate::DirstateMap;

py_class!(pub class NonNormalEntries |py| {
    data dmap: DirstateMap;

    def __contains__(&self, key: PyObject) -> PyResult<bool> {
        self.dmap(py).non_normal_entries_contains(py, key)
    }
    def remove(&self, key: PyObject) -> PyResult<PyObject> {
        self.dmap(py).non_normal_entries_remove(py, key)
    }
    def union(&self, other: PyObject) -> PyResult<PyList> {
        self.dmap(py).non_normal_entries_union(py, other)
    }
    def __richcmp__(&self, other: PyObject, op: CompareOp) -> PyResult<bool> {
        match op {
            CompareOp::Eq => self.is_equal_to(py, other),
            CompareOp::Ne => Ok(!self.is_equal_to(py, other)?),
            _ => Err(PyErr::new::<NotImplementedError, _>(py, ""))
        }
    }
    def __repr__(&self) -> PyResult<PyString> {
        self.dmap(py).non_normal_entries_display(py)
    }
});

impl NonNormalEntries {
    pub fn from_inner(py: Python, dm: DirstateMap) -> PyResult<Self> {
        Self::create_instance(py, dm)
    }

    fn is_equal_to(&self, py: Python, other: PyObject) -> PyResult<bool> {
        for item in other.iter(py)? {
            if !self.dmap(py).non_normal_entries_contains(py, item?)? {
                return Ok(false);
            }
        }
        Ok(true)
    }
}

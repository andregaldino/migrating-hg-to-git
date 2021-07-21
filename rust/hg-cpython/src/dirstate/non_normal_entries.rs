// non_normal_other_parent_entries.rs
//
// Copyright 2020 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use cpython::{
    exc::NotImplementedError, CompareOp, ObjectProtocol, PyBytes, PyClone,
    PyErr, PyObject, PyResult, PyString, Python, PythonObject, ToPyObject,
    UnsafePyLeaked,
};

use crate::dirstate::dirstate_map::v2_error;
use crate::dirstate::DirstateMap;
use hg::dirstate_tree::on_disk::DirstateV2ParseError;
use hg::utils::hg_path::HgPath;
use std::cell::RefCell;

py_class!(pub class NonNormalEntries |py| {
    data dmap: DirstateMap;

    def __contains__(&self, key: PyObject) -> PyResult<bool> {
        self.dmap(py).non_normal_entries_contains(py, key)
    }
    def remove(&self, key: PyObject) -> PyResult<PyObject> {
        self.dmap(py).non_normal_entries_remove(py, key)
    }
    def add(&self, key: PyObject) -> PyResult<PyObject> {
        self.dmap(py).non_normal_entries_add(py, key)
    }
    def discard(&self, key: PyObject) -> PyResult<PyObject> {
        self.dmap(py).non_normal_entries_discard(py, key)
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

    def __iter__(&self) -> PyResult<NonNormalEntriesIterator> {
        self.dmap(py).non_normal_entries_iter(py)
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

    fn translate_key(
        py: Python,
        key: Result<&HgPath, DirstateV2ParseError>,
    ) -> PyResult<Option<PyBytes>> {
        let key = key.map_err(|e| v2_error(py, e))?;
        Ok(Some(PyBytes::new(py, key.as_bytes())))
    }
}

type NonNormalEntriesIter<'a> = Box<
    dyn Iterator<Item = Result<&'a HgPath, DirstateV2ParseError>> + Send + 'a,
>;

py_shared_iterator!(
    NonNormalEntriesIterator,
    UnsafePyLeaked<NonNormalEntriesIter<'static>>,
    NonNormalEntries::translate_key,
    Option<PyBytes>
);

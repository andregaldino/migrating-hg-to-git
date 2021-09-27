// copymap.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for `hg::dirstate::dirstate_map::CopyMap` provided by the
//! `hg-core` package.

use cpython::{
    PyBytes, PyClone, PyDict, PyObject, PyResult, Python, UnsafePyLeaked,
};
use std::cell::RefCell;

use crate::dirstate::dirstate_map::v2_error;
use crate::dirstate::dirstate_map::DirstateMap;
use hg::dirstate::CopyMapIter;
use hg::dirstate_tree::on_disk::DirstateV2ParseError;
use hg::utils::hg_path::HgPath;

py_class!(pub class CopyMap |py| {
    data dirstate_map: DirstateMap;

    def __getitem__(&self, key: PyObject) -> PyResult<PyBytes> {
        (*self.dirstate_map(py)).copymapgetitem(py, key)
    }

    def __len__(&self) -> PyResult<usize> {
        self.dirstate_map(py).copymaplen(py)
    }

    def __contains__(&self, key: PyObject) -> PyResult<bool> {
        self.dirstate_map(py).copymapcontains(py, key)
    }

    def get(
        &self,
        key: PyObject,
        default: Option<PyObject> = None
    ) -> PyResult<Option<PyObject>> {
        self.dirstate_map(py).copymapget(py, key, default)
    }

    def pop(
        &self,
        key: PyObject,
        default: Option<PyObject> = None
    ) -> PyResult<Option<PyObject>> {
        self.dirstate_map(py).copymappop(py, key, default)
    }

    def __iter__(&self) -> PyResult<CopyMapKeysIterator> {
        self.dirstate_map(py).copymapiter(py)
    }

    // Python's `dict()` builtin works with either a subclass of dict
    // or an abstract mapping. Said mapping needs to implement `__getitem__`
    // and `keys`.
    def keys(&self) -> PyResult<CopyMapKeysIterator> {
        self.dirstate_map(py).copymapiter(py)
    }

    def items(&self) -> PyResult<CopyMapItemsIterator> {
        self.dirstate_map(py).copymapitemsiter(py)
    }

    def iteritems(&self) -> PyResult<CopyMapItemsIterator> {
        self.dirstate_map(py).copymapitemsiter(py)
    }

    def __setitem__(
        &self,
        key: PyObject,
        item: PyObject
    ) -> PyResult<()> {
        self.dirstate_map(py).copymapsetitem(py, key, item)?;
        Ok(())
    }

    def copy(&self) -> PyResult<PyDict> {
        self.dirstate_map(py).copymapcopy(py)
    }

});

impl CopyMap {
    pub fn from_inner(py: Python, dm: DirstateMap) -> PyResult<Self> {
        Self::create_instance(py, dm)
    }
    fn translate_key(
        py: Python,
        res: Result<(&HgPath, &HgPath), DirstateV2ParseError>,
    ) -> PyResult<Option<PyBytes>> {
        let (k, _v) = res.map_err(|e| v2_error(py, e))?;
        Ok(Some(PyBytes::new(py, k.as_bytes())))
    }
    fn translate_key_value(
        py: Python,
        res: Result<(&HgPath, &HgPath), DirstateV2ParseError>,
    ) -> PyResult<Option<(PyBytes, PyBytes)>> {
        let (k, v) = res.map_err(|e| v2_error(py, e))?;
        Ok(Some((
            PyBytes::new(py, k.as_bytes()),
            PyBytes::new(py, v.as_bytes()),
        )))
    }
}

py_shared_iterator!(
    CopyMapKeysIterator,
    UnsafePyLeaked<CopyMapIter<'static>>,
    CopyMap::translate_key,
    Option<PyBytes>
);

py_shared_iterator!(
    CopyMapItemsIterator,
    UnsafePyLeaked<CopyMapIter<'static>>,
    CopyMap::translate_key_value,
    Option<(PyBytes, PyBytes)>
);

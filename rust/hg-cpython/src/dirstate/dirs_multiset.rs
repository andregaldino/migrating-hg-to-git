// dirs_multiset.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::dirstate::dirs_multiset` file provided by the
//! `hg-core` package.

use std::cell::RefCell;
use std::convert::TryInto;

use cpython::{
    exc, ObjectProtocol, PyBytes, PyClone, PyDict, PyErr, PyObject, PyResult,
    Python,
};

use crate::{dirstate::extract_dirstate, ref_sharing::PySharedState};
use hg::{
    DirsIterable, DirsMultiset, DirstateMapError, DirstateParseError,
    EntryState,
};

py_class!(pub class Dirs |py| {
    data inner: RefCell<DirsMultiset>;
    data py_shared_state: PySharedState;

    // `map` is either a `dict` or a flat iterator (usually a `set`, sometimes
    // a `list`)
    def __new__(
        _cls,
        map: PyObject,
        skip: Option<PyObject> = None
    ) -> PyResult<Self> {
        let mut skip_state: Option<EntryState> = None;
        if let Some(skip) = skip {
            skip_state = Some(
                skip.extract::<PyBytes>(py)?.data(py)[0]
                    .try_into()
                    .map_err(|e: DirstateParseError| {
                        PyErr::new::<exc::ValueError, _>(py, e.to_string())
                    })?,
            );
        }
        let inner = if let Ok(map) = map.cast_as::<PyDict>(py) {
            let dirstate = extract_dirstate(py, &map)?;
            DirsMultiset::new(
                DirsIterable::Dirstate(&dirstate),
                skip_state,
            )
        } else {
            let map: Result<Vec<Vec<u8>>, PyErr> = map
                .iter(py)?
                .map(|o| Ok(o?.extract::<PyBytes>(py)?.data(py).to_owned()))
                .collect();
            DirsMultiset::new(
                DirsIterable::Manifest(&map?),
                skip_state,
            )
        };

        Self::create_instance(
            py,
            RefCell::new(inner),
            PySharedState::default()
        )
    }

    def addpath(&self, path: PyObject) -> PyResult<PyObject> {
        self.borrow_mut(py)?.add_path(
            path.extract::<PyBytes>(py)?.data(py),
        );
        Ok(py.None())
    }

    def delpath(&self, path: PyObject) -> PyResult<PyObject> {
        self.borrow_mut(py)?.delete_path(
            path.extract::<PyBytes>(py)?.data(py),
        )
            .and(Ok(py.None()))
            .or_else(|e| {
                match e {
                    DirstateMapError::PathNotFound(_p) => {
                        Err(PyErr::new::<exc::ValueError, _>(
                            py,
                            "expected a value, found none".to_string(),
                        ))
                    }
                    DirstateMapError::EmptyPath => {
                        Ok(py.None())
                    }
                }
            })
    }
    def __iter__(&self) -> PyResult<DirsMultisetKeysIterator> {
        DirsMultisetKeysIterator::create_instance(
            py,
            RefCell::new(Some(DirsMultisetLeakedRef::new(py, &self))),
            RefCell::new(Box::new(self.leak_immutable(py)?.iter())),
        )
    }

    def __contains__(&self, item: PyObject) -> PyResult<bool> {
        Ok(self
            .inner(py)
            .borrow()
            .contains(item.extract::<PyBytes>(py)?.data(py).as_ref()))
    }
});

py_shared_ref!(Dirs, DirsMultiset, inner, DirsMultisetLeakedRef,);

impl Dirs {
    pub fn from_inner(py: Python, d: DirsMultiset) -> PyResult<Self> {
        Self::create_instance(py, RefCell::new(d), PySharedState::default())
    }

    fn translate_key(py: Python, res: &Vec<u8>) -> PyResult<Option<PyBytes>> {
        Ok(Some(PyBytes::new(py, res)))
    }
}

py_shared_sequence_iterator!(
    DirsMultisetKeysIterator,
    DirsMultisetLeakedRef,
    Vec<u8>,
    Dirs::translate_key,
    Option<PyBytes>
);

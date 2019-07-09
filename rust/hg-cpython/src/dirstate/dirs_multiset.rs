// dirs_multiset.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::dirstate::dirs_multiset` file provided by the
//! `hg-core` package.

use std::cell::RefCell;

use cpython::{
    exc, ObjectProtocol, PyBytes, PyDict, PyErr, PyObject, PyResult,
    ToPyObject,
};

use crate::dirstate::extract_dirstate;
use hg::{
    DirsIterable, DirsMultiset, DirstateMapError, DirstateParseError,
    EntryState,
};
use std::convert::TryInto;

py_class!(pub class Dirs |py| {
    data dirs_map: RefCell<DirsMultiset>;

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

        Self::create_instance(py, RefCell::new(inner))
    }

    def addpath(&self, path: PyObject) -> PyResult<PyObject> {
        self.dirs_map(py).borrow_mut().add_path(
            path.extract::<PyBytes>(py)?.data(py),
        );
        Ok(py.None())
    }

    def delpath(&self, path: PyObject) -> PyResult<PyObject> {
        self.dirs_map(py).borrow_mut().delete_path(
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

    // This is really inefficient on top of being ugly, but it's an easy way
    // of having it work to continue working on the rest of the module
    // hopefully bypassing Python entirely pretty soon.
    def __iter__(&self) -> PyResult<PyObject> {
        let dict = PyDict::new(py);

        for (key, value) in self.dirs_map(py).borrow().iter() {
            dict.set_item(
                py,
                PyBytes::new(py, &key[..]),
                value.to_py_object(py),
            )?;
        }

        let locals = PyDict::new(py);
        locals.set_item(py, "obj", dict)?;

        py.eval("iter(obj)", None, Some(&locals))
    }

    def __contains__(&self, item: PyObject) -> PyResult<bool> {
        Ok(self
            .dirs_map(py)
            .borrow()
            .contains_key(item.extract::<PyBytes>(py)?.data(py).as_ref()))
    }
});

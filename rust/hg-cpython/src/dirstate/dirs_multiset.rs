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
    exc, ObjectProtocol, PyBytes, PyClone, PyDict, PyErr, PyObject, PyResult,
    Python, UnsafePyLeaked,
};

use hg::{
    utils::hg_path::{HgPath, HgPathBuf},
    DirsMultiset, DirsMultisetIter, DirstateMapError,
};

py_class!(pub class Dirs |py| {
    @shared data inner: DirsMultiset;

    // `map` is either a `dict` or a flat iterator (usually a `set`, sometimes
    // a `list`)
    def __new__(
        _cls,
        map: PyObject,
    ) -> PyResult<Self> {
        let inner = if map.cast_as::<PyDict>(py).is_ok() {
            let err = "pathutil.dirs() with a dict should only be used by the Python dirstatemap \
                and should not be used when Rust is enabled";
            return Err(PyErr::new::<exc::TypeError, _>(py, err.to_string()))
        } else {
            let map: Result<Vec<HgPathBuf>, PyErr> = map
                .iter(py)?
                .map(|o| {
                    Ok(HgPathBuf::from_bytes(
                        o?.extract::<PyBytes>(py)?.data(py),
                    ))
                })
                .collect();
            DirsMultiset::from_manifest(&map?)
                .map_err(|e| {
                    PyErr::new::<exc::ValueError, _>(py, e.to_string())
                })?
        };

        Self::create_instance(py, inner)
    }

    def addpath(&self, path: PyObject) -> PyResult<PyObject> {
        self.inner(py).borrow_mut().add_path(
            HgPath::new(path.extract::<PyBytes>(py)?.data(py)),
        ).and(Ok(py.None())).or_else(|e| {
            match e {
                DirstateMapError::EmptyPath => {
                    Ok(py.None())
                },
                e => {
                    Err(PyErr::new::<exc::ValueError, _>(
                        py,
                        e.to_string(),
                    ))
                }
            }
        })
    }

    def delpath(&self, path: PyObject) -> PyResult<PyObject> {
        self.inner(py).borrow_mut().delete_path(
            HgPath::new(path.extract::<PyBytes>(py)?.data(py)),
        )
            .and(Ok(py.None()))
            .or_else(|e| {
                match e {
                    DirstateMapError::EmptyPath => {
                        Ok(py.None())
                    },
                    e => {
                        Err(PyErr::new::<exc::ValueError, _>(
                            py,
                            e.to_string(),
                        ))
                    }
                }
            })
    }
    def __iter__(&self) -> PyResult<DirsMultisetKeysIterator> {
        let leaked_ref = self.inner(py).leak_immutable();
        DirsMultisetKeysIterator::from_inner(
            py,
            unsafe { leaked_ref.map(py, |o| o.iter()) },
        )
    }

    def __contains__(&self, item: PyObject) -> PyResult<bool> {
        Ok(self.inner(py).borrow().contains(HgPath::new(
            item.extract::<PyBytes>(py)?.data(py).as_ref(),
        )))
    }
});

impl Dirs {
    pub fn from_inner(py: Python, d: DirsMultiset) -> PyResult<Self> {
        Self::create_instance(py, d)
    }

    fn translate_key(
        py: Python,
        res: &HgPathBuf,
    ) -> PyResult<Option<PyBytes>> {
        Ok(Some(PyBytes::new(py, res.as_bytes())))
    }
}

py_shared_iterator!(
    DirsMultisetKeysIterator,
    UnsafePyLeaked<DirsMultisetIter<'static>>,
    Dirs::translate_key,
    Option<PyBytes>
);

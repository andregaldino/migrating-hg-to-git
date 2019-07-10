// dirstate_map.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::dirstate::dirstate_map` file provided by the
//! `hg-core` package.

use std::cell::RefCell;
use std::convert::TryInto;
use std::time::Duration;

use cpython::{
    exc, ObjectProtocol, PyBool, PyBytes, PyClone, PyDict, PyErr, PyObject,
    PyResult, PyTuple, Python, PythonObject, ToPyObject,
};
use libc::c_char;

use crate::{
    dirstate::copymap::{CopyMap, CopyMapItemsIterator, CopyMapKeysIterator},
    dirstate::{decapsule_make_dirstate_tuple, dirs_multiset::Dirs},
    ref_sharing::PySharedState,
};
use hg::{
    utils::copy_into_array, DirsIterable, DirsMultiset, DirstateEntry,
    DirstateMap as RustDirstateMap, DirstateParents, DirstateParseError,
    EntryState,
};

// TODO
//     This object needs to share references to multiple members of its Rust
//     inner struct, namely `copy_map`, `dirs` and `all_dirs`.
//     Right now `CopyMap` is done, but it needs to have an explicit reference
//     to `RustDirstateMap` which itself needs to have an encapsulation for
//     every method in `CopyMap` (copymapcopy, etc.).
//     This is ugly and hard to maintain.
//     The same logic applies to `dirs` and `all_dirs`, however the `Dirs`
//     `py_class!` is already implemented and does not mention
//     `RustDirstateMap`, rightfully so.
//     All attributes also have to have a separate refcount data attribute for
//     leaks, with all methods that go along for reference sharing.
py_class!(pub class DirstateMap |py| {
    data inner: RefCell<RustDirstateMap>;
    data py_shared_state: PySharedState;

    def __new__(_cls, _root: PyObject) -> PyResult<Self> {
        let inner = RustDirstateMap::default();
        Self::create_instance(
            py,
            RefCell::new(inner),
            PySharedState::default()
        )
    }

    def clear(&self) -> PyResult<PyObject> {
        self.borrow_mut(py)?.clear();
        Ok(py.None())
    }

    def get(
        &self,
        key: PyObject,
        default: Option<PyObject> = None
    ) -> PyResult<Option<PyObject>> {
        let key = key.extract::<PyBytes>(py)?;
        match self.inner(py).borrow().get(key.data(py)) {
            Some(entry) => {
                // Explicitly go through u8 first, then cast to
                // platform-specific `c_char`.
                let state: u8 = entry.state.into();
                Ok(Some(decapsule_make_dirstate_tuple(py)?(
                        state as c_char,
                        entry.mode,
                        entry.size,
                        entry.mtime,
                    )))
            },
            None => Ok(default)
        }
    }

    def addfile(
        &self,
        f: PyObject,
        oldstate: PyObject,
        state: PyObject,
        mode: PyObject,
        size: PyObject,
        mtime: PyObject
    ) -> PyResult<PyObject> {
        self.borrow_mut(py)?.add_file(
            f.extract::<PyBytes>(py)?.data(py),
            oldstate.extract::<PyBytes>(py)?.data(py)[0]
                .try_into()
                .map_err(|e: DirstateParseError| {
                    PyErr::new::<exc::ValueError, _>(py, e.to_string())
                })?,
            DirstateEntry {
                state: state.extract::<PyBytes>(py)?.data(py)[0]
                    .try_into()
                    .map_err(|e: DirstateParseError| {
                        PyErr::new::<exc::ValueError, _>(py, e.to_string())
                    })?,
                mode: mode.extract(py)?,
                size: size.extract(py)?,
                mtime: mtime.extract(py)?,
            },
        );
        Ok(py.None())
    }

    def removefile(
        &self,
        f: PyObject,
        oldstate: PyObject,
        size: PyObject
    ) -> PyResult<PyObject> {
        self.borrow_mut(py)?
            .remove_file(
                f.extract::<PyBytes>(py)?.data(py),
                oldstate.extract::<PyBytes>(py)?.data(py)[0]
                    .try_into()
                    .map_err(|e: DirstateParseError| {
                        PyErr::new::<exc::ValueError, _>(py, e.to_string())
                    })?,
                size.extract(py)?,
            )
            .or_else(|_| {
                Err(PyErr::new::<exc::OSError, _>(
                    py,
                    "Dirstate error".to_string(),
                ))
            })?;
        Ok(py.None())
    }

    def dropfile(
        &self,
        f: PyObject,
        oldstate: PyObject
    ) -> PyResult<PyBool> {
        self.borrow_mut(py)?
            .drop_file(
                f.extract::<PyBytes>(py)?.data(py),
                oldstate.extract::<PyBytes>(py)?.data(py)[0]
                    .try_into()
                    .map_err(|e: DirstateParseError| {
                        PyErr::new::<exc::ValueError, _>(py, e.to_string())
                    })?,
            )
            .and_then(|b| Ok(b.to_py_object(py)))
            .or_else(|_| {
                Err(PyErr::new::<exc::OSError, _>(
                    py,
                    "Dirstate error".to_string(),
                ))
            })
    }

    def clearambiguoustimes(
        &self,
        files: PyObject,
        now: PyObject
    ) -> PyResult<PyObject> {
        let files: PyResult<Vec<Vec<u8>>> = files
            .iter(py)?
            .map(|filename| {
                Ok(filename?.extract::<PyBytes>(py)?.data(py).to_owned())
            })
            .collect();
        self.inner(py)
            .borrow_mut()
            .clear_ambiguous_times(files?, now.extract(py)?);
        Ok(py.None())
    }

    // TODO share the reference
    def nonnormalentries(&self) -> PyResult<PyObject> {
        let (non_normal, other_parent) =
            self.inner(py).borrow().non_normal_other_parent_entries();

        let locals = PyDict::new(py);
        locals.set_item(
            py,
            "non_normal",
            non_normal
                .iter()
                .map(|v| PyBytes::new(py, &v))
                .collect::<Vec<PyBytes>>()
                .to_py_object(py),
        )?;
        locals.set_item(
            py,
            "other_parent",
            other_parent
                .iter()
                .map(|v| PyBytes::new(py, &v))
                .collect::<Vec<PyBytes>>()
                .to_py_object(py),
        )?;

        py.eval("set(non_normal), set(other_parent)", None, Some(&locals))
    }

    def hastrackeddir(&self, d: PyObject) -> PyResult<PyBool> {
        let d = d.extract::<PyBytes>(py)?;
        Ok(self
            .inner(py)
            .borrow_mut()
            .has_tracked_dir(d.data(py))
            .to_py_object(py))
    }

    def hasdir(&self, d: PyObject) -> PyResult<PyBool> {
        let d = d.extract::<PyBytes>(py)?;
        Ok(self
            .inner(py)
            .borrow_mut()
            .has_dir(d.data(py))
            .to_py_object(py))
    }

    def parents(&self, st: PyObject) -> PyResult<PyTuple> {
        self.inner(py)
            .borrow_mut()
            .parents(st.extract::<PyBytes>(py)?.data(py))
            .and_then(|d| {
                Ok((PyBytes::new(py, &d.p1), PyBytes::new(py, &d.p2))
                    .to_py_object(py))
            })
            .or_else(|_| {
                Err(PyErr::new::<exc::OSError, _>(
                    py,
                    "Dirstate error".to_string(),
                ))
            })
    }

    def setparents(&self, p1: PyObject, p2: PyObject) -> PyResult<PyObject> {
        let p1 = copy_into_array(p1.extract::<PyBytes>(py)?.data(py));
        let p2 = copy_into_array(p2.extract::<PyBytes>(py)?.data(py));

        self.inner(py)
            .borrow_mut()
            .set_parents(DirstateParents { p1, p2 });
        Ok(py.None())
    }

    def read(&self, st: PyObject) -> PyResult<Option<PyObject>> {
        match self
            .inner(py)
            .borrow_mut()
            .read(st.extract::<PyBytes>(py)?.data(py))
        {
            Ok(Some(parents)) => Ok(Some(
                (PyBytes::new(py, &parents.p1), PyBytes::new(py, &parents.p2))
                    .to_py_object(py)
                    .into_object(),
            )),
            Ok(None) => Ok(Some(py.None())),
            Err(_) => Err(PyErr::new::<exc::OSError, _>(
                py,
                "Dirstate error".to_string(),
            )),
        }
    }
    def write(
        &self,
        p1: PyObject,
        p2: PyObject,
        now: PyObject
    ) -> PyResult<PyBytes> {
        let now = Duration::new(now.extract(py)?, 0);
        let parents = DirstateParents {
            p1: copy_into_array(p1.extract::<PyBytes>(py)?.data(py)),
            p2: copy_into_array(p2.extract::<PyBytes>(py)?.data(py)),
        };

        match self.borrow_mut(py)?.pack(parents, now) {
            Ok(packed) => Ok(PyBytes::new(py, &packed)),
            Err(_) => Err(PyErr::new::<exc::OSError, _>(
                py,
                "Dirstate error".to_string(),
            )),
        }
    }

    def filefoldmapasdict(&self) -> PyResult<PyDict> {
        let dict = PyDict::new(py);
        for (key, value) in
            self.borrow_mut(py)?.build_file_fold_map().iter()
        {
            dict.set_item(py, key, value)?;
        }
        Ok(dict)
    }

    def __len__(&self) -> PyResult<usize> {
        Ok(self.inner(py).borrow().len())
    }

    def __contains__(&self, key: PyObject) -> PyResult<bool> {
        let key = key.extract::<PyBytes>(py)?;
        Ok(self.inner(py).borrow().contains_key(key.data(py)))
    }

    def __getitem__(&self, key: PyObject) -> PyResult<PyObject> {
        let key = key.extract::<PyBytes>(py)?;
        let key = key.data(py);
        match self.inner(py).borrow().get(key) {
            Some(entry) => {
                // Explicitly go through u8 first, then cast to
                // platform-specific `c_char`.
                let state: u8 = entry.state.into();
                Ok(decapsule_make_dirstate_tuple(py)?(
                        state as c_char,
                        entry.mode,
                        entry.size,
                        entry.mtime,
                    ))
            },
            None => Err(PyErr::new::<exc::KeyError, _>(
                py,
                String::from_utf8_lossy(key),
            )),
        }
    }

    def keys(&self) -> PyResult<DirstateMapKeysIterator> {
        DirstateMapKeysIterator::from_inner(
            py,
            Some(DirstateMapLeakedRef::new(py, &self)),
            Box::new(self.leak_immutable(py)?.iter()),
        )
    }

    def items(&self) -> PyResult<DirstateMapItemsIterator> {
        DirstateMapItemsIterator::from_inner(
            py,
            Some(DirstateMapLeakedRef::new(py, &self)),
            Box::new(self.leak_immutable(py)?.iter()),
        )
    }

    def __iter__(&self) -> PyResult<DirstateMapKeysIterator> {
        DirstateMapKeysIterator::from_inner(
            py,
            Some(DirstateMapLeakedRef::new(py, &self)),
            Box::new(self.leak_immutable(py)?.iter()),
        )
    }

    def getdirs(&self) -> PyResult<Dirs> {
        // TODO don't copy, share the reference
        self.inner(py).borrow_mut().set_dirs();
        Dirs::from_inner(
            py,
            DirsMultiset::new(
                DirsIterable::Dirstate(&self.inner(py).borrow()),
                Some(EntryState::Removed),
            ),
        )
    }
    def getalldirs(&self) -> PyResult<Dirs> {
        // TODO don't copy, share the reference
        self.inner(py).borrow_mut().set_all_dirs();
        Dirs::from_inner(
            py,
            DirsMultiset::new(
                DirsIterable::Dirstate(&self.inner(py).borrow()),
                None,
            ),
        )
    }

    // TODO all copymap* methods, see docstring above
    def copymapcopy(&self) -> PyResult<PyDict> {
        let dict = PyDict::new(py);
        for (key, value) in self.inner(py).borrow().copy_map.iter() {
            dict.set_item(py, PyBytes::new(py, key), PyBytes::new(py, value))?;
        }
        Ok(dict)
    }

    def copymapgetitem(&self, key: PyObject) -> PyResult<PyBytes> {
        let key = key.extract::<PyBytes>(py)?;
        match self.inner(py).borrow().copy_map.get(key.data(py)) {
            Some(copy) => Ok(PyBytes::new(py, copy)),
            None => Err(PyErr::new::<exc::KeyError, _>(
                py,
                String::from_utf8_lossy(key.data(py)),
            )),
        }
    }
    def copymap(&self) -> PyResult<CopyMap> {
        CopyMap::from_inner(py, self.clone_ref(py))
    }

    def copymaplen(&self) -> PyResult<usize> {
        Ok(self.inner(py).borrow().copy_map.len())
    }
    def copymapcontains(&self, key: PyObject) -> PyResult<bool> {
        let key = key.extract::<PyBytes>(py)?;
        Ok(self.inner(py).borrow().copy_map.contains_key(key.data(py)))
    }
    def copymapget(
        &self,
        key: PyObject,
        default: Option<PyObject>
    ) -> PyResult<Option<PyObject>> {
        let key = key.extract::<PyBytes>(py)?;
        match self.inner(py).borrow().copy_map.get(key.data(py)) {
            Some(copy) => Ok(Some(PyBytes::new(py, copy).into_object())),
            None => Ok(default),
        }
    }
    def copymapsetitem(
        &self,
        key: PyObject,
        value: PyObject
    ) -> PyResult<PyObject> {
        let key = key.extract::<PyBytes>(py)?;
        let value = value.extract::<PyBytes>(py)?;
        self.inner(py)
            .borrow_mut()
            .copy_map
            .insert(key.data(py).to_vec(), value.data(py).to_vec());
        Ok(py.None())
    }
    def copymappop(
        &self,
        key: PyObject,
        default: Option<PyObject>
    ) -> PyResult<Option<PyObject>> {
        let key = key.extract::<PyBytes>(py)?;
        match self.inner(py).borrow_mut().copy_map.remove(key.data(py)) {
            Some(_) => Ok(None),
            None => Ok(default),
        }
    }

    def copymapiter(&self) -> PyResult<CopyMapKeysIterator> {
        CopyMapKeysIterator::from_inner(
            py,
            Some(DirstateMapLeakedRef::new(py, &self)),
            Box::new(self.leak_immutable(py)?.copy_map.iter()),
        )
    }

    def copymapitemsiter(&self) -> PyResult<CopyMapItemsIterator> {
        CopyMapItemsIterator::from_inner(
            py,
            Some(DirstateMapLeakedRef::new(py, &self)),
            Box::new(self.leak_immutable(py)?.copy_map.iter()),
        )
    }

});

impl DirstateMap {
    fn translate_key(
        py: Python,
        res: (&Vec<u8>, &DirstateEntry),
    ) -> PyResult<Option<PyBytes>> {
        Ok(Some(PyBytes::new(py, res.0)))
    }
    fn translate_key_value(
        py: Python,
        res: (&Vec<u8>, &DirstateEntry),
    ) -> PyResult<Option<(PyBytes, PyObject)>> {
        let (f, entry) = res;

        // Explicitly go through u8 first, then cast to
        // platform-specific `c_char`.
        let state: u8 = entry.state.into();
        Ok(Some((
            PyBytes::new(py, f),
            decapsule_make_dirstate_tuple(py)?(
                state as c_char,
                entry.mode,
                entry.size,
                entry.mtime,
            ),
        )))
    }
}

py_shared_ref!(DirstateMap, RustDirstateMap, inner, DirstateMapLeakedRef,);

py_shared_mapping_iterator!(
    DirstateMapKeysIterator,
    DirstateMapLeakedRef,
    Vec<u8>,
    DirstateEntry,
    DirstateMap::translate_key,
    Option<PyBytes>
);

py_shared_mapping_iterator!(
    DirstateMapItemsIterator,
    DirstateMapLeakedRef,
    Vec<u8>,
    DirstateEntry,
    DirstateMap::translate_key_value,
    Option<(PyBytes, PyObject)>
);

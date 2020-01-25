// dirstate_map.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::dirstate::dirstate_map` file provided by the
//! `hg-core` package.

use std::cell::{Ref, RefCell};
use std::convert::TryInto;
use std::time::Duration;

use cpython::{
    exc, ObjectProtocol, PyBool, PyBytes, PyClone, PyDict, PyErr, PyObject,
    PyResult, PyTuple, Python, PythonObject, ToPyObject, UnsafePyLeaked,
};

use crate::{
    dirstate::copymap::{CopyMap, CopyMapItemsIterator, CopyMapKeysIterator},
    dirstate::{dirs_multiset::Dirs, make_dirstate_tuple},
};
use hg::{
    utils::hg_path::{HgPath, HgPathBuf},
    DirsMultiset, DirstateEntry, DirstateMap as RustDirstateMap,
    DirstateMapError, DirstateParents, DirstateParseError, EntryState,
    StateMapIter, PARENT_SIZE,
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
    @shared data inner: RustDirstateMap;

    def __new__(_cls, _root: PyObject) -> PyResult<Self> {
        let inner = RustDirstateMap::default();
        Self::create_instance(py, inner)
    }

    def clear(&self) -> PyResult<PyObject> {
        self.inner(py).borrow_mut().clear();
        Ok(py.None())
    }

    def get(
        &self,
        key: PyObject,
        default: Option<PyObject> = None
    ) -> PyResult<Option<PyObject>> {
        let key = key.extract::<PyBytes>(py)?;
        match self.inner(py).borrow().get(HgPath::new(key.data(py))) {
            Some(entry) => {
                Ok(Some(make_dirstate_tuple(py, entry)?))
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
        self.inner(py).borrow_mut().add_file(
            HgPath::new(f.extract::<PyBytes>(py)?.data(py)),
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
        ).and(Ok(py.None())).or_else(|e: DirstateMapError| {
            Err(PyErr::new::<exc::ValueError, _>(py, e.to_string()))
        })
    }

    def removefile(
        &self,
        f: PyObject,
        oldstate: PyObject,
        size: PyObject
    ) -> PyResult<PyObject> {
        self.inner(py).borrow_mut()
            .remove_file(
                HgPath::new(f.extract::<PyBytes>(py)?.data(py)),
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
        self.inner(py).borrow_mut()
            .drop_file(
                HgPath::new(f.extract::<PyBytes>(py)?.data(py)),
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
        let files: PyResult<Vec<HgPathBuf>> = files
            .iter(py)?
            .map(|filename| {
                Ok(HgPathBuf::from_bytes(
                    filename?.extract::<PyBytes>(py)?.data(py),
                ))
            })
            .collect();
        self.inner(py).borrow_mut()
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
                .map(|v| PyBytes::new(py, v.as_ref()))
                .collect::<Vec<PyBytes>>()
                .to_py_object(py),
        )?;
        locals.set_item(
            py,
            "other_parent",
            other_parent
                .iter()
                .map(|v| PyBytes::new(py, v.as_ref()))
                .collect::<Vec<PyBytes>>()
                .to_py_object(py),
        )?;

        py.eval("set(non_normal), set(other_parent)", None, Some(&locals))
    }

    def hastrackeddir(&self, d: PyObject) -> PyResult<PyBool> {
        let d = d.extract::<PyBytes>(py)?;
        Ok(self.inner(py).borrow_mut()
            .has_tracked_dir(HgPath::new(d.data(py)))
            .map_err(|e| {
                PyErr::new::<exc::ValueError, _>(py, e.to_string())
            })?
            .to_py_object(py))
    }

    def hasdir(&self, d: PyObject) -> PyResult<PyBool> {
        let d = d.extract::<PyBytes>(py)?;
        Ok(self.inner(py).borrow_mut()
            .has_dir(HgPath::new(d.data(py)))
            .map_err(|e| {
                PyErr::new::<exc::ValueError, _>(py, e.to_string())
            })?
            .to_py_object(py))
    }

    def parents(&self, st: PyObject) -> PyResult<PyTuple> {
        self.inner(py).borrow_mut()
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
        let p1 = extract_node_id(py, &p1)?;
        let p2 = extract_node_id(py, &p2)?;

        self.inner(py).borrow_mut()
            .set_parents(&DirstateParents { p1, p2 });
        Ok(py.None())
    }

    def read(&self, st: PyObject) -> PyResult<Option<PyObject>> {
        match self.inner(py).borrow_mut()
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
            p1: extract_node_id(py, &p1)?,
            p2: extract_node_id(py, &p2)?,
        };

        match self.inner(py).borrow_mut().pack(parents, now) {
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
            self.inner(py).borrow_mut().build_file_fold_map().iter()
        {
            dict.set_item(py, key.as_ref().to_vec(), value.as_ref().to_vec())?;
        }
        Ok(dict)
    }

    def __len__(&self) -> PyResult<usize> {
        Ok(self.inner(py).borrow().len())
    }

    def __contains__(&self, key: PyObject) -> PyResult<bool> {
        let key = key.extract::<PyBytes>(py)?;
        Ok(self.inner(py).borrow().contains_key(HgPath::new(key.data(py))))
    }

    def __getitem__(&self, key: PyObject) -> PyResult<PyObject> {
        let key = key.extract::<PyBytes>(py)?;
        let key = HgPath::new(key.data(py));
        match self.inner(py).borrow().get(key) {
            Some(entry) => {
                Ok(make_dirstate_tuple(py, entry)?)
            },
            None => Err(PyErr::new::<exc::KeyError, _>(
                py,
                String::from_utf8_lossy(key.as_bytes()),
            )),
        }
    }

    def keys(&self) -> PyResult<DirstateMapKeysIterator> {
        let leaked_ref = self.inner(py).leak_immutable();
        DirstateMapKeysIterator::from_inner(
            py,
            unsafe { leaked_ref.map(py, |o| o.iter()) },
        )
    }

    def items(&self) -> PyResult<DirstateMapItemsIterator> {
        let leaked_ref = self.inner(py).leak_immutable();
        DirstateMapItemsIterator::from_inner(
            py,
            unsafe { leaked_ref.map(py, |o| o.iter()) },
        )
    }

    def __iter__(&self) -> PyResult<DirstateMapKeysIterator> {
        let leaked_ref = self.inner(py).leak_immutable();
        DirstateMapKeysIterator::from_inner(
            py,
            unsafe { leaked_ref.map(py, |o| o.iter()) },
        )
    }

    def getdirs(&self) -> PyResult<Dirs> {
        // TODO don't copy, share the reference
        self.inner(py).borrow_mut().set_dirs()
            .map_err(|e| {
                PyErr::new::<exc::ValueError, _>(py, e.to_string())
            })?;
        Dirs::from_inner(
            py,
            DirsMultiset::from_dirstate(
                &self.inner(py).borrow(),
                Some(EntryState::Removed),
            )
            .map_err(|e| {
                PyErr::new::<exc::ValueError, _>(py, e.to_string())
            })?,
        )
    }
    def getalldirs(&self) -> PyResult<Dirs> {
        // TODO don't copy, share the reference
        self.inner(py).borrow_mut().set_all_dirs()
            .map_err(|e| {
                PyErr::new::<exc::ValueError, _>(py, e.to_string())
            })?;
        Dirs::from_inner(
            py,
            DirsMultiset::from_dirstate(
                &self.inner(py).borrow(),
                None,
            ).map_err(|e| {
                PyErr::new::<exc::ValueError, _>(py, e.to_string())
            })?,
        )
    }

    // TODO all copymap* methods, see docstring above
    def copymapcopy(&self) -> PyResult<PyDict> {
        let dict = PyDict::new(py);
        for (key, value) in self.inner(py).borrow().copy_map.iter() {
            dict.set_item(
                py,
                PyBytes::new(py, key.as_ref()),
                PyBytes::new(py, value.as_ref()),
            )?;
        }
        Ok(dict)
    }

    def copymapgetitem(&self, key: PyObject) -> PyResult<PyBytes> {
        let key = key.extract::<PyBytes>(py)?;
        match self.inner(py).borrow().copy_map.get(HgPath::new(key.data(py))) {
            Some(copy) => Ok(PyBytes::new(py, copy.as_ref())),
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
        Ok(self
            .inner(py)
            .borrow()
            .copy_map
            .contains_key(HgPath::new(key.data(py))))
    }
    def copymapget(
        &self,
        key: PyObject,
        default: Option<PyObject>
    ) -> PyResult<Option<PyObject>> {
        let key = key.extract::<PyBytes>(py)?;
        match self
            .inner(py)
            .borrow()
            .copy_map
            .get(HgPath::new(key.data(py)))
        {
            Some(copy) => Ok(Some(
                PyBytes::new(py, copy.as_ref()).into_object(),
            )),
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
        self.inner(py).borrow_mut().copy_map.insert(
            HgPathBuf::from_bytes(key.data(py)),
            HgPathBuf::from_bytes(value.data(py)),
        );
        Ok(py.None())
    }
    def copymappop(
        &self,
        key: PyObject,
        default: Option<PyObject>
    ) -> PyResult<Option<PyObject>> {
        let key = key.extract::<PyBytes>(py)?;
        match self
            .inner(py)
            .borrow_mut()
            .copy_map
            .remove(HgPath::new(key.data(py)))
        {
            Some(_) => Ok(None),
            None => Ok(default),
        }
    }

    def copymapiter(&self) -> PyResult<CopyMapKeysIterator> {
        let leaked_ref = self.inner(py).leak_immutable();
        CopyMapKeysIterator::from_inner(
            py,
            unsafe { leaked_ref.map(py, |o| o.copy_map.iter()) },
        )
    }

    def copymapitemsiter(&self) -> PyResult<CopyMapItemsIterator> {
        let leaked_ref = self.inner(py).leak_immutable();
        CopyMapItemsIterator::from_inner(
            py,
            unsafe { leaked_ref.map(py, |o| o.copy_map.iter()) },
        )
    }

});

impl DirstateMap {
    pub fn get_inner<'a>(
        &'a self,
        py: Python<'a>,
    ) -> Ref<'a, RustDirstateMap> {
        self.inner(py).borrow()
    }
    fn translate_key(
        py: Python,
        res: (&HgPathBuf, &DirstateEntry),
    ) -> PyResult<Option<PyBytes>> {
        Ok(Some(PyBytes::new(py, res.0.as_ref())))
    }
    fn translate_key_value(
        py: Python,
        res: (&HgPathBuf, &DirstateEntry),
    ) -> PyResult<Option<(PyBytes, PyObject)>> {
        let (f, entry) = res;
        Ok(Some((
            PyBytes::new(py, f.as_ref()),
            make_dirstate_tuple(py, entry)?,
        )))
    }
}

py_shared_iterator!(
    DirstateMapKeysIterator,
    UnsafePyLeaked<StateMapIter<'static>>,
    DirstateMap::translate_key,
    Option<PyBytes>
);

py_shared_iterator!(
    DirstateMapItemsIterator,
    UnsafePyLeaked<StateMapIter<'static>>,
    DirstateMap::translate_key_value,
    Option<(PyBytes, PyObject)>
);

fn extract_node_id(py: Python, obj: &PyObject) -> PyResult<[u8; PARENT_SIZE]> {
    let bytes = obj.extract::<PyBytes>(py)?;
    match bytes.data(py).try_into() {
        Ok(s) => Ok(s),
        Err(e) => Err(PyErr::new::<exc::ValueError, _>(py, e.to_string())),
    }
}

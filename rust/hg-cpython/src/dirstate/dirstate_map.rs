// dirstate_map.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::dirstate::dirstate_map` file provided by the
//! `hg-core` package.

use std::cell::{RefCell, RefMut};
use std::convert::TryInto;

use cpython::{
    exc, ObjectProtocol, PyBool, PyBytes, PyClone, PyDict, PyErr, PyList,
    PyObject, PyResult, PySet, PyString, Python, PythonObject, ToPyObject,
    UnsafePyLeaked,
};

use crate::{
    dirstate::copymap::{CopyMap, CopyMapItemsIterator, CopyMapKeysIterator},
    dirstate::non_normal_entries::{
        NonNormalEntries, NonNormalEntriesIterator,
    },
    dirstate::owning::OwningDirstateMap,
    dirstate::{dirs_multiset::Dirs, make_dirstate_tuple},
    parsers::dirstate_parents_to_pytuple,
};
use hg::{
    dirstate::parsers::Timestamp,
    dirstate_tree::dispatch::DirstateMapMethods,
    errors::HgError,
    revlog::Node,
    utils::files::normalize_case,
    utils::hg_path::{HgPath, HgPathBuf},
    DirsMultiset, DirstateEntry, DirstateError,
    DirstateMap as RustDirstateMap, DirstateMapError, DirstateParents,
    EntryState, StateMapIter,
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
    @shared data inner: Box<dyn DirstateMapMethods + Send>;

    /// Returns a `(dirstate_map, parents)` tuple
    @staticmethod
    def new(use_dirstate_tree: bool, on_disk: PyBytes) -> PyResult<PyObject> {
        let dirstate_error = |_: DirstateError| {
            PyErr::new::<exc::OSError, _>(py, "Dirstate error".to_string())
        };
        let (inner, parents) = if use_dirstate_tree {
            let (map, parents) =
                OwningDirstateMap::new(py, on_disk)
                .map_err(dirstate_error)?;
            (Box::new(map) as _, parents)
        } else {
            let bytes = on_disk.data(py);
            let mut map = RustDirstateMap::default();
            let parents = map.read(bytes).map_err(dirstate_error)?;
            (Box::new(map) as _, parents)
        };
        let map = Self::create_instance(py, inner)?;
        let parents = parents.map(|p| dirstate_parents_to_pytuple(py, &p));
        Ok((map, parents).to_py_object(py).into_object())
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
                .map_err(|e: HgError| {
                    PyErr::new::<exc::ValueError, _>(py, e.to_string())
                })?,
            DirstateEntry {
                state: state.extract::<PyBytes>(py)?.data(py)[0]
                    .try_into()
                    .map_err(|e: HgError| {
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
                    .map_err(|e: HgError| {
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
                    .map_err(|e: HgError| {
                        PyErr::new::<exc::ValueError, _>(py, e.to_string())
                    })?,
            )
            .and_then(|b| Ok(b.to_py_object(py)))
            .or_else(|e| {
                Err(PyErr::new::<exc::OSError, _>(
                    py,
                    format!("Dirstate error: {}", e.to_string()),
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

    def other_parent_entries(&self) -> PyResult<PyObject> {
        let mut inner_shared = self.inner(py).borrow_mut();
        let set = PySet::empty(py)?;
        for path in inner_shared.iter_other_parent_paths() {
            set.add(py, PyBytes::new(py, path.as_bytes()))?;
        }
        Ok(set.into_object())
    }

    def non_normal_entries(&self) -> PyResult<NonNormalEntries> {
        NonNormalEntries::from_inner(py, self.clone_ref(py))
    }

    def non_normal_entries_contains(&self, key: PyObject) -> PyResult<bool> {
        let key = key.extract::<PyBytes>(py)?;
        Ok(self
            .inner(py)
            .borrow_mut()
            .non_normal_entries_contains(HgPath::new(key.data(py))))
    }

    def non_normal_entries_display(&self) -> PyResult<PyString> {
        Ok(
            PyString::new(
                py,
                &format!(
                    "NonNormalEntries: {}",
                    hg::utils::join_display(
                        self
                            .inner(py)
                            .borrow_mut()
                            .iter_non_normal_paths(),
                        ", "
                    )
                )
            )
        )
    }

    def non_normal_entries_remove(&self, key: PyObject) -> PyResult<PyObject> {
        let key = key.extract::<PyBytes>(py)?;
        self
            .inner(py)
            .borrow_mut()
            .non_normal_entries_remove(HgPath::new(key.data(py)));
        Ok(py.None())
    }

    def non_normal_or_other_parent_paths(&self) -> PyResult<PyList> {
        let mut inner = self.inner(py).borrow_mut();

        let ret = PyList::new(py, &[]);
        for filename in inner.non_normal_or_other_parent_paths() {
            let as_pystring = PyBytes::new(py, filename.as_bytes());
            ret.append(py, as_pystring.into_object());
        }
        Ok(ret)
    }

    def non_normal_entries_iter(&self) -> PyResult<NonNormalEntriesIterator> {
        // Make sure the sets are defined before we no longer have a mutable
        // reference to the dmap.
        self.inner(py)
            .borrow_mut()
            .set_non_normal_other_parent_entries(false);

        let leaked_ref = self.inner(py).leak_immutable();

        NonNormalEntriesIterator::from_inner(py, unsafe {
            leaked_ref.map(py, |o| {
                o.iter_non_normal_paths_panic()
            })
        })
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

    def write(
        &self,
        p1: PyObject,
        p2: PyObject,
        now: PyObject
    ) -> PyResult<PyBytes> {
        let now = Timestamp(now.extract(py)?);
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
        for (path, entry) in self.inner(py).borrow_mut().iter() {
            if entry.state != EntryState::Removed {
                let key = normalize_case(path);
                let value = path;
                dict.set_item(
                    py,
                    PyBytes::new(py, key.as_bytes()).into_object(),
                    PyBytes::new(py, value.as_bytes()).into_object(),
                )?;
            }
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
                self.inner(py).borrow().iter(),
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
                self.inner(py).borrow().iter(),
                None,
            ).map_err(|e| {
                PyErr::new::<exc::ValueError, _>(py, e.to_string())
            })?,
        )
    }

    // TODO all copymap* methods, see docstring above
    def copymapcopy(&self) -> PyResult<PyDict> {
        let dict = PyDict::new(py);
        for (key, value) in self.inner(py).borrow().copy_map_iter() {
            dict.set_item(
                py,
                PyBytes::new(py, key.as_bytes()),
                PyBytes::new(py, value.as_bytes()),
            )?;
        }
        Ok(dict)
    }

    def copymapgetitem(&self, key: PyObject) -> PyResult<PyBytes> {
        let key = key.extract::<PyBytes>(py)?;
        match self.inner(py).borrow().copy_map_get(HgPath::new(key.data(py))) {
            Some(copy) => Ok(PyBytes::new(py, copy.as_bytes())),
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
        Ok(self.inner(py).borrow().copy_map_len())
    }
    def copymapcontains(&self, key: PyObject) -> PyResult<bool> {
        let key = key.extract::<PyBytes>(py)?;
        Ok(self
            .inner(py)
            .borrow()
            .copy_map_contains_key(HgPath::new(key.data(py))))
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
            .copy_map_get(HgPath::new(key.data(py)))
        {
            Some(copy) => Ok(Some(
                PyBytes::new(py, copy.as_bytes()).into_object(),
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
        self.inner(py).borrow_mut().copy_map_insert(
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
            .copy_map_remove(HgPath::new(key.data(py)))
        {
            Some(_) => Ok(None),
            None => Ok(default),
        }
    }

    def copymapiter(&self) -> PyResult<CopyMapKeysIterator> {
        let leaked_ref = self.inner(py).leak_immutable();
        CopyMapKeysIterator::from_inner(
            py,
            unsafe { leaked_ref.map(py, |o| o.copy_map_iter()) },
        )
    }

    def copymapitemsiter(&self) -> PyResult<CopyMapItemsIterator> {
        let leaked_ref = self.inner(py).leak_immutable();
        CopyMapItemsIterator::from_inner(
            py,
            unsafe { leaked_ref.map(py, |o| o.copy_map_iter()) },
        )
    }

});

impl DirstateMap {
    pub fn get_inner_mut<'a>(
        &'a self,
        py: Python<'a>,
    ) -> RefMut<'a, Box<dyn DirstateMapMethods + Send>> {
        self.inner(py).borrow_mut()
    }
    fn translate_key(
        py: Python,
        res: (&HgPath, &DirstateEntry),
    ) -> PyResult<Option<PyBytes>> {
        Ok(Some(PyBytes::new(py, res.0.as_bytes())))
    }
    fn translate_key_value(
        py: Python,
        res: (&HgPath, &DirstateEntry),
    ) -> PyResult<Option<(PyBytes, PyObject)>> {
        let (f, entry) = res;
        Ok(Some((
            PyBytes::new(py, f.as_bytes()),
            make_dirstate_tuple(py, &entry)?,
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

fn extract_node_id(py: Python, obj: &PyObject) -> PyResult<Node> {
    let bytes = obj.extract::<PyBytes>(py)?;
    match bytes.data(py).try_into() {
        Ok(s) => Ok(s),
        Err(e) => Err(PyErr::new::<exc::ValueError, _>(py, e.to_string())),
    }
}

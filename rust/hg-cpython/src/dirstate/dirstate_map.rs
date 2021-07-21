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
    dirstate::make_dirstate_item,
    dirstate::make_dirstate_item_raw,
    dirstate::non_normal_entries::{
        NonNormalEntries, NonNormalEntriesIterator,
    },
    dirstate::owning::OwningDirstateMap,
    parsers::dirstate_parents_to_pytuple,
};
use hg::{
    dirstate::parsers::Timestamp,
    dirstate::MTIME_UNSET,
    dirstate::SIZE_NON_NORMAL,
    dirstate_tree::dispatch::DirstateMapMethods,
    dirstate_tree::on_disk::DirstateV2ParseError,
    revlog::Node,
    utils::files::normalize_case,
    utils::hg_path::{HgPath, HgPathBuf},
    DirstateEntry, DirstateError, DirstateMap as RustDirstateMap,
    DirstateParents, EntryState, StateMapIter,
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
    def new_v1(
        use_dirstate_tree: bool,
        on_disk: PyBytes,
    ) -> PyResult<PyObject> {
        let (inner, parents) = if use_dirstate_tree {
            let (map, parents) = OwningDirstateMap::new_v1(py, on_disk)
                .map_err(|e| dirstate_error(py, e))?;
            (Box::new(map) as _, parents)
        } else {
            let bytes = on_disk.data(py);
            let mut map = RustDirstateMap::default();
            let parents = map.read(bytes).map_err(|e| dirstate_error(py, e))?;
            (Box::new(map) as _, parents)
        };
        let map = Self::create_instance(py, inner)?;
        let parents = parents.map(|p| dirstate_parents_to_pytuple(py, &p));
        Ok((map, parents).to_py_object(py).into_object())
    }

    /// Returns a DirstateMap
    @staticmethod
    def new_v2(
        on_disk: PyBytes,
        data_size: usize,
        tree_metadata: PyBytes,
    ) -> PyResult<PyObject> {
        let dirstate_error = |e: DirstateError| {
            PyErr::new::<exc::OSError, _>(py, format!("Dirstate error: {:?}", e))
        };
        let inner = OwningDirstateMap::new_v2(
            py, on_disk, data_size, tree_metadata,
        ).map_err(dirstate_error)?;
        let map = Self::create_instance(py, Box::new(inner))?;
        Ok(map.into_object())
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
        match self
            .inner(py)
            .borrow()
            .get(HgPath::new(key.data(py)))
            .map_err(|e| v2_error(py, e))?
        {
            Some(entry) => {
                Ok(Some(make_dirstate_item(py, &entry)?))
            },
            None => Ok(default)
        }
    }

    def set_v1(&self, path: PyObject, item: PyObject) -> PyResult<PyObject> {
        let f = path.extract::<PyBytes>(py)?;
        let filename = HgPath::new(f.data(py));
        let state = item.getattr(py, "state")?.extract::<PyBytes>(py)?;
        let state = state.data(py)[0];
        let entry = DirstateEntry {
            state: state.try_into().expect("state is always valid"),
            mtime: item.getattr(py, "mtime")?.extract(py)?,
            size: item.getattr(py, "size")?.extract(py)?,
            mode: item.getattr(py, "mode")?.extract(py)?,
        };
        self.inner(py).borrow_mut().set_v1(filename, entry);
        Ok(py.None())
    }

    def addfile(
        &self,
        f: PyObject,
        mode: PyObject,
        size: PyObject,
        mtime: PyObject,
        added: PyObject,
        merged: PyObject,
        from_p2: PyObject,
        possibly_dirty: PyObject,
    ) -> PyResult<PyObject> {
        let f = f.extract::<PyBytes>(py)?;
        let filename = HgPath::new(f.data(py));
        let mode = if mode.is_none(py) {
            // fallback default value
            0
        } else {
            mode.extract(py)?
        };
        let size = if size.is_none(py) {
            // fallback default value
            SIZE_NON_NORMAL
        } else {
            size.extract(py)?
        };
        let mtime = if mtime.is_none(py) {
            // fallback default value
            MTIME_UNSET
        } else {
            mtime.extract(py)?
        };
        let entry = DirstateEntry {
            // XXX Arbitrary default value since the value is determined later
            state: EntryState::Normal,
            mode: mode,
            size: size,
            mtime: mtime,
        };
        let added = added.extract::<PyBool>(py)?.is_true();
        let merged = merged.extract::<PyBool>(py)?.is_true();
        let from_p2 = from_p2.extract::<PyBool>(py)?.is_true();
        let possibly_dirty = possibly_dirty.extract::<PyBool>(py)?.is_true();
        self.inner(py).borrow_mut().add_file(
            filename,
            entry,
            added,
            merged,
            from_p2,
            possibly_dirty
        ).and(Ok(py.None())).or_else(|e: DirstateError| {
            Err(PyErr::new::<exc::ValueError, _>(py, e.to_string()))
        })
    }

    def removefile(
        &self,
        f: PyObject,
        in_merge: PyObject
    ) -> PyResult<PyObject> {
        self.inner(py).borrow_mut()
            .remove_file(
                HgPath::new(f.extract::<PyBytes>(py)?.data(py)),
                in_merge.extract::<PyBool>(py)?.is_true(),
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
    ) -> PyResult<PyBool> {
        self.inner(py).borrow_mut()
            .drop_file(
                HgPath::new(f.extract::<PyBytes>(py)?.data(py)),
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
        self.inner(py)
            .borrow_mut()
            .clear_ambiguous_times(files?, now.extract(py)?)
            .map_err(|e| v2_error(py, e))?;
        Ok(py.None())
    }

    def other_parent_entries(&self) -> PyResult<PyObject> {
        let mut inner_shared = self.inner(py).borrow_mut();
        let set = PySet::empty(py)?;
        for path in inner_shared.iter_other_parent_paths() {
            let path = path.map_err(|e| v2_error(py, e))?;
            set.add(py, PyBytes::new(py, path.as_bytes()))?;
        }
        Ok(set.into_object())
    }

    def non_normal_entries(&self) -> PyResult<NonNormalEntries> {
        NonNormalEntries::from_inner(py, self.clone_ref(py))
    }

    def non_normal_entries_contains(&self, key: PyObject) -> PyResult<bool> {
        let key = key.extract::<PyBytes>(py)?;
        self.inner(py)
            .borrow_mut()
            .non_normal_entries_contains(HgPath::new(key.data(py)))
            .map_err(|e| v2_error(py, e))
    }

    def non_normal_entries_display(&self) -> PyResult<PyString> {
        let mut inner = self.inner(py).borrow_mut();
        let paths = inner
            .iter_non_normal_paths()
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| v2_error(py, e))?;
        let formatted = format!("NonNormalEntries: {}", hg::utils::join_display(paths, ", "));
        Ok(PyString::new(py, &formatted))
    }

    def non_normal_entries_remove(&self, key: PyObject) -> PyResult<PyObject> {
        let key = key.extract::<PyBytes>(py)?;
        let key = key.data(py);
        let was_present = self
            .inner(py)
            .borrow_mut()
            .non_normal_entries_remove(HgPath::new(key));
        if !was_present {
            let msg = String::from_utf8_lossy(key);
            Err(PyErr::new::<exc::KeyError, _>(py, msg))
        } else {
            Ok(py.None())
        }
    }

    def non_normal_entries_discard(&self, key: PyObject) -> PyResult<PyObject>
    {
        let key = key.extract::<PyBytes>(py)?;
        self
            .inner(py)
            .borrow_mut()
            .non_normal_entries_remove(HgPath::new(key.data(py)));
        Ok(py.None())
    }

    def non_normal_entries_add(&self, key: PyObject) -> PyResult<PyObject> {
        let key = key.extract::<PyBytes>(py)?;
        self
            .inner(py)
            .borrow_mut()
            .non_normal_entries_add(HgPath::new(key.data(py)));
        Ok(py.None())
    }

    def non_normal_or_other_parent_paths(&self) -> PyResult<PyList> {
        let mut inner = self.inner(py).borrow_mut();

        let ret = PyList::new(py, &[]);
        for filename in inner.non_normal_or_other_parent_paths() {
            let filename = filename.map_err(|e| v2_error(py, e))?;
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

    def write_v1(
        &self,
        p1: PyObject,
        p2: PyObject,
        now: PyObject
    ) -> PyResult<PyBytes> {
        let now = Timestamp(now.extract(py)?);

        let mut inner = self.inner(py).borrow_mut();
        let parents = DirstateParents {
            p1: extract_node_id(py, &p1)?,
            p2: extract_node_id(py, &p2)?,
        };
        let result = inner.pack_v1(parents, now);
        match result {
            Ok(packed) => Ok(PyBytes::new(py, &packed)),
            Err(_) => Err(PyErr::new::<exc::OSError, _>(
                py,
                "Dirstate error".to_string(),
            )),
        }
    }

    /// Returns new data together with whether that data should be appended to
    /// the existing data file whose content is at `self.on_disk` (True),
    /// instead of written to a new data file (False).
    def write_v2(
        &self,
        now: PyObject,
        can_append: bool,
    ) -> PyResult<PyObject> {
        let now = Timestamp(now.extract(py)?);

        let mut inner = self.inner(py).borrow_mut();
        let result = inner.pack_v2(now, can_append);
        match result {
            Ok((packed, tree_metadata, append)) => {
                let packed = PyBytes::new(py, &packed);
                let tree_metadata = PyBytes::new(py, &tree_metadata);
                let tuple = (packed, tree_metadata, append);
                Ok(tuple.to_py_object(py).into_object())
            },
            Err(_) => Err(PyErr::new::<exc::OSError, _>(
                py,
                "Dirstate error".to_string(),
            )),
        }
    }

    def filefoldmapasdict(&self) -> PyResult<PyDict> {
        let dict = PyDict::new(py);
        for item in self.inner(py).borrow_mut().iter() {
            let (path, entry) = item.map_err(|e| v2_error(py, e))?;
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
        self.inner(py)
            .borrow()
            .contains_key(HgPath::new(key.data(py)))
            .map_err(|e| v2_error(py, e))
    }

    def __getitem__(&self, key: PyObject) -> PyResult<PyObject> {
        let key = key.extract::<PyBytes>(py)?;
        let key = HgPath::new(key.data(py));
        match self
            .inner(py)
            .borrow()
            .get(key)
            .map_err(|e| v2_error(py, e))?
        {
            Some(entry) => {
                Ok(make_dirstate_item(py, &entry)?)
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

    // TODO all copymap* methods, see docstring above
    def copymapcopy(&self) -> PyResult<PyDict> {
        let dict = PyDict::new(py);
        for item in self.inner(py).borrow().copy_map_iter() {
            let (key, value) = item.map_err(|e| v2_error(py, e))?;
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
        match self
            .inner(py)
            .borrow()
            .copy_map_get(HgPath::new(key.data(py)))
            .map_err(|e| v2_error(py, e))?
        {
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
        self.inner(py)
            .borrow()
            .copy_map_contains_key(HgPath::new(key.data(py)))
            .map_err(|e| v2_error(py, e))
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
            .map_err(|e| v2_error(py, e))?
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
        self.inner(py)
            .borrow_mut()
            .copy_map_insert(
                HgPathBuf::from_bytes(key.data(py)),
                HgPathBuf::from_bytes(value.data(py)),
            )
            .map_err(|e| v2_error(py, e))?;
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
            .map_err(|e| v2_error(py, e))?
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

    def tracked_dirs(&self) -> PyResult<PyList> {
        let dirs = PyList::new(py, &[]);
        for path in self.inner(py).borrow_mut().iter_tracked_dirs()
            .map_err(|e |dirstate_error(py, e))?
        {
            let path = path.map_err(|e| v2_error(py, e))?;
            let path = PyBytes::new(py, path.as_bytes());
            dirs.append(py, path.into_object())
        }
        Ok(dirs)
    }

    def debug_iter(&self) -> PyResult<PyList> {
        let dirs = PyList::new(py, &[]);
        for item in self.inner(py).borrow().debug_iter() {
            let (path, (state, mode, size, mtime)) =
                item.map_err(|e| v2_error(py, e))?;
            let path = PyBytes::new(py, path.as_bytes());
            let item = make_dirstate_item_raw(py, state, mode, size, mtime)?;
            dirs.append(py, (path, item).to_py_object(py).into_object())
        }
        Ok(dirs)
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
        res: Result<(&HgPath, DirstateEntry), DirstateV2ParseError>,
    ) -> PyResult<Option<PyBytes>> {
        let (f, _entry) = res.map_err(|e| v2_error(py, e))?;
        Ok(Some(PyBytes::new(py, f.as_bytes())))
    }
    fn translate_key_value(
        py: Python,
        res: Result<(&HgPath, DirstateEntry), DirstateV2ParseError>,
    ) -> PyResult<Option<(PyBytes, PyObject)>> {
        let (f, entry) = res.map_err(|e| v2_error(py, e))?;
        Ok(Some((
            PyBytes::new(py, f.as_bytes()),
            make_dirstate_item(py, &entry)?,
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

pub(super) fn v2_error(py: Python<'_>, _: DirstateV2ParseError) -> PyErr {
    PyErr::new::<exc::ValueError, _>(py, "corrupted dirstate-v2")
}

fn dirstate_error(py: Python<'_>, e: DirstateError) -> PyErr {
    PyErr::new::<exc::OSError, _>(py, format!("Dirstate error: {:?}", e))
}

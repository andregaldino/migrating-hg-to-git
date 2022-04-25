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
    exc, PyBool, PyBytes, PyClone, PyDict, PyErr, PyList, PyNone, PyObject,
    PyResult, Python, PythonObject, ToPyObject, UnsafePyLeaked,
};
use hg::dirstate::{ParentFileData, TruncatedTimestamp};

use crate::{
    dirstate::copymap::{CopyMap, CopyMapItemsIterator, CopyMapKeysIterator},
    dirstate::item::DirstateItem,
    pybytes_deref::PyBytesDeref,
};
use hg::{
    dirstate::StateMapIter, dirstate_tree::on_disk::DirstateV2ParseError,
    dirstate_tree::owning::OwningDirstateMap, revlog::Node,
    utils::files::normalize_case, utils::hg_path::HgPath, DirstateEntry,
    DirstateError, DirstateParents,
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
    @shared data inner: OwningDirstateMap;

    /// Returns a `(dirstate_map, parents)` tuple
    @staticmethod
    def new_v1(
        on_disk: PyBytes,
    ) -> PyResult<PyObject> {
        let on_disk = PyBytesDeref::new(py, on_disk);
        let (map, parents) = OwningDirstateMap::new_v1(on_disk)
            .map_err(|e| dirstate_error(py, e))?;
        let map = Self::create_instance(py, map)?;
        let p1 = PyBytes::new(py, parents.p1.as_bytes());
        let p2 = PyBytes::new(py, parents.p2.as_bytes());
        let parents = (p1, p2);
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
        let on_disk = PyBytesDeref::new(py, on_disk);
        let map = OwningDirstateMap::new_v2(
            on_disk, data_size, tree_metadata.data(py),
        ).map_err(dirstate_error)?;
        let map = Self::create_instance(py, map)?;
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
                Ok(Some(DirstateItem::new_as_pyobject(py, entry)?))
            },
            None => Ok(default)
        }
    }

    def set_tracked(&self, f: PyObject) -> PyResult<PyBool> {
        let bytes = f.extract::<PyBytes>(py)?;
        let path = HgPath::new(bytes.data(py));
        let res = self.inner(py).borrow_mut().set_tracked(path);
        let was_tracked = res.or_else(|_| {
            Err(PyErr::new::<exc::OSError, _>(py, "Dirstate error".to_string()))
        })?;
        Ok(was_tracked.to_py_object(py))
    }

    def set_untracked(&self, f: PyObject) -> PyResult<PyBool> {
        let bytes = f.extract::<PyBytes>(py)?;
        let path = HgPath::new(bytes.data(py));
        let res = self.inner(py).borrow_mut().set_untracked(path);
        let was_tracked = res.or_else(|_| {
            Err(PyErr::new::<exc::OSError, _>(py, "Dirstate error".to_string()))
        })?;
        Ok(was_tracked.to_py_object(py))
    }

    def set_clean(
        &self,
        f: PyObject,
        mode: u32,
        size: u32,
        mtime: (i64, u32, bool)
    ) -> PyResult<PyNone> {
        let (mtime_s, mtime_ns, second_ambiguous) = mtime;
        let timestamp = TruncatedTimestamp::new_truncate(
            mtime_s, mtime_ns, second_ambiguous
        );
        let bytes = f.extract::<PyBytes>(py)?;
        let path = HgPath::new(bytes.data(py));
        let res = self.inner(py).borrow_mut().set_clean(
            path, mode, size, timestamp,
        );
        res.or_else(|_| {
            Err(PyErr::new::<exc::OSError, _>(py, "Dirstate error".to_string()))
        })?;
        Ok(PyNone)
    }

    def set_possibly_dirty(&self, f: PyObject) -> PyResult<PyNone> {
        let bytes = f.extract::<PyBytes>(py)?;
        let path = HgPath::new(bytes.data(py));
        let res = self.inner(py).borrow_mut().set_possibly_dirty(path);
        res.or_else(|_| {
            Err(PyErr::new::<exc::OSError, _>(py, "Dirstate error".to_string()))
        })?;
        Ok(PyNone)
    }

    def reset_state(
        &self,
        f: PyObject,
        wc_tracked: bool,
        p1_tracked: bool,
        p2_info: bool,
        has_meaningful_mtime: bool,
        parentfiledata: Option<(u32, u32, Option<(i64, u32, bool)>)>,
    ) -> PyResult<PyNone> {
        let mut has_meaningful_mtime = has_meaningful_mtime;
        let parent_file_data = match parentfiledata {
            None => {
                has_meaningful_mtime = false;
                None
            },
            Some(data) => {
                let (mode, size, mtime_info) = data;
                let mtime = if let Some(mtime_info) = mtime_info {
                    let (mtime_s, mtime_ns, second_ambiguous) = mtime_info;
                    let timestamp = TruncatedTimestamp::new_truncate(
                        mtime_s, mtime_ns, second_ambiguous
                    );
                    Some(timestamp)
                } else {
                    has_meaningful_mtime = false;
                    None
                };
                Some(ParentFileData {
                    mode_size: Some((mode, size)),
                    mtime,
                })
            }
        };
        let bytes = f.extract::<PyBytes>(py)?;
        let path = HgPath::new(bytes.data(py));
        let res = self.inner(py).borrow_mut().reset_state(
            path,
            wc_tracked,
            p1_tracked,
            p2_info,
            has_meaningful_mtime,
            parent_file_data,
        );
        res.or_else(|_| {
            Err(PyErr::new::<exc::OSError, _>(py, "Dirstate error".to_string()))
        })?;
        Ok(PyNone)
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
    ) -> PyResult<PyBytes> {
        let inner = self.inner(py).borrow();
        let parents = DirstateParents {
            p1: extract_node_id(py, &p1)?,
            p2: extract_node_id(py, &p2)?,
        };
        let result = inner.pack_v1(parents);
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
        can_append: bool,
    ) -> PyResult<PyObject> {
        let inner = self.inner(py).borrow();
        let result = inner.pack_v2(can_append);
        match result {
            Ok((packed, tree_metadata, append, _old_data_size)) => {
                let packed = PyBytes::new(py, &packed);
                let tree_metadata = PyBytes::new(py, tree_metadata.as_bytes());
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
            if !entry.removed() {
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
                Ok(DirstateItem::new_as_pyobject(py, entry)?)
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
                HgPath::new(key.data(py)),
                HgPath::new(value.data(py)),
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
            Some(copy) => Ok(Some(
                PyBytes::new(py, copy.as_bytes()).into_object(),
            )),
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

    def setparents_fixup(&self) -> PyResult<PyDict> {
        let dict = PyDict::new(py);
        let copies = self.inner(py).borrow_mut().setparents_fixup();
        for (key, value) in copies.map_err(|e| v2_error(py, e))? {
            dict.set_item(
                py,
                PyBytes::new(py, key.as_bytes()),
                PyBytes::new(py, value.as_bytes()),
            )?;
        }
        Ok(dict)
    }

    def debug_iter(&self, all: bool) -> PyResult<PyList> {
        let dirs = PyList::new(py, &[]);
        for item in self.inner(py).borrow().debug_iter(all) {
            let (path, (state, mode, size, mtime)) =
                item.map_err(|e| v2_error(py, e))?;
            let path = PyBytes::new(py, path.as_bytes());
            let item = (path, state, mode, size, mtime);
            dirs.append(py, item.to_py_object(py).into_object())
        }
        Ok(dirs)
    }
});

impl DirstateMap {
    pub fn get_inner_mut<'a>(
        &'a self,
        py: Python<'a>,
    ) -> RefMut<'a, OwningDirstateMap> {
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
            DirstateItem::new_as_pyobject(py, entry)?,
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

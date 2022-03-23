use cpython::exc;
use cpython::ObjectProtocol;
use cpython::PyBytes;
use cpython::PyErr;
use cpython::PyNone;
use cpython::PyObject;
use cpython::PyResult;
use cpython::Python;
use cpython::PythonObject;
use hg::dirstate::DirstateEntry;
use hg::dirstate::DirstateV2Data;
use hg::dirstate::TruncatedTimestamp;
use std::cell::Cell;

py_class!(pub class DirstateItem |py| {
    data entry: Cell<DirstateEntry>;

    def __new__(
        _cls,
        wc_tracked: bool = false,
        p1_tracked: bool = false,
        p2_info: bool = false,
        has_meaningful_data: bool = true,
        has_meaningful_mtime: bool = true,
        parentfiledata: Option<(u32, u32, Option<(u32, u32, bool)>)> = None,
        fallback_exec: Option<bool> = None,
        fallback_symlink: Option<bool> = None,

    ) -> PyResult<DirstateItem> {
        let mut mode_size_opt = None;
        let mut mtime_opt = None;
        if let Some((mode, size, mtime)) = parentfiledata {
            if has_meaningful_data {
                mode_size_opt = Some((mode, size))
            }
            if has_meaningful_mtime {
                if let Some(m) = mtime {
                    mtime_opt = Some(timestamp(py, m)?);
                }
            }
        }
        let entry = DirstateEntry::from_v2_data(DirstateV2Data {
            wc_tracked: wc_tracked,
            p1_tracked,
            p2_info,
            mode_size: mode_size_opt,
            mtime: mtime_opt,
            fallback_exec,
            fallback_symlink,
        });
        DirstateItem::create_instance(py, Cell::new(entry))
    }

    @property
    def state(&self) -> PyResult<PyBytes> {
        let state_byte: u8 = self.entry(py).get().state().into();
        Ok(PyBytes::new(py, &[state_byte]))
    }

    @property
    def mode(&self) -> PyResult<i32> {
        Ok(self.entry(py).get().mode())
    }

    @property
    def size(&self) -> PyResult<i32> {
        Ok(self.entry(py).get().size())
    }

    @property
    def mtime(&self) -> PyResult<i32> {
        Ok(self.entry(py).get().mtime())
    }

    @property
    def has_fallback_exec(&self) -> PyResult<bool> {
        match self.entry(py).get().get_fallback_exec() {
            Some(_) => Ok(true),
            None => Ok(false),
        }
    }

    @property
    def fallback_exec(&self) -> PyResult<Option<bool>> {
        match self.entry(py).get().get_fallback_exec() {
            Some(exec) => Ok(Some(exec)),
            None => Ok(None),
        }
    }

    @fallback_exec.setter
    def set_fallback_exec(&self, value: Option<PyObject>) -> PyResult<()> {
        match value {
            None => {self.entry(py).get().set_fallback_exec(None);},
            Some(value) => {
            if value.is_none(py) {
                self.entry(py).get().set_fallback_exec(None);
            } else {
                self.entry(py).get().set_fallback_exec(
                    Some(value.is_true(py)?)
                );
            }},
        }
        Ok(())
    }

    @property
    def has_fallback_symlink(&self) -> PyResult<bool> {
        match self.entry(py).get().get_fallback_symlink() {
            Some(_) => Ok(true),
            None => Ok(false),
        }
    }

    @property
    def fallback_symlink(&self) -> PyResult<Option<bool>> {
        match self.entry(py).get().get_fallback_symlink() {
            Some(symlink) => Ok(Some(symlink)),
            None => Ok(None),
        }
    }

    @fallback_symlink.setter
    def set_fallback_symlink(&self, value: Option<PyObject>) -> PyResult<()> {
        match value {
            None => {self.entry(py).get().set_fallback_symlink(None);},
            Some(value) => {
            if value.is_none(py) {
                self.entry(py).get().set_fallback_symlink(None);
            } else {
                self.entry(py).get().set_fallback_symlink(
                    Some(value.is_true(py)?)
                );
            }},
        }
        Ok(())
    }

    @property
    def tracked(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().tracked())
    }

    @property
    def p1_tracked(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().p1_tracked())
    }

    @property
    def added(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().added())
    }


    @property
    def p2_info(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().p2_info())
    }

    @property
    def removed(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().removed())
    }

    @property
    def maybe_clean(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().maybe_clean())
    }

    @property
    def any_tracked(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().any_tracked())
    }

    def mtime_likely_equal_to(&self, other: (u32, u32, bool))
        -> PyResult<bool> {
        if let Some(mtime) = self.entry(py).get().truncated_mtime() {
            Ok(mtime.likely_equal(timestamp(py, other)?))
        } else {
            Ok(false)
        }
    }

    def drop_merge_data(&self) -> PyResult<PyNone> {
        self.update(py, |entry| entry.drop_merge_data());
        Ok(PyNone)
    }

    def set_clean(
        &self,
        mode: u32,
        size: u32,
        mtime: (u32, u32, bool),
    ) -> PyResult<PyNone> {
        let mtime = timestamp(py, mtime)?;
        self.update(py, |entry| entry.set_clean(mode, size, mtime));
        Ok(PyNone)
    }

    def set_possibly_dirty(&self) -> PyResult<PyNone> {
        self.update(py, |entry| entry.set_possibly_dirty());
        Ok(PyNone)
    }

    def set_tracked(&self) -> PyResult<PyNone> {
        self.update(py, |entry| entry.set_tracked());
        Ok(PyNone)
    }

    def set_untracked(&self) -> PyResult<PyNone> {
        self.update(py, |entry| entry.set_untracked());
        Ok(PyNone)
    }
});

impl DirstateItem {
    pub fn new_as_pyobject(
        py: Python<'_>,
        entry: DirstateEntry,
    ) -> PyResult<PyObject> {
        Ok(DirstateItem::create_instance(py, Cell::new(entry))?.into_object())
    }

    pub fn get_entry(&self, py: Python<'_>) -> DirstateEntry {
        self.entry(py).get()
    }

    // TODO: Use https://doc.rust-lang.org/std/cell/struct.Cell.html#method.update instead when it’s stable
    pub fn update(&self, py: Python<'_>, f: impl FnOnce(&mut DirstateEntry)) {
        let mut entry = self.entry(py).get();
        f(&mut entry);
        self.entry(py).set(entry)
    }
}

pub(crate) fn timestamp(
    py: Python<'_>,
    (s, ns, second_ambiguous): (u32, u32, bool),
) -> PyResult<TruncatedTimestamp> {
    TruncatedTimestamp::from_already_truncated(s, ns, second_ambiguous)
        .map_err(|_| {
            PyErr::new::<exc::ValueError, _>(
                py,
                "expected mtime truncated to 31 bits",
            )
        })
}

use cpython::exc;
use cpython::PyBytes;
use cpython::PyErr;
use cpython::PyNone;
use cpython::PyObject;
use cpython::PyResult;
use cpython::Python;
use cpython::PythonObject;
use hg::dirstate::DirstateEntry;
use hg::dirstate::EntryState;
use std::cell::Cell;
use std::convert::TryFrom;

py_class!(pub class DirstateItem |py| {
    data entry: Cell<DirstateEntry>;

    def __new__(
        _cls,
        wc_tracked: bool = false,
        p1_tracked: bool = false,
        p2_info: bool = false,
        has_meaningful_data: bool = true,
        has_meaningful_mtime: bool = true,
        parentfiledata: Option<(i32, i32, i32)> = None,

    ) -> PyResult<DirstateItem> {
        let mut mode_size_opt = None;
        let mut mtime_opt = None;
        if let Some((mode, size, mtime)) = parentfiledata {
            if has_meaningful_data {
                mode_size_opt = Some((mode, size))
            }
            if has_meaningful_mtime {
                mtime_opt = Some(mtime)
            }
        }
        let entry = DirstateEntry::from_v2_data(
            wc_tracked, p1_tracked, p2_info, mode_size_opt, mtime_opt,
        );
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
    def tracked(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().tracked())
    }

    @property
    def added(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().added())
    }

    @property
    def merged(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().merged())
    }

    @property
    def removed(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().removed())
    }

    @property
    def from_p2(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().from_p2())
    }

    @property
    def maybe_clean(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().maybe_clean())
    }

    @property
    def any_tracked(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().any_tracked())
    }

    def v1_state(&self) -> PyResult<PyBytes> {
        let (state, _mode, _size, _mtime) = self.entry(py).get().v1_data();
        let state_byte: u8 = state.into();
        Ok(PyBytes::new(py, &[state_byte]))
    }

    def v1_mode(&self) -> PyResult<i32> {
        let (_state, mode, _size, _mtime) = self.entry(py).get().v1_data();
        Ok(mode)
    }

    def v1_size(&self) -> PyResult<i32> {
        let (_state, _mode, size, _mtime) = self.entry(py).get().v1_data();
        Ok(size)
    }

    def v1_mtime(&self) -> PyResult<i32> {
        let (_state, _mode, _size, mtime) = self.entry(py).get().v1_data();
        Ok(mtime)
    }

    def need_delay(&self, now: i32) -> PyResult<bool> {
        Ok(self.entry(py).get().mtime_is_ambiguous(now))
    }

    @classmethod
    def from_v1_data(
        _cls,
        state: PyBytes,
        mode: i32,
        size: i32,
        mtime: i32,
    ) -> PyResult<Self> {
        let state = <[u8; 1]>::try_from(state.data(py))
            .ok()
            .and_then(|state| EntryState::try_from(state[0]).ok())
            .ok_or_else(|| PyErr::new::<exc::ValueError, _>(py, "invalid state"))?;
        let entry = DirstateEntry::from_v1_data(state, mode, size, mtime);
        DirstateItem::create_instance(py, Cell::new(entry))
    }

    @classmethod
    def new_added(_cls) -> PyResult<Self> {
        let entry = DirstateEntry::new_added();
        DirstateItem::create_instance(py, Cell::new(entry))
    }

    @classmethod
    def new_merged(_cls) -> PyResult<Self> {
        let entry = DirstateEntry::new_merged();
        DirstateItem::create_instance(py, Cell::new(entry))
    }

    @classmethod
    def new_from_p2(_cls) -> PyResult<Self> {
        let entry = DirstateEntry::new_from_p2();
        DirstateItem::create_instance(py, Cell::new(entry))
    }

    @classmethod
    def new_possibly_dirty(_cls) -> PyResult<Self> {
        let entry = DirstateEntry::new_possibly_dirty();
        DirstateItem::create_instance(py, Cell::new(entry))
    }

    @classmethod
    def new_normal(_cls, mode: i32, size: i32, mtime: i32) -> PyResult<Self> {
        let entry = DirstateEntry::new_normal(mode, size, mtime);
        DirstateItem::create_instance(py, Cell::new(entry))
    }

    def drop_merge_data(&self) -> PyResult<PyNone> {
        self.update(py, |entry| entry.drop_merge_data());
        Ok(PyNone)
    }

    def set_clean(
        &self,
        mode: i32,
        size: i32,
        mtime: i32,
    ) -> PyResult<PyNone> {
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

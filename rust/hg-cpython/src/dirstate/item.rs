use cpython::exc;
use cpython::PyBytes;
use cpython::PyErr;
use cpython::PyNone;
use cpython::PyObject;
use cpython::PyResult;
use cpython::Python;
use cpython::PythonObject;
use hg::dirstate::entry::Flags;
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
        p2_tracked: bool = false,
        merged: bool = false,
        clean_p1: bool = false,
        clean_p2: bool = false,
        possibly_dirty: bool = false,
        parentfiledata: Option<(i32, i32, i32)> = None,

    ) -> PyResult<DirstateItem> {
        let mut flags = Flags::empty();
        flags.set(Flags::WDIR_TRACKED, wc_tracked);
        flags.set(Flags::P1_TRACKED, p1_tracked);
        flags.set(Flags::P2_TRACKED, p2_tracked);
        flags.set(Flags::MERGED, merged);
        flags.set(Flags::CLEAN_P1, clean_p1);
        flags.set(Flags::CLEAN_P2, clean_p2);
        flags.set(Flags::POSSIBLY_DIRTY, possibly_dirty);
        let entry = DirstateEntry::new(flags, parentfiledata);
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
    def merged_removed(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().merged_removed())
    }

    @property
    def from_p2_removed(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().from_p2_removed())
    }

    @property
    def dm_nonnormal(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().is_non_normal())
    }

    @property
    def dm_otherparent(&self) -> PyResult<bool> {
        Ok(self.entry(py).get().is_from_other_parent())
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

    // TODO: Use https://doc.rust-lang.org/std/cell/struct.Cell.html#method.update instead when it’s stable
    pub fn update(&self, py: Python<'_>, f: impl FnOnce(&mut DirstateEntry)) {
        let mut entry = self.entry(py).get();
        f(&mut entry);
        self.entry(py).set(entry)
    }
}

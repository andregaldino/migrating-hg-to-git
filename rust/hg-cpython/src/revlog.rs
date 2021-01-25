// revlog.rs
//
// Copyright 2019-2020 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::{
    cindex,
    utils::{node_from_py_bytes, node_from_py_object},
};
use cpython::{
    buffer::{Element, PyBuffer},
    exc::{IndexError, ValueError},
    ObjectProtocol, PyBytes, PyClone, PyDict, PyErr, PyModule, PyObject,
    PyResult, PyString, PyTuple, Python, PythonObject, ToPyObject,
};
use hg::{
    nodemap::{Block, NodeMapError, NodeTree},
    revlog::{nodemap::NodeMap, RevlogIndex},
    Revision,
};
use std::cell::RefCell;

/// Return a Struct implementing the Graph trait
pub(crate) fn pyindex_to_graph(
    py: Python,
    index: PyObject,
) -> PyResult<cindex::Index> {
    match index.extract::<MixedIndex>(py) {
        Ok(midx) => Ok(midx.clone_cindex(py)),
        Err(_) => cindex::Index::new(py, index),
    }
}

py_class!(pub class MixedIndex |py| {
    data cindex: RefCell<cindex::Index>;
    data nt: RefCell<Option<NodeTree>>;
    data docket: RefCell<Option<PyObject>>;
    // Holds a reference to the mmap'ed persistent nodemap data
    data mmap: RefCell<Option<PyBuffer>>;

    def __new__(_cls, cindex: PyObject) -> PyResult<MixedIndex> {
        Self::new(py, cindex)
    }

    /// Compatibility layer used for Python consumers needing access to the C index
    ///
    /// Only use case so far is `scmutil.shortesthexnodeidprefix`,
    /// that may need to build a custom `nodetree`, based on a specified revset.
    /// With a Rust implementation of the nodemap, we will be able to get rid of
    /// this, by exposing our own standalone nodemap class,
    /// ready to accept `MixedIndex`.
    def get_cindex(&self) -> PyResult<PyObject> {
        Ok(self.cindex(py).borrow().inner().clone_ref(py))
    }

    // Index API involving nodemap, as defined in mercurial/pure/parsers.py

    /// Return Revision if found, raises a bare `error.RevlogError`
    /// in case of ambiguity, same as C version does
    def get_rev(&self, node: PyBytes) -> PyResult<Option<Revision>> {
        let opt = self.get_nodetree(py)?.borrow();
        let nt = opt.as_ref().unwrap();
        let idx = &*self.cindex(py).borrow();
        let node = node_from_py_bytes(py, &node)?;
        nt.find_bin(idx, node.into()).map_err(|e| nodemap_error(py, e))
    }

    /// same as `get_rev()` but raises a bare `error.RevlogError` if node
    /// is not found.
    ///
    /// No need to repeat `node` in the exception, `mercurial/revlog.py`
    /// will catch and rewrap with it
    def rev(&self, node: PyBytes) -> PyResult<Revision> {
        self.get_rev(py, node)?.ok_or_else(|| revlog_error(py))
    }

    /// return True if the node exist in the index
    def has_node(&self, node: PyBytes) -> PyResult<bool> {
        self.get_rev(py, node).map(|opt| opt.is_some())
    }

    /// find length of shortest hex nodeid of a binary ID
    def shortest(&self, node: PyBytes) -> PyResult<usize> {
        let opt = self.get_nodetree(py)?.borrow();
        let nt = opt.as_ref().unwrap();
        let idx = &*self.cindex(py).borrow();
        match nt.unique_prefix_len_node(idx, &node_from_py_bytes(py, &node)?)
        {
            Ok(Some(l)) => Ok(l),
            Ok(None) => Err(revlog_error(py)),
            Err(e) => Err(nodemap_error(py, e)),
        }
    }

    def partialmatch(&self, node: PyObject) -> PyResult<Option<PyBytes>> {
        let opt = self.get_nodetree(py)?.borrow();
        let nt = opt.as_ref().unwrap();
        let idx = &*self.cindex(py).borrow();

        let node_as_string = if cfg!(feature = "python3-sys") {
            node.cast_as::<PyString>(py)?.to_string(py)?.to_string()
        }
        else {
            let node = node.extract::<PyBytes>(py)?;
            String::from_utf8_lossy(node.data(py)).to_string()
        };

        nt.find_hex(idx, &node_as_string)
            // TODO make an inner API returning the node directly
            .map(|opt| opt.map(
                |rev| PyBytes::new(py, idx.node(rev).unwrap().as_bytes())))
            .map_err(|e| nodemap_error(py, e))

    }

    /// append an index entry
    def append(&self, tup: PyTuple) -> PyResult<PyObject> {
        if tup.len(py) < 8 {
            // this is better than the panic promised by tup.get_item()
            return Err(
                PyErr::new::<IndexError, _>(py, "tuple index out of range"))
        }
        let node_bytes = tup.get_item(py, 7).extract(py)?;
        let node = node_from_py_object(py, &node_bytes)?;

        let mut idx = self.cindex(py).borrow_mut();
        let rev = idx.len() as Revision;

        idx.append(py, tup)?;
        self.get_nodetree(py)?.borrow_mut().as_mut().unwrap()
            .insert(&*idx, &node, rev)
            .map_err(|e| nodemap_error(py, e))?;
        Ok(py.None())
    }

    def __delitem__(&self, key: PyObject) -> PyResult<()> {
        // __delitem__ is both for `del idx[r]` and `del idx[r1:r2]`
        self.cindex(py).borrow().inner().del_item(py, key)?;
        let mut opt = self.get_nodetree(py)?.borrow_mut();
        let mut nt = opt.as_mut().unwrap();
        nt.invalidate_all();
        self.fill_nodemap(py, &mut nt)?;
        Ok(())
    }

    //
    // Reforwarded C index API
    //

    // index_methods (tp_methods). Same ordering as in revlog.c

    /// return the gca set of the given revs
    def ancestors(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "ancestors", args, kw)
    }

    /// return the heads of the common ancestors of the given revs
    def commonancestorsheads(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "commonancestorsheads", args, kw)
    }

    /// Clear the index caches and inner py_class data.
    /// It is Python's responsibility to call `update_nodemap_data` again.
    def clearcaches(&self, *args, **kw) -> PyResult<PyObject> {
        self.nt(py).borrow_mut().take();
        self.docket(py).borrow_mut().take();
        self.mmap(py).borrow_mut().take();
        self.call_cindex(py, "clearcaches", args, kw)
    }

    /// get an index entry
    def get(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "get", args, kw)
    }

    /// compute phases
    def computephasesmapsets(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "computephasesmapsets", args, kw)
    }

    /// reachableroots
    def reachableroots2(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "reachableroots2", args, kw)
    }

    /// get head revisions
    def headrevs(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "headrevs", args, kw)
    }

    /// get filtered head revisions
    def headrevsfiltered(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "headrevsfiltered", args, kw)
    }

    /// True if the object is a snapshot
    def issnapshot(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "issnapshot", args, kw)
    }

    /// Gather snapshot data in a cache dict
    def findsnapshots(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "findsnapshots", args, kw)
    }

    /// determine revisions with deltas to reconstruct fulltext
    def deltachain(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "deltachain", args, kw)
    }

    /// slice planned chunk read to reach a density threshold
    def slicechunktodensity(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "slicechunktodensity", args, kw)
    }

    /// stats for the index
    def stats(&self, *args, **kw) -> PyResult<PyObject> {
        self.call_cindex(py, "stats", args, kw)
    }

    // index_sequence_methods and index_mapping_methods.
    //
    // Since we call back through the high level Python API,
    // there's no point making a distinction between index_get
    // and index_getitem.

    def __len__(&self) -> PyResult<usize> {
        self.cindex(py).borrow().inner().len(py)
    }

    def __getitem__(&self, key: PyObject) -> PyResult<PyObject> {
        // this conversion seems needless, but that's actually because
        // `index_getitem` does not handle conversion from PyLong,
        // which expressions such as [e for e in index] internally use.
        // Note that we don't seem to have a direct way to call
        // PySequence_GetItem (does the job), which would possibly be better
        // for performance
        let key = match key.extract::<Revision>(py) {
            Ok(rev) => rev.to_py_object(py).into_object(),
            Err(_) => key,
        };
        self.cindex(py).borrow().inner().get_item(py, key)
    }

    def __setitem__(&self, key: PyObject, value: PyObject) -> PyResult<()> {
        self.cindex(py).borrow().inner().set_item(py, key, value)
    }

    def __contains__(&self, item: PyObject) -> PyResult<bool> {
        // ObjectProtocol does not seem to provide contains(), so
        // this is an equivalent implementation of the index_contains()
        // defined in revlog.c
        let cindex = self.cindex(py).borrow();
        match item.extract::<Revision>(py) {
            Ok(rev) => {
                Ok(rev >= -1 && rev < cindex.inner().len(py)? as Revision)
            }
            Err(_) => {
                cindex.inner().call_method(
                    py,
                    "has_node",
                    PyTuple::new(py, &[item]),
                    None)?
                .extract(py)
            }
        }
    }

    def nodemap_data_all(&self) -> PyResult<PyBytes> {
        self.inner_nodemap_data_all(py)
    }

    def nodemap_data_incremental(&self) -> PyResult<PyObject> {
        self.inner_nodemap_data_incremental(py)
    }
    def update_nodemap_data(
        &self,
        docket: PyObject,
        nm_data: PyObject
    ) -> PyResult<PyObject> {
        self.inner_update_nodemap_data(py, docket, nm_data)
    }


});

impl MixedIndex {
    fn new(py: Python, cindex: PyObject) -> PyResult<MixedIndex> {
        Self::create_instance(
            py,
            RefCell::new(cindex::Index::new(py, cindex)?),
            RefCell::new(None),
            RefCell::new(None),
            RefCell::new(None),
        )
    }

    /// This is scaffolding at this point, but it could also become
    /// a way to start a persistent nodemap or perform a
    /// vacuum / repack operation
    fn fill_nodemap(
        &self,
        py: Python,
        nt: &mut NodeTree,
    ) -> PyResult<PyObject> {
        let index = self.cindex(py).borrow();
        for r in 0..index.len() {
            let rev = r as Revision;
            // in this case node() won't ever return None
            nt.insert(&*index, index.node(rev).unwrap(), rev)
                .map_err(|e| nodemap_error(py, e))?
        }
        Ok(py.None())
    }

    fn get_nodetree<'a>(
        &'a self,
        py: Python<'a>,
    ) -> PyResult<&'a RefCell<Option<NodeTree>>> {
        if self.nt(py).borrow().is_none() {
            let readonly = Box::new(Vec::new());
            let mut nt = NodeTree::load_bytes(readonly, 0);
            self.fill_nodemap(py, &mut nt)?;
            self.nt(py).borrow_mut().replace(nt);
        }
        Ok(self.nt(py))
    }

    /// forward a method call to the underlying C index
    fn call_cindex(
        &self,
        py: Python,
        name: &str,
        args: &PyTuple,
        kwargs: Option<&PyDict>,
    ) -> PyResult<PyObject> {
        self.cindex(py)
            .borrow()
            .inner()
            .call_method(py, name, args, kwargs)
    }

    pub fn clone_cindex(&self, py: Python) -> cindex::Index {
        self.cindex(py).borrow().clone_ref(py)
    }

    /// Returns the full nodemap bytes to be written as-is to disk
    fn inner_nodemap_data_all(&self, py: Python) -> PyResult<PyBytes> {
        let nodemap = self.get_nodetree(py)?.borrow_mut().take().unwrap();
        let (readonly, bytes) = nodemap.into_readonly_and_added_bytes();

        // If there's anything readonly, we need to build the data again from
        // scratch
        let bytes = if readonly.len() > 0 {
            let mut nt = NodeTree::load_bytes(Box::new(vec![]), 0);
            self.fill_nodemap(py, &mut nt)?;

            let (readonly, bytes) = nt.into_readonly_and_added_bytes();
            assert_eq!(readonly.len(), 0);

            bytes
        } else {
            bytes
        };

        let bytes = PyBytes::new(py, &bytes);
        Ok(bytes)
    }

    /// Returns the last saved docket along with the size of any changed data
    /// (in number of blocks), and said data as bytes.
    fn inner_nodemap_data_incremental(
        &self,
        py: Python,
    ) -> PyResult<PyObject> {
        let docket = self.docket(py).borrow();
        let docket = match docket.as_ref() {
            Some(d) => d,
            None => return Ok(py.None()),
        };

        let node_tree = self.get_nodetree(py)?.borrow_mut().take().unwrap();
        let masked_blocks = node_tree.masked_readonly_blocks();
        let (_, data) = node_tree.into_readonly_and_added_bytes();
        let changed = masked_blocks * std::mem::size_of::<Block>();

        Ok((docket, changed, PyBytes::new(py, &data))
            .to_py_object(py)
            .into_object())
    }

    /// Update the nodemap from the new (mmaped) data.
    /// The docket is kept as a reference for later incremental calls.
    fn inner_update_nodemap_data(
        &self,
        py: Python,
        docket: PyObject,
        nm_data: PyObject,
    ) -> PyResult<PyObject> {
        let buf = PyBuffer::get(py, &nm_data)?;
        let len = buf.item_count();

        // Build a slice from the mmap'ed buffer data
        let cbuf = buf.buf_ptr();
        let bytes = if std::mem::size_of::<u8>() == buf.item_size()
            && buf.is_c_contiguous()
            && u8::is_compatible_format(buf.format())
        {
            unsafe { std::slice::from_raw_parts(cbuf as *const u8, len) }
        } else {
            return Err(PyErr::new::<ValueError, _>(
                py,
                "Nodemap data buffer has an invalid memory representation"
                    .to_string(),
            ));
        };

        // Keep a reference to the mmap'ed buffer, otherwise we get a dangling
        // pointer.
        self.mmap(py).borrow_mut().replace(buf);

        let mut nt = NodeTree::load_bytes(Box::new(bytes), len);

        let data_tip =
            docket.getattr(py, "tip_rev")?.extract::<Revision>(py)?;
        self.docket(py).borrow_mut().replace(docket.clone_ref(py));
        let idx = self.cindex(py).borrow();
        let current_tip = idx.len();

        for r in (data_tip + 1)..current_tip as Revision {
            let rev = r as Revision;
            // in this case node() won't ever return None
            nt.insert(&*idx, idx.node(rev).unwrap(), rev)
                .map_err(|e| nodemap_error(py, e))?
        }

        *self.nt(py).borrow_mut() = Some(nt);

        Ok(py.None())
    }
}

fn revlog_error(py: Python) -> PyErr {
    match py
        .import("mercurial.error")
        .and_then(|m| m.get(py, "RevlogError"))
    {
        Err(e) => e,
        Ok(cls) => PyErr::from_instance(py, cls),
    }
}

fn rev_not_in_index(py: Python, rev: Revision) -> PyErr {
    PyErr::new::<ValueError, _>(
        py,
        format!(
            "Inconsistency: Revision {} found in nodemap \
             is not in revlog index",
            rev
        ),
    )
}

/// Standard treatment of NodeMapError
fn nodemap_error(py: Python, err: NodeMapError) -> PyErr {
    match err {
        NodeMapError::MultipleResults => revlog_error(py),
        NodeMapError::RevisionNotInIndex(r) => rev_not_in_index(py, r),
        NodeMapError::InvalidNodePrefix => {
            PyErr::new::<ValueError, _>(py, "Invalid node or prefix")
        }
    }
}

/// Create the module, with __package__ given from parent
pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.revlog", package);
    let m = PyModule::new(py, dotted_name)?;
    m.add(py, "__package__", package)?;
    m.add(py, "__doc__", "RevLog - Rust implementations")?;

    m.add_class::<MixedIndex>(py)?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;

    Ok(m)
}

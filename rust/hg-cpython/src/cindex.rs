// cindex.rs
//
// Copyright 2018 Georges Racinet <gracinet@anybox.fr>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings to use the Index defined by the parsers C extension
//!
//! Ideally, we should use an Index entirely implemented in Rust,
//! but this will take some time to get there.

use cpython::{
    exc::ImportError, exc::TypeError, ObjectProtocol, PyClone, PyErr,
    PyObject, PyResult, PyTuple, Python, PythonObject,
};
use hg::revlog::{Node, RevlogIndex};
use hg::{Graph, GraphError, Revision, WORKING_DIRECTORY_REVISION};
use libc::{c_int, ssize_t};

const REVLOG_CABI_VERSION: c_int = 3;

#[repr(C)]
pub struct Revlog_CAPI {
    abi_version: c_int,
    index_length:
        unsafe extern "C" fn(index: *mut revlog_capi::RawPyObject) -> ssize_t,
    index_node: unsafe extern "C" fn(
        index: *mut revlog_capi::RawPyObject,
        rev: ssize_t,
    ) -> *const Node,
    fast_rank: unsafe extern "C" fn(
        index: *mut revlog_capi::RawPyObject,
        rev: ssize_t,
    ) -> ssize_t,
    index_parents: unsafe extern "C" fn(
        index: *mut revlog_capi::RawPyObject,
        rev: c_int,
        ps: *mut [c_int; 2],
    ) -> c_int,
}

py_capsule!(
    from mercurial.cext.parsers import revlog_CAPI
        as revlog_capi for Revlog_CAPI);

/// A `Graph` backed up by objects and functions from revlog.c
///
/// This implementation of the `Graph` trait, relies on (pointers to)
/// - the C index object (`index` member)
/// - the `index_get_parents()` function (`parents` member)
///
/// # Safety
///
/// The C index itself is mutable, and this Rust exposition is **not
/// protected by the GIL**, meaning that this construct isn't safe with respect
/// to Python threads.
///
/// All callers of this `Index` must acquire the GIL and must not release it
/// while working.
///
/// # TODO find a solution to make it GIL safe again.
///
/// This is non trivial, and can wait until we have a clearer picture with
/// more Rust Mercurial constructs.
///
/// One possibility would be to a `GILProtectedIndex` wrapper enclosing
/// a `Python<'p>` marker and have it be the one implementing the
/// `Graph` trait, but this would mean the `Graph` implementor would become
/// likely to change between subsequent method invocations of the `hg-core`
/// objects (a serious change of the `hg-core` API):
/// either exposing ways to mutate the `Graph`, or making it a non persistent
/// parameter in the relevant methods that need one.
///
/// Another possibility would be to introduce an abstract lock handle into
/// the core API, that would be tied to `GILGuard` / `Python<'p>`
/// in the case of the `cpython` crate bindings yet could leave room for other
/// mechanisms in other contexts.
pub struct Index {
    index: PyObject,
    capi: &'static Revlog_CAPI,
}

impl Index {
    pub fn new(py: Python, index: PyObject) -> PyResult<Self> {
        let capi = unsafe { revlog_capi::retrieve(py)? };
        if capi.abi_version != REVLOG_CABI_VERSION {
            return Err(PyErr::new::<ImportError, _>(
                py,
                format!(
                    "ABI version mismatch: the C ABI revlog version {} \
                     does not match the {} expected by Rust hg-cpython",
                    capi.abi_version, REVLOG_CABI_VERSION
                ),
            ));
        }
        let compat: u64 = index.getattr(py, "rust_ext_compat")?.extract(py)?;
        if compat == 0 {
            return Err(PyErr::new::<TypeError, _>(
                py,
                "index object not compatible with Rust",
            ));
        }
        Ok(Index { index, capi })
    }

    /// return a reference to the CPython Index object in this Struct
    pub fn inner(&self) -> &PyObject {
        &self.index
    }

    pub fn append(&mut self, py: Python, tup: PyTuple) -> PyResult<PyObject> {
        self.index.call_method(
            py,
            "append",
            PyTuple::new(py, &[tup.into_object()]),
            None,
        )
    }
}

impl Clone for Index {
    fn clone(&self) -> Self {
        let guard = Python::acquire_gil();
        Index {
            index: self.index.clone_ref(guard.python()),
            capi: self.capi,
        }
    }
}

impl PyClone for Index {
    fn clone_ref(&self, py: Python) -> Self {
        Index {
            index: self.index.clone_ref(py),
            capi: self.capi,
        }
    }
}

impl Graph for Index {
    /// wrap a call to the C extern parents function
    fn parents(&self, rev: Revision) -> Result<[Revision; 2], GraphError> {
        if rev == WORKING_DIRECTORY_REVISION {
            return Err(GraphError::WorkingDirectoryUnsupported);
        }
        let mut res: [c_int; 2] = [0; 2];
        let code = unsafe {
            (self.capi.index_parents)(
                self.index.as_ptr(),
                rev as c_int,
                &mut res as *mut [c_int; 2],
            )
        };
        match code {
            0 => Ok(res),
            _ => Err(GraphError::ParentOutOfRange(rev)),
        }
    }
}

impl vcsgraph::graph::Graph for Index {
    fn parents(
        &self,
        rev: Revision,
    ) -> Result<vcsgraph::graph::Parents, vcsgraph::graph::GraphReadError>
    {
        match Graph::parents(self, rev) {
            Ok(parents) => Ok(vcsgraph::graph::Parents(parents)),
            Err(GraphError::ParentOutOfRange(rev)) => {
                Err(vcsgraph::graph::GraphReadError::KeyedInvalidKey(rev))
            }
            Err(GraphError::WorkingDirectoryUnsupported) => Err(
                vcsgraph::graph::GraphReadError::WorkingDirectoryUnsupported,
            ),
        }
    }
}

impl vcsgraph::graph::RankedGraph for Index {
    fn rank(
        &self,
        rev: Revision,
    ) -> Result<vcsgraph::graph::Rank, vcsgraph::graph::GraphReadError> {
        match unsafe {
            (self.capi.fast_rank)(self.index.as_ptr(), rev as ssize_t)
        } {
            -1 => Err(vcsgraph::graph::GraphReadError::InconsistentGraphData),
            rank => Ok(rank as usize),
        }
    }
}

impl RevlogIndex for Index {
    /// Note C return type is Py_ssize_t (hence signed), but we shall
    /// force it to unsigned, because it's a length
    fn len(&self) -> usize {
        unsafe { (self.capi.index_length)(self.index.as_ptr()) as usize }
    }

    fn node(&self, rev: Revision) -> Option<&Node> {
        let raw = unsafe {
            (self.capi.index_node)(self.index.as_ptr(), rev as ssize_t)
        };
        if raw.is_null() {
            None
        } else {
            // TODO it would be much better for the C layer to give us
            // a length, since the hash length will change in the near
            // future, but that's probably out of scope for the nodemap
            // patch series.
            //
            // The root of that unsafety relies in the signature of
            // `capi.index_node()` itself: returning a `Node` pointer
            // whereas it's a `char *` in the C counterpart.
            Some(unsafe { &*raw })
        }
    }
}

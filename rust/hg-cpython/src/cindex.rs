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

use cpython::{exc::ImportError, PyClone, PyErr, PyObject, PyResult, Python};
use hg::{Graph, GraphError, Revision, WORKING_DIRECTORY_REVISION};
use libc::c_int;

const REVLOG_CABI_VERSION: c_int = 1;

#[repr(C)]
pub struct Revlog_CAPI {
    abi_version: c_int,
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
        Ok(Index {
            index: index,
            capi: capi,
        })
    }

    /// return a reference to the CPython Index object in this Struct
    pub fn inner(&self) -> &PyObject {
        &self.index
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

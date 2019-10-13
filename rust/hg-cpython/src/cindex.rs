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

use cpython::{PyClone, PyObject, PyResult, Python};
use hg::{Graph, GraphError, Revision, WORKING_DIRECTORY_REVISION};
use libc::c_int;

py_capsule_fn!(
    from mercurial.cext.parsers import index_get_parents_CAPI
        as get_parents_capi
        signature (
            index: *mut RawPyObject,
            rev: c_int,
            ps: *mut [c_int; 2],
        ) -> c_int
);

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
    parents: get_parents_capi::CapsuleFn,
}

impl Index {
    pub fn new(py: Python, index: PyObject) -> PyResult<Self> {
        Ok(Index {
            index: index,
            parents: get_parents_capi::retrieve(py)?,
        })
    }
}

impl Clone for Index {
    fn clone(&self) -> Self {
        let guard = Python::acquire_gil();
        Index {
            index: self.index.clone_ref(guard.python()),
            parents: self.parents.clone(),
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
            (self.parents)(
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

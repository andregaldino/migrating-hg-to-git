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
#[cfg(feature = "python27")]
extern crate python27_sys as python_sys;
#[cfg(feature = "python3")]
extern crate python3_sys as python_sys;

use self::python_sys::PyCapsule_Import;
use cpython::{PyClone, PyErr, PyObject, PyResult, Python};
use hg::{Graph, GraphError, Revision};
use libc::c_int;
use std::ffi::CStr;
use std::mem::transmute;

type IndexParentsFn = unsafe extern "C" fn(
    index: *mut python_sys::PyObject,
    rev: c_int,
    ps: *mut [c_int; 2],
) -> c_int;

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
    parents: IndexParentsFn,
}

impl Index {
    pub fn new(py: Python, index: PyObject) -> PyResult<Self> {
        Ok(Index {
            index: index,
            parents: decapsule_parents_fn(py)?,
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

/// Return the `index_get_parents` function of the parsers C Extension module.
///
/// A pointer to the function is stored in the `parsers` module as a
/// standard [Python capsule](https://docs.python.org/2/c-api/capsule.html).
///
/// This function retrieves the capsule and casts the function pointer
///
/// Casting function pointers is one of the rare cases of
/// legitimate use cases of `mem::transmute()` (see
/// https://doc.rust-lang.org/std/mem/fn.transmute.html of
/// `mem::transmute()`.
/// It is inappropriate for architectures where
/// function and data pointer sizes differ (so-called "Harvard
/// architectures"), but these are nowadays mostly DSPs
/// and microcontrollers, hence out of our scope.
fn decapsule_parents_fn(py: Python) -> PyResult<IndexParentsFn> {
    unsafe {
        let caps_name = CStr::from_bytes_with_nul_unchecked(
            b"mercurial.cext.parsers.index_get_parents_CAPI\0",
        );
        let from_caps = PyCapsule_Import(caps_name.as_ptr(), 0);
        if from_caps.is_null() {
            return Err(PyErr::fetch(py));
        }
        Ok(transmute(from_caps))
    }
}

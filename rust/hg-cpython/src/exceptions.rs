// ancestors.rs
//
// Copyright 2018 Georges Racinet <gracinet@anybox.fr>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for Rust errors
//!
//! [`GraphError`] exposes `hg::GraphError` as a subclass of `ValueError`
//! but some variants of `hg::GraphError` can be converted directly to other
//! existing Python exceptions if appropriate.
//!
//! [`GraphError`]: struct.GraphError.html
use cpython::{
    exc::{RuntimeError, ValueError},
    py_exception, PyErr, Python,
};
use hg;

py_exception!(rustext, GraphError, ValueError);

impl GraphError {
    pub fn pynew(py: Python, inner: hg::GraphError) -> PyErr {
        match inner {
            hg::GraphError::ParentOutOfRange(r) => {
                GraphError::new(py, ("ParentOutOfRange", r))
            }
            hg::GraphError::WorkingDirectoryUnsupported => {
                match py
                    .import("mercurial.error")
                    .and_then(|m| m.get(py, "WdirUnsupported"))
                {
                    Err(e) => e,
                    Ok(cls) => PyErr::from_instance(py, cls),
                }
            }
        }
    }

    pub fn pynew_from_vcsgraph(
        py: Python,
        inner: vcsgraph::graph::GraphReadError,
    ) -> PyErr {
        match inner {
            vcsgraph::graph::GraphReadError::InconsistentGraphData => {
                GraphError::new(py, "InconsistentGraphData")
            }
            vcsgraph::graph::GraphReadError::InvalidKey => {
                GraphError::new(py, "ParentOutOfRange")
            }
            vcsgraph::graph::GraphReadError::KeyedInvalidKey(r) => {
                GraphError::new(py, ("ParentOutOfRange", r))
            }
            vcsgraph::graph::GraphReadError::WorkingDirectoryUnsupported => {
                match py
                    .import("mercurial.error")
                    .and_then(|m| m.get(py, "WdirUnsupported"))
                {
                    Err(e) => e,
                    Ok(cls) => PyErr::from_instance(py, cls),
                }
            }
        }
    }
}

py_exception!(rustext, HgPathPyError, RuntimeError);
py_exception!(rustext, FallbackError, RuntimeError);
py_exception!(shared_ref, AlreadyBorrowed, RuntimeError);

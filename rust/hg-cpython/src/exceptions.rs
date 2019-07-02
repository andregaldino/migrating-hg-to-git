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
    exc::{IOError, RuntimeError, ValueError},
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
}

py_exception!(rustext, PatternError, RuntimeError);
py_exception!(rustext, PatternFileError, RuntimeError);

impl PatternError {
    pub fn pynew(py: Python, inner: hg::PatternError) -> PyErr {
        match inner {
            hg::PatternError::UnsupportedSyntax(m) => {
                PatternError::new(py, ("PatternError", m))
            }
        }
    }
}

impl PatternFileError {
    pub fn pynew(py: Python, inner: hg::PatternFileError) -> PyErr {
        match inner {
            hg::PatternFileError::IO(e) => {
                let value = (e.raw_os_error().unwrap_or(2), e.to_string());
                PyErr::new::<IOError, _>(py, value)
            }
            hg::PatternFileError::Pattern(e, l) => match e {
                hg::PatternError::UnsupportedSyntax(m) => {
                    PatternFileError::new(py, ("PatternFileError", m, l))
                }
            },
        }
    }
}

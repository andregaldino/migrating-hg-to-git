// revlog.rs
//
// Copyright 2019 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::cindex;
use cpython::{PyObject, PyResult, Python};

/// Return a Struct implementing the Graph trait
pub(crate) fn pyindex_to_graph(
    py: Python,
    index: PyObject,
) -> PyResult<cindex::Index> {
    cindex::Index::new(py, index)
}

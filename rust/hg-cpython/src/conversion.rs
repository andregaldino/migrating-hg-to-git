// conversion.rs
//
// Copyright 2019 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the hg::ancestors module provided by the
//! `hg-core` crate. From Python, this will be seen as `rustext.ancestor`

use cpython::{
    ObjectProtocol, PyDict, PyObject, PyResult, PyTuple, Python, PythonObject,
    ToPyObject,
};
use hg::Revision;
use std::collections::HashSet;
use std::iter::FromIterator;

/// Utility function to convert a Python iterable into various collections
///
/// We need this in particular to feed to various methods of inner objects
/// with `impl IntoIterator<Item=Revision>` arguments, because
/// a `PyErr` can arise at each step of iteration, whereas these methods
/// expect iterables over `Revision`, not over some `Result<Revision, PyErr>`
pub fn rev_pyiter_collect<C>(py: Python, revs: &PyObject) -> PyResult<C>
where
    C: FromIterator<Revision>,
{
    revs.iter(py)?
        .map(|r| r.and_then(|o| o.extract::<Revision>(py)))
        .collect()
}

/// Copy and convert an `HashSet<Revision>` in a Python set
///
/// This will probably turn useless once `PySet` support lands in
/// `rust-cpython`.
///
/// This builds a Python tuple, then calls Python's "set()" on it
pub fn py_set(py: Python, set: &HashSet<Revision>) -> PyResult<PyObject> {
    let as_vec: Vec<PyObject> = set
        .iter()
        .map(|rev| rev.to_py_object(py).into_object())
        .collect();
    let as_pytuple = PyTuple::new(py, as_vec.as_slice());

    let locals = PyDict::new(py);
    locals.set_item(py, "obj", as_pytuple.to_py_object(py))?;
    py.eval("set(obj)", None, Some(&locals))
}

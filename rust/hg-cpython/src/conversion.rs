// conversion.rs
//
// Copyright 2019 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the hg::ancestors module provided by the
//! `hg-core` crate. From Python, this will be seen as `rustext.ancestor`

use cpython::{ObjectProtocol, PyObject, PyResult, Python};
use hg::Revision;
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

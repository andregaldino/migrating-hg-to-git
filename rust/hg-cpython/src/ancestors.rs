// ancestors.rs
//
// Copyright 2018 Georges Racinet <gracinet@anybox.fr>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Bindings for the `hg::ancestors` module provided by the
//! `hg-core` crate. From Python, this will be seen as `rustext.ancestor`
//! and can be used as replacement for the the pure `ancestor` Python module.
//!
//! # Classes visible from Python:
//! - [`LazyAncestors`] is the Rust implementation of
//!   `mercurial.ancestor.lazyancestors`.
//!   The only difference is that it is instantiated with a C `parsers.index`
//!   instance instead of a parents function.
//!
//! - [`AncestorsIterator`] is the Rust counterpart of the
//!   `ancestor._lazyancestorsiter` Python generator.
//!   From Python, instances of this should be mainly obtained by calling
//!   `iter()` on a [`LazyAncestors`] instance.
//!
//! [`LazyAncestors`]: struct.LazyAncestors.html
//! [`AncestorsIterator`]: struct.AncestorsIterator.html
use cindex::Index;
use cpython::{
    ObjectProtocol, PyClone, PyDict, PyModule, PyObject, PyResult, Python,
};
use exceptions::GraphError;
use hg::Revision;
use hg::{AncestorsIterator as CoreIterator, LazyAncestors as CoreLazy};
use std::cell::RefCell;

/// Utility function to convert a Python iterable into a Vec<Revision>
///
/// We need this to feed to `AncestorIterators` constructors because
/// a `PyErr` can arise at each step of iteration, whereas our inner objects
/// expect iterables over `Revision`, not over some `Result<Revision, PyErr>`
fn reviter_to_revvec(py: Python, revs: PyObject) -> PyResult<Vec<Revision>> {
    revs.iter(py)?
        .map(|r| r.and_then(|o| o.extract::<Revision>(py)))
        .collect()
}

py_class!(pub class AncestorsIterator |py| {
    data inner: RefCell<Box<CoreIterator<Index>>>;

    def __next__(&self) -> PyResult<Option<Revision>> {
        match self.inner(py).borrow_mut().next() {
            Some(Err(e)) => Err(GraphError::pynew(py, e)),
            None => Ok(None),
            Some(Ok(r)) => Ok(Some(r)),
        }
    }

    def __contains__(&self, rev: Revision) -> PyResult<bool> {
        self.inner(py).borrow_mut().contains(rev)
            .map_err(|e| GraphError::pynew(py, e))
    }

    def __iter__(&self) -> PyResult<Self> {
        Ok(self.clone_ref(py))
    }

    def __new__(_cls, index: PyObject, initrevs: PyObject, stoprev: Revision,
                inclusive: bool) -> PyResult<AncestorsIterator> {
        let initvec = reviter_to_revvec(py, initrevs)?;
        let ait = CoreIterator::new(
            Index::new(py, index)?,
            initvec,
            stoprev,
            inclusive,
        )
        .map_err(|e| GraphError::pynew(py, e))?;
        AncestorsIterator::from_inner(py, ait)
    }

});

impl AncestorsIterator {
    pub fn from_inner(py: Python, ait: CoreIterator<Index>) -> PyResult<Self> {
        Self::create_instance(py, RefCell::new(Box::new(ait)))
    }
}

py_class!(pub class LazyAncestors |py| {
    data inner: RefCell<Box<CoreLazy<Index>>>;

    def __contains__(&self, rev: Revision) -> PyResult<bool> {
        self.inner(py)
            .borrow_mut()
            .contains(rev)
            .map_err(|e| GraphError::pynew(py, e))
    }

    def __iter__(&self) -> PyResult<AncestorsIterator> {
        AncestorsIterator::from_inner(py, self.inner(py).borrow().iter())
    }

    def __bool__(&self) -> PyResult<bool> {
        Ok(!self.inner(py).borrow().is_empty())
    }

    def __new__(_cls, index: PyObject, initrevs: PyObject, stoprev: Revision,
                inclusive: bool) -> PyResult<Self> {
        let initvec = reviter_to_revvec(py, initrevs)?;

        let lazy =
            CoreLazy::new(Index::new(py, index)?, initvec, stoprev, inclusive)
                .map_err(|e| GraphError::pynew(py, e))?;

        Self::create_instance(py, RefCell::new(Box::new(lazy)))
        }

});

/// Create the module, with `__package__` given from parent
pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.ancestor", package);
    let m = PyModule::new(py, dotted_name)?;
    m.add(py, "__package__", package)?;
    m.add(
        py,
        "__doc__",
        "Generic DAG ancestor algorithms - Rust implementation",
    )?;
    m.add_class::<AncestorsIterator>(py)?;
    m.add_class::<LazyAncestors>(py)?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;
    // Example C code (see pyexpat.c and import.c) will "give away the
    // reference", but we won't because it will be consumed once the
    // Rust PyObject is dropped.
    Ok(m)
}

// macros.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Macros for use in the `hg-cpython` bridge library.

use crate::exceptions::AlreadyBorrowed;
use cpython::{PyResult, Python};
use std::cell::{Cell, Ref, RefCell, RefMut};

/// Manages the shared state between Python and Rust
#[derive(Default)]
pub struct PySharedState {
    leak_count: Cell<usize>,
    mutably_borrowed: Cell<bool>,
}

impl PySharedState {
    pub fn borrow_mut<'a, T>(
        &'a self,
        py: Python<'a>,
        pyrefmut: RefMut<'a, T>,
    ) -> PyResult<PyRefMut<'a, T>> {
        if self.mutably_borrowed.get() {
            return Err(AlreadyBorrowed::new(
                py,
                "Cannot borrow mutably while there exists another \
                 mutable reference in a Python object",
            ));
        }
        match self.leak_count.get() {
            0 => {
                self.mutably_borrowed.replace(true);
                Ok(PyRefMut::new(py, pyrefmut, self))
            }
            // TODO
            // For now, this works differently than Python references
            // in the case of iterators.
            // Python does not complain when the data an iterator
            // points to is modified if the iterator is never used
            // afterwards.
            // Here, we are stricter than this by refusing to give a
            // mutable reference if it is already borrowed.
            // While the additional safety might be argued for, it
            // breaks valid programming patterns in Python and we need
            // to fix this issue down the line.
            _ => Err(AlreadyBorrowed::new(
                py,
                "Cannot borrow mutably while there are \
                 immutable references in Python objects",
            )),
        }
    }

    /// Return a reference to the wrapped data with an artificial static
    /// lifetime.
    /// We need to be protected by the GIL for thread-safety.
    ///
    /// # Safety
    ///
    /// This is highly unsafe since the lifetime of the given data can be
    /// extended. Do not call this function directly.
    pub unsafe fn leak_immutable<T>(
        &self,
        py: Python,
        data: &PySharedRefCell<T>,
    ) -> PyResult<&'static T> {
        if self.mutably_borrowed.get() {
            return Err(AlreadyBorrowed::new(
                py,
                "Cannot borrow immutably while there is a \
                 mutable reference in Python objects",
            ));
        }
        let ptr = data.as_ptr();
        self.leak_count.replace(self.leak_count.get() + 1);
        Ok(&*ptr)
    }

    /// # Safety
    ///
    /// It's unsafe to update the reference count without knowing the
    /// reference is deleted. Do not call this function directly.
    pub unsafe fn decrease_leak_count(&self, _py: Python, mutable: bool) {
        self.leak_count
            .replace(self.leak_count.get().saturating_sub(1));
        if mutable {
            self.mutably_borrowed.replace(false);
        }
    }
}

/// `RefCell` wrapper to be safely used in conjunction with `PySharedState`.
///
/// Only immutable operation is allowed through this interface.
#[derive(Debug)]
pub struct PySharedRefCell<T> {
    inner: RefCell<T>,
}

impl<T> PySharedRefCell<T> {
    pub const fn new(value: T) -> PySharedRefCell<T> {
        Self {
            inner: RefCell::new(value),
        }
    }

    pub fn borrow(&self) -> Ref<T> {
        // py_shared_state isn't involved since
        // - inner.borrow() would fail if self is mutably borrowed,
        // - and inner.borrow_mut() would fail while self is borrowed.
        self.inner.borrow()
    }

    pub fn as_ptr(&self) -> *mut T {
        self.inner.as_ptr()
    }

    pub unsafe fn borrow_mut(&self) -> RefMut<T> {
        // must be borrowed by self.py_shared_state(py).borrow_mut().
        self.inner.borrow_mut()
    }
}

/// Holds a mutable reference to data shared between Python and Rust.
pub struct PyRefMut<'a, T> {
    inner: RefMut<'a, T>,
    py_shared_state: &'a PySharedState,
}

impl<'a, T> PyRefMut<'a, T> {
    // Must be constructed by PySharedState after checking its leak_count.
    // Otherwise, drop() would incorrectly update the state.
    fn new(
        _py: Python<'a>,
        inner: RefMut<'a, T>,
        py_shared_state: &'a PySharedState,
    ) -> Self {
        Self {
            inner,
            py_shared_state,
        }
    }
}

impl<'a, T> std::ops::Deref for PyRefMut<'a, T> {
    type Target = RefMut<'a, T>;

    fn deref(&self) -> &Self::Target {
        &self.inner
    }
}
impl<'a, T> std::ops::DerefMut for PyRefMut<'a, T> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.inner
    }
}

impl<'a, T> Drop for PyRefMut<'a, T> {
    fn drop(&mut self) {
        let gil = Python::acquire_gil();
        let py = gil.python();
        unsafe {
            self.py_shared_state.decrease_leak_count(py, true);
        }
    }
}

/// Allows a `py_class!` generated struct to share references to one of its
/// data members with Python.
///
/// # Warning
///
/// The targeted `py_class!` needs to have the
/// `data py_shared_state: PySharedState;` data attribute to compile.
/// A better, more complicated macro is needed to automatically insert it,
/// but this one is not yet really battle tested (what happens when
/// multiple references are needed?). See the example below.
///
/// TODO allow Python container types: for now, integration with the garbage
///     collector does not extend to Rust structs holding references to Python
///     objects. Should the need surface, `__traverse__` and `__clear__` will
///     need to be written as per the `rust-cpython` docs on GC integration.
///
/// # Parameters
///
/// * `$name` is the same identifier used in for `py_class!` macro call.
/// * `$inner_struct` is the identifier of the underlying Rust struct
/// * `$data_member` is the identifier of the data member of `$inner_struct`
/// that will be shared.
/// * `$leaked` is the identifier to give to the struct that will manage
/// references to `$name`, to be used for example in other macros like
/// `py_shared_iterator`.
///
/// # Example
///
/// ```
/// struct MyStruct {
///     inner: Vec<u32>;
/// }
///
/// py_class!(pub class MyType |py| {
///     data inner: PySharedRefCell<MyStruct>;
///     data py_shared_state: PySharedState;
/// });
///
/// py_shared_ref!(MyType, MyStruct, inner, MyTypeLeakedRef);
/// ```
macro_rules! py_shared_ref {
    (
        $name: ident,
        $inner_struct: ident,
        $data_member: ident,
        $leaked: ident,
    ) => {
        impl $name {
            fn borrow_mut<'a>(
                &'a self,
                py: Python<'a>,
            ) -> PyResult<crate::ref_sharing::PyRefMut<'a, $inner_struct>>
            {
                // assert $data_member type
                use crate::ref_sharing::PySharedRefCell;
                let data: &PySharedRefCell<_> = self.$data_member(py);
                self.py_shared_state(py)
                    .borrow_mut(py, unsafe { data.borrow_mut() })
            }

            /// Returns a leaked reference and its management object.
            ///
            /// # Safety
            ///
            /// It's up to you to make sure that the management object lives
            /// longer than the leaked reference. Otherwise, you'll get a
            /// dangling reference.
            unsafe fn leak_immutable<'a>(
                &'a self,
                py: Python<'a>,
            ) -> PyResult<($leaked, &'static $inner_struct)> {
                // assert $data_member type
                use crate::ref_sharing::PySharedRefCell;
                let data: &PySharedRefCell<_> = self.$data_member(py);
                let static_ref =
                    self.py_shared_state(py).leak_immutable(py, data)?;
                let leak_handle = $leaked::new(py, self);
                Ok((leak_handle, static_ref))
            }
        }

        /// Manage immutable references to `$name` leaked into Python
        /// iterators.
        ///
        /// In truth, this does not represent leaked references themselves;
        /// it is instead useful alongside them to manage them.
        pub struct $leaked {
            inner: $name,
        }

        impl $leaked {
            // Marked as unsafe so client code wouldn't construct $leaked
            // struct by mistake. Its drop() is unsafe.
            unsafe fn new(py: Python, inner: &$name) -> Self {
                Self {
                    inner: inner.clone_ref(py),
                }
            }
        }

        impl Drop for $leaked {
            fn drop(&mut self) {
                let gil = Python::acquire_gil();
                let py = gil.python();
                let state = self.inner.py_shared_state(py);
                unsafe {
                    state.decrease_leak_count(py, false);
                }
            }
        }
    };
}

/// Defines a `py_class!` that acts as a Python iterator over a Rust iterator.
///
/// TODO: this is a bit awkward to use, and a better (more complicated)
///     procedural macro would simplify the interface a lot.
///
/// # Parameters
///
/// * `$name` is the identifier to give to the resulting Rust struct.
/// * `$leaked` corresponds to `$leaked` in the matching `py_shared_ref!` call.
/// * `$iterator_type` is the type of the Rust iterator.
/// * `$success_func` is a function for processing the Rust `(key, value)`
/// tuple on iteration success, turning it into something Python understands.
/// * `$success_func` is the return type of `$success_func`
///
/// # Example
///
/// ```
/// struct MyStruct {
///     inner: HashMap<Vec<u8>, Vec<u8>>;
/// }
///
/// py_class!(pub class MyType |py| {
///     data inner: PySharedRefCell<MyStruct>;
///     data py_shared_state: PySharedState;
///
///     def __iter__(&self) -> PyResult<MyTypeItemsIterator> {
///         let (leak_handle, leaked_ref) = unsafe { self.leak_immutable(py)? };
///         MyTypeItemsIterator::create_instance(
///             py,
///             RefCell::new(Some(leak_handle)),
///             RefCell::new(leaked_ref.iter()),
///         )
///     }
/// });
///
/// impl MyType {
///     fn translate_key_value(
///         py: Python,
///         res: (&Vec<u8>, &Vec<u8>),
///     ) -> PyResult<Option<(PyBytes, PyBytes)>> {
///         let (f, entry) = res;
///         Ok(Some((
///             PyBytes::new(py, f),
///             PyBytes::new(py, entry),
///         )))
///     }
/// }
///
/// py_shared_ref!(MyType, MyStruct, inner, MyTypeLeakedRef);
///
/// py_shared_iterator!(
///     MyTypeItemsIterator,
///     MyTypeLeakedRef,
///     HashMap<'static, Vec<u8>, Vec<u8>>,
///     MyType::translate_key_value,
///     Option<(PyBytes, PyBytes)>
/// );
/// ```
macro_rules! py_shared_iterator {
    (
        $name: ident,
        $leaked: ident,
        $iterator_type: ty,
        $success_func: expr,
        $success_type: ty
    ) => {
        py_class!(pub class $name |py| {
            data inner: RefCell<Option<$leaked>>;
            data it: RefCell<$iterator_type>;

            def __next__(&self) -> PyResult<$success_type> {
                let mut inner_opt = self.inner(py).borrow_mut();
                if inner_opt.is_some() {
                    match self.it(py).borrow_mut().next() {
                        None => {
                            // replace Some(inner) by None, drop $leaked
                            inner_opt.take();
                            Ok(None)
                        }
                        Some(res) => {
                            $success_func(py, res)
                        }
                    }
                } else {
                    Ok(None)
                }
            }

            def __iter__(&self) -> PyResult<Self> {
                Ok(self.clone_ref(py))
            }
        });

        impl $name {
            pub fn from_inner(
                py: Python,
                leaked: Option<$leaked>,
                it: $iterator_type
            ) -> PyResult<Self> {
                Self::create_instance(
                    py,
                    RefCell::new(leaked),
                    RefCell::new(it)
                )
            }
        }
    };
}

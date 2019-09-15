// ref_sharing.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

//! Macros for use in the `hg-cpython` bridge library.

use crate::exceptions::AlreadyBorrowed;
use cpython::{PyClone, PyObject, PyResult, Python};
use std::cell::{Cell, Ref, RefCell, RefMut};

/// Manages the shared state between Python and Rust
#[derive(Debug, Default)]
pub struct PySharedState {
    leak_count: Cell<usize>,
    mutably_borrowed: Cell<bool>,
}

// &PySharedState can be Send because any access to inner cells is
// synchronized by the GIL.
unsafe impl Sync for PySharedState {}

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

    /// Return a reference to the wrapped data and its state with an
    /// artificial static lifetime.
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
    ) -> PyResult<(&'static T, &'static PySharedState)> {
        if self.mutably_borrowed.get() {
            return Err(AlreadyBorrowed::new(
                py,
                "Cannot borrow immutably while there is a \
                 mutable reference in Python objects",
            ));
        }
        // TODO: it's weird that self is data.py_shared_state. Maybe we
        // can move stuff to PySharedRefCell?
        let ptr = data.as_ptr();
        let state_ptr: *const PySharedState = &data.py_shared_state;
        self.leak_count.replace(self.leak_count.get() + 1);
        Ok((&*ptr, &*state_ptr))
    }

    /// # Safety
    ///
    /// It's unsafe to update the reference count without knowing the
    /// reference is deleted. Do not call this function directly.
    pub unsafe fn decrease_leak_count(&self, _py: Python, mutable: bool) {
        if mutable {
            assert_eq!(self.leak_count.get(), 0);
            assert!(self.mutably_borrowed.get());
            self.mutably_borrowed.replace(false);
        } else {
            let count = self.leak_count.get();
            assert!(count > 0);
            self.leak_count.replace(count - 1);
        }
    }
}

/// `RefCell` wrapper to be safely used in conjunction with `PySharedState`.
///
/// Only immutable operation is allowed through this interface.
#[derive(Debug)]
pub struct PySharedRefCell<T> {
    inner: RefCell<T>,
    py_shared_state: PySharedState,
}

impl<T> PySharedRefCell<T> {
    pub fn new(value: T) -> PySharedRefCell<T> {
        Self {
            inner: RefCell::new(value),
            py_shared_state: PySharedState::default(),
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

    // TODO: maybe this should be named as try_borrow_mut(), and use
    // inner.try_borrow_mut(). The current implementation panics if
    // self.inner has been borrowed, but returns error if py_shared_state
    // refuses to borrow.
    pub fn borrow_mut<'a>(
        &'a self,
        py: Python<'a>,
    ) -> PyResult<PyRefMut<'a, T>> {
        self.py_shared_state.borrow_mut(py, self.inner.borrow_mut())
    }
}

/// Sharable data member of type `T` borrowed from the `PyObject`.
pub struct PySharedRef<'a, T> {
    py: Python<'a>,
    owner: &'a PyObject,
    data: &'a PySharedRefCell<T>,
}

impl<'a, T> PySharedRef<'a, T> {
    /// # Safety
    ///
    /// The `data` must be owned by the `owner`. Otherwise, the leak count
    /// would get wrong.
    pub unsafe fn new(
        py: Python<'a>,
        owner: &'a PyObject,
        data: &'a PySharedRefCell<T>,
    ) -> Self {
        Self { py, owner, data }
    }

    pub fn borrow(&self) -> Ref<'a, T> {
        self.data.borrow()
    }

    pub fn borrow_mut(&self) -> PyResult<PyRefMut<'a, T>> {
        self.data.borrow_mut(self.py)
    }

    /// Returns a leaked reference.
    pub fn leak_immutable(&self) -> PyResult<PyLeakedRef<&'static T>> {
        let state = &self.data.py_shared_state;
        unsafe {
            let (static_ref, static_state_ref) =
                state.leak_immutable(self.py, self.data)?;
            Ok(PyLeakedRef::new(
                self.py,
                self.owner,
                static_ref,
                static_state_ref,
            ))
        }
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
/// * `$shared_accessor` is the function name to be generated, which allows
/// safe access to the data member.
///
/// # Safety
///
/// `$data_member` must persist while the `$name` object is alive. In other
/// words, it must be an accessor to a data field of the Python object.
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
/// });
///
/// py_shared_ref!(MyType, MyStruct, inner, inner_shared);
/// ```
macro_rules! py_shared_ref {
    (
        $name: ident,
        $inner_struct: ident,
        $data_member: ident,
        $shared_accessor: ident
    ) => {
        impl $name {
            /// Returns a safe reference to the shared `$data_member`.
            ///
            /// This function guarantees that `PySharedRef` is created with
            /// the valid `self` and `self.$data_member(py)` pair.
            fn $shared_accessor<'a>(
                &'a self,
                py: Python<'a>,
            ) -> $crate::ref_sharing::PySharedRef<'a, $inner_struct> {
                use cpython::PythonObject;
                use $crate::ref_sharing::PySharedRef;
                let owner = self.as_object();
                let data = self.$data_member(py);
                unsafe { PySharedRef::new(py, owner, data) }
            }
        }
    };
}

/// Manage immutable references to `PyObject` leaked into Python iterators.
pub struct PyLeakedRef<T> {
    inner: PyObject,
    data: Option<T>,
    py_shared_state: &'static PySharedState,
}

// DO NOT implement Deref for PyLeakedRef<T>! Dereferencing PyLeakedRef
// without taking Python GIL wouldn't be safe.

impl<T> PyLeakedRef<T> {
    /// # Safety
    ///
    /// The `py_shared_state` must be owned by the `inner` Python object.
    // Marked as unsafe so client code wouldn't construct PyLeakedRef
    // struct by mistake. Its drop() is unsafe.
    pub unsafe fn new(
        py: Python,
        inner: &PyObject,
        data: T,
        py_shared_state: &'static PySharedState,
    ) -> Self {
        Self {
            inner: inner.clone_ref(py),
            data: Some(data),
            py_shared_state,
        }
    }

    /// Returns an immutable reference to the inner value.
    pub fn get_ref<'a>(&'a self, _py: Python<'a>) -> &'a T {
        self.data.as_ref().unwrap()
    }

    /// Returns a mutable reference to the inner value.
    ///
    /// Typically `T` is an iterator. If `T` is an immutable reference,
    /// `get_mut()` is useless since the inner value can't be mutated.
    pub fn get_mut<'a>(&'a mut self, _py: Python<'a>) -> &'a mut T {
        self.data.as_mut().unwrap()
    }

    /// Converts the inner value by the given function.
    ///
    /// Typically `T` is a static reference to a container, and `U` is an
    /// iterator of that container.
    ///
    /// # Safety
    ///
    /// The lifetime of the object passed in to the function `f` is cheated.
    /// It's typically a static reference, but is valid only while the
    /// corresponding `PyLeakedRef` is alive. Do not copy it out of the
    /// function call.
    pub unsafe fn map<U>(
        mut self,
        py: Python,
        f: impl FnOnce(T) -> U,
    ) -> PyLeakedRef<U> {
        // f() could make the self.data outlive. That's why map() is unsafe.
        // In order to make this function safe, maybe we'll need a way to
        // temporarily restrict the lifetime of self.data and translate the
        // returned object back to Something<'static>.
        let new_data = f(self.data.take().unwrap());
        PyLeakedRef {
            inner: self.inner.clone_ref(py),
            data: Some(new_data),
            py_shared_state: self.py_shared_state,
        }
    }
}

impl<T> Drop for PyLeakedRef<T> {
    fn drop(&mut self) {
        // py_shared_state should be alive since we do have
        // a Python reference to the owner object. Taking GIL makes
        // sure that the state is only accessed by this thread.
        let gil = Python::acquire_gil();
        let py = gil.python();
        if self.data.is_none() {
            return; // moved to another PyLeakedRef
        }
        unsafe {
            self.py_shared_state.decrease_leak_count(py, false);
        }
    }
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
///
///     def __iter__(&self) -> PyResult<MyTypeItemsIterator> {
///         let leaked_ref = self.inner_shared(py).leak_immutable()?;
///         MyTypeItemsIterator::from_inner(
///             py,
///             unsafe { leaked_ref.map(py, |o| o.iter()) },
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
///     PyLeakedRef<HashMap<'static, Vec<u8>, Vec<u8>>>,
///     MyType::translate_key_value,
///     Option<(PyBytes, PyBytes)>
/// );
/// ```
macro_rules! py_shared_iterator {
    (
        $name: ident,
        $leaked: ty,
        $success_func: expr,
        $success_type: ty
    ) => {
        py_class!(pub class $name |py| {
            data inner: RefCell<Option<$leaked>>;

            def __next__(&self) -> PyResult<$success_type> {
                let mut inner_opt = self.inner(py).borrow_mut();
                if let Some(leaked) = inner_opt.as_mut() {
                    match leaked.get_mut(py).next() {
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
                leaked: $leaked,
            ) -> PyResult<Self> {
                Self::create_instance(
                    py,
                    RefCell::new(Some(leaked)),
                )
            }
        }
    };
}

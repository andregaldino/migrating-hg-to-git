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
use cpython::{exc, PyClone, PyErr, PyObject, PyResult, Python};
use std::cell::{Ref, RefCell, RefMut};
use std::ops::{Deref, DerefMut};
use std::sync::atomic::{AtomicUsize, Ordering};

/// Manages the shared state between Python and Rust
///
/// `PySharedState` is owned by `PySharedRefCell`, and is shared across its
/// derived references. The consistency of these references are guaranteed
/// as follows:
///
/// - The immutability of `py_class!` object fields. Any mutation of
///   `PySharedRefCell` is allowed only through its `borrow_mut()`.
/// - The `py: Python<'_>` token, which makes sure that any data access is
///   synchronized by the GIL.
/// - The underlying `RefCell`, which prevents `PySharedRefCell` data from
///   being directly borrowed or leaked while it is mutably borrowed.
/// - The `borrow_count`, which is the number of references borrowed from
///   `PyLeaked`. Just like `RefCell`, mutation is prohibited while `PyLeaked`
///   is borrowed.
/// - The `generation` counter, which increments on `borrow_mut()`. `PyLeaked`
///   reference is valid only if the `current_generation()` equals to the
///   `generation` at the time of `leak_immutable()`.
#[derive(Debug, Default)]
struct PySharedState {
    // The counter variable could be Cell<usize> since any operation on
    // PySharedState is synchronized by the GIL, but being "atomic" makes
    // PySharedState inherently Sync. The ordering requirement doesn't
    // matter thanks to the GIL.
    borrow_count: AtomicUsize,
    generation: AtomicUsize,
}

impl PySharedState {
    /// Return a reference to the wrapped data and its state with an
    /// artificial static lifetime.
    /// We need to be protected by the GIL for thread-safety.
    ///
    /// # Safety
    ///
    /// This is highly unsafe since the lifetime of the given data can be
    /// extended. Do not call this function directly.
    unsafe fn leak_immutable<T>(
        &self,
        _py: Python,
        data: Ref<T>,
    ) -> (&'static T, &'static PySharedState) {
        let ptr: *const T = &*data;
        let state_ptr: *const PySharedState = self;
        (&*ptr, &*state_ptr)
    }

    fn current_borrow_count(&self, _py: Python) -> usize {
        self.borrow_count.load(Ordering::Relaxed)
    }

    fn increase_borrow_count(&self, _py: Python) {
        // Note that this wraps around if there are more than usize::MAX
        // borrowed references, which shouldn't happen due to memory limit.
        self.borrow_count.fetch_add(1, Ordering::Relaxed);
    }

    fn decrease_borrow_count(&self, _py: Python) {
        let prev_count = self.borrow_count.fetch_sub(1, Ordering::Relaxed);
        assert!(prev_count > 0);
    }

    fn current_generation(&self, _py: Python) -> usize {
        self.generation.load(Ordering::Relaxed)
    }

    fn increment_generation(&self, py: Python) {
        assert_eq!(self.current_borrow_count(py), 0);
        // Note that this wraps around to the same value if mutably
        // borrowed more than usize::MAX times, which wouldn't happen
        // in practice.
        self.generation.fetch_add(1, Ordering::Relaxed);
    }
}

/// Helper to keep the borrow count updated while the shared object is
/// immutably borrowed without using the `RefCell` interface.
struct BorrowPyShared<'a> {
    py: Python<'a>,
    py_shared_state: &'a PySharedState,
}

impl<'a> BorrowPyShared<'a> {
    fn new(
        py: Python<'a>,
        py_shared_state: &'a PySharedState,
    ) -> BorrowPyShared<'a> {
        py_shared_state.increase_borrow_count(py);
        BorrowPyShared {
            py,
            py_shared_state,
        }
    }
}

impl Drop for BorrowPyShared<'_> {
    fn drop(&mut self) {
        self.py_shared_state.decrease_borrow_count(self.py);
    }
}

/// `RefCell` wrapper to be safely used in conjunction with `PySharedState`.
///
/// This object can be stored in a `py_class!` object as a data field. Any
/// operation is allowed through the `PySharedRef` interface.
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

    fn borrow<'a>(&'a self, _py: Python<'a>) -> Ref<'a, T> {
        // py_shared_state isn't involved since
        // - inner.borrow() would fail if self is mutably borrowed,
        // - and inner.try_borrow_mut() would fail while self is borrowed.
        self.inner.borrow()
    }

    fn try_borrow_mut<'a>(
        &'a self,
        py: Python<'a>,
    ) -> PyResult<RefMut<'a, T>> {
        if self.py_shared_state.current_borrow_count(py) > 0 {
            return Err(AlreadyBorrowed::new(
                py,
                "Cannot borrow mutably while immutably borrowed",
            ));
        }
        let inner_ref = self
            .inner
            .try_borrow_mut()
            .map_err(|e| AlreadyBorrowed::new(py, e.to_string()))?;
        self.py_shared_state.increment_generation(py);
        Ok(inner_ref)
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
        self.data.borrow(self.py)
    }

    /// Mutably borrows the wrapped value.
    ///
    /// # Panics
    ///
    /// Panics if the value is currently borrowed through `PySharedRef`
    /// or `PyLeaked`.
    pub fn borrow_mut(&self) -> RefMut<'a, T> {
        self.try_borrow_mut().expect("already borrowed")
    }

    /// Mutably borrows the wrapped value, returning an error if the value
    /// is currently borrowed.
    pub fn try_borrow_mut(&self) -> PyResult<RefMut<'a, T>> {
        self.data.try_borrow_mut(self.py)
    }

    /// Returns a leaked reference.
    ///
    /// # Panics
    ///
    /// Panics if this is mutably borrowed.
    pub fn leak_immutable(&self) -> PyLeaked<&'static T> {
        let state = &self.data.py_shared_state;
        // make sure self.data isn't mutably borrowed; otherwise the
        // generation number can't be trusted.
        let data_ref = self.borrow();
        unsafe {
            let (static_ref, static_state_ref) =
                state.leak_immutable(self.py, data_ref);
            PyLeaked::new(self.py, self.owner, static_ref, static_state_ref)
        }
    }
}

/// Allows a `py_class!` generated struct to share references to one of its
/// data members with Python.
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
///
/// This reference will be invalidated once the original value is mutably
/// borrowed.
pub struct PyLeaked<T> {
    inner: PyObject,
    data: T,
    py_shared_state: &'static PySharedState,
    /// Generation counter of data `T` captured when PyLeaked is created.
    generation: usize,
}

// DO NOT implement Deref for PyLeaked<T>! Dereferencing PyLeaked
// without taking Python GIL wouldn't be safe. Also, the underling reference
// is invalid if generation != py_shared_state.generation.

impl<T> PyLeaked<T> {
    /// # Safety
    ///
    /// The `py_shared_state` must be owned by the `inner` Python object.
    fn new(
        py: Python,
        inner: &PyObject,
        data: T,
        py_shared_state: &'static PySharedState,
    ) -> Self {
        Self {
            inner: inner.clone_ref(py),
            data: data,
            py_shared_state,
            generation: py_shared_state.current_generation(py),
        }
    }

    /// Immutably borrows the wrapped value.
    ///
    /// Borrowing fails if the underlying reference has been invalidated.
    pub fn try_borrow<'a>(
        &'a self,
        py: Python<'a>,
    ) -> PyResult<PyLeakedRef<'a, T>> {
        self.validate_generation(py)?;
        Ok(PyLeakedRef {
            _borrow: BorrowPyShared::new(py, self.py_shared_state),
            data: &self.data,
        })
    }

    /// Mutably borrows the wrapped value.
    ///
    /// Borrowing fails if the underlying reference has been invalidated.
    ///
    /// Typically `T` is an iterator. If `T` is an immutable reference,
    /// `get_mut()` is useless since the inner value can't be mutated.
    pub fn try_borrow_mut<'a>(
        &'a mut self,
        py: Python<'a>,
    ) -> PyResult<PyLeakedRefMut<'a, T>> {
        self.validate_generation(py)?;
        Ok(PyLeakedRefMut {
            _borrow: BorrowPyShared::new(py, self.py_shared_state),
            data: &mut self.data,
        })
    }

    /// Converts the inner value by the given function.
    ///
    /// Typically `T` is a static reference to a container, and `U` is an
    /// iterator of that container.
    ///
    /// # Panics
    ///
    /// Panics if the underlying reference has been invalidated.
    ///
    /// This is typically called immediately after the `PyLeaked` is obtained.
    /// In which case, the reference must be valid and no panic would occur.
    ///
    /// # Safety
    ///
    /// The lifetime of the object passed in to the function `f` is cheated.
    /// It's typically a static reference, but is valid only while the
    /// corresponding `PyLeaked` is alive. Do not copy it out of the
    /// function call.
    pub unsafe fn map<U>(
        self,
        py: Python,
        f: impl FnOnce(T) -> U,
    ) -> PyLeaked<U> {
        // Needs to test the generation value to make sure self.data reference
        // is still intact.
        self.validate_generation(py)
            .expect("map() over invalidated leaked reference");

        // f() could make the self.data outlive. That's why map() is unsafe.
        // In order to make this function safe, maybe we'll need a way to
        // temporarily restrict the lifetime of self.data and translate the
        // returned object back to Something<'static>.
        let new_data = f(self.data);
        PyLeaked {
            inner: self.inner,
            data: new_data,
            py_shared_state: self.py_shared_state,
            generation: self.generation,
        }
    }

    fn validate_generation(&self, py: Python) -> PyResult<()> {
        if self.py_shared_state.current_generation(py) == self.generation {
            Ok(())
        } else {
            Err(PyErr::new::<exc::RuntimeError, _>(
                py,
                "Cannot access to leaked reference after mutation",
            ))
        }
    }
}

/// Immutably borrowed reference to a leaked value.
pub struct PyLeakedRef<'a, T> {
    _borrow: BorrowPyShared<'a>,
    data: &'a T,
}

impl<T> Deref for PyLeakedRef<'_, T> {
    type Target = T;

    fn deref(&self) -> &T {
        self.data
    }
}

/// Mutably borrowed reference to a leaked value.
pub struct PyLeakedRefMut<'a, T> {
    _borrow: BorrowPyShared<'a>,
    data: &'a mut T,
}

impl<T> Deref for PyLeakedRefMut<'_, T> {
    type Target = T;

    fn deref(&self) -> &T {
        self.data
    }
}

impl<T> DerefMut for PyLeakedRefMut<'_, T> {
    fn deref_mut(&mut self) -> &mut T {
        self.data
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
///         let leaked_ref = self.inner_shared(py).leak_immutable();
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
///     PyLeaked<HashMap<'static, Vec<u8>, Vec<u8>>>,
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
            data inner: RefCell<$leaked>;

            def __next__(&self) -> PyResult<$success_type> {
                let mut leaked = self.inner(py).borrow_mut();
                let mut iter = leaked.try_borrow_mut(py)?;
                match iter.next() {
                    None => Ok(None),
                    Some(res) => $success_func(py, res),
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
                    RefCell::new(leaked),
                )
            }
        }
    };
}

#[cfg(test)]
#[cfg(any(feature = "python27-bin", feature = "python3-bin"))]
mod test {
    use super::*;
    use cpython::{GILGuard, Python};

    py_class!(class Owner |py| {
        data string: PySharedRefCell<String>;
    });
    py_shared_ref!(Owner, String, string, string_shared);

    fn prepare_env() -> (GILGuard, Owner) {
        let gil = Python::acquire_gil();
        let py = gil.python();
        let owner =
            Owner::create_instance(py, PySharedRefCell::new("new".to_owned()))
                .unwrap();
        (gil, owner)
    }

    #[test]
    fn test_leaked_borrow() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        let leaked = owner.string_shared(py).leak_immutable();
        let leaked_ref = leaked.try_borrow(py).unwrap();
        assert_eq!(*leaked_ref, "new");
    }

    #[test]
    fn test_leaked_borrow_mut() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        let leaked = owner.string_shared(py).leak_immutable();
        let mut leaked_iter = unsafe { leaked.map(py, |s| s.chars()) };
        let mut leaked_ref = leaked_iter.try_borrow_mut(py).unwrap();
        assert_eq!(leaked_ref.next(), Some('n'));
        assert_eq!(leaked_ref.next(), Some('e'));
        assert_eq!(leaked_ref.next(), Some('w'));
        assert_eq!(leaked_ref.next(), None);
    }

    #[test]
    fn test_leaked_borrow_after_mut() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        let leaked = owner.string_shared(py).leak_immutable();
        owner.string_shared(py).borrow_mut().clear();
        assert!(leaked.try_borrow(py).is_err());
    }

    #[test]
    fn test_leaked_borrow_mut_after_mut() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        let leaked = owner.string_shared(py).leak_immutable();
        let mut leaked_iter = unsafe { leaked.map(py, |s| s.chars()) };
        owner.string_shared(py).borrow_mut().clear();
        assert!(leaked_iter.try_borrow_mut(py).is_err());
    }

    #[test]
    #[should_panic(expected = "map() over invalidated leaked reference")]
    fn test_leaked_map_after_mut() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        let leaked = owner.string_shared(py).leak_immutable();
        owner.string_shared(py).borrow_mut().clear();
        let _leaked_iter = unsafe { leaked.map(py, |s| s.chars()) };
    }

    #[test]
    fn test_try_borrow_mut_while_leaked_ref() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        assert!(owner.string_shared(py).try_borrow_mut().is_ok());
        let leaked = owner.string_shared(py).leak_immutable();
        {
            let _leaked_ref = leaked.try_borrow(py).unwrap();
            assert!(owner.string_shared(py).try_borrow_mut().is_err());
            {
                let _leaked_ref2 = leaked.try_borrow(py).unwrap();
                assert!(owner.string_shared(py).try_borrow_mut().is_err());
            }
            assert!(owner.string_shared(py).try_borrow_mut().is_err());
        }
        assert!(owner.string_shared(py).try_borrow_mut().is_ok());
    }

    #[test]
    fn test_try_borrow_mut_while_leaked_ref_mut() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        assert!(owner.string_shared(py).try_borrow_mut().is_ok());
        let leaked = owner.string_shared(py).leak_immutable();
        let mut leaked_iter = unsafe { leaked.map(py, |s| s.chars()) };
        {
            let _leaked_ref = leaked_iter.try_borrow_mut(py).unwrap();
            assert!(owner.string_shared(py).try_borrow_mut().is_err());
        }
        assert!(owner.string_shared(py).try_borrow_mut().is_ok());
    }

    #[test]
    #[should_panic(expected = "mutably borrowed")]
    fn test_leak_while_borrow_mut() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        let _mut_ref = owner.string_shared(py).borrow_mut();
        owner.string_shared(py).leak_immutable();
    }

    #[test]
    fn test_try_borrow_mut_while_borrow() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        let _ref = owner.string_shared(py).borrow();
        assert!(owner.string_shared(py).try_borrow_mut().is_err());
    }

    #[test]
    #[should_panic(expected = "already borrowed")]
    fn test_borrow_mut_while_borrow() {
        let (gil, owner) = prepare_env();
        let py = gil.python();
        let _ref = owner.string_shared(py).borrow();
        owner.string_shared(py).borrow_mut();
    }
}

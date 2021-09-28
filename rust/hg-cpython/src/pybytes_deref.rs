use cpython::{PyBytes, Python};
use stable_deref_trait::StableDeref;

/// Safe abstraction over a `PyBytes` together with the `&[u8]` slice
/// that borrows it. Implements `Deref<Target = [u8]>`.
///
/// Calling `PyBytes::data` requires a GIL marker but we want to access the
/// data in a thread that (ideally) does not need to acquire the GIL.
/// This type allows separating the call an the use.
///
/// It also enables using a (wrapped) `PyBytes` in GIL-unaware generic code.
pub struct PyBytesDeref {
    #[allow(unused)]
    keep_alive: PyBytes,

    /// Borrows the buffer inside `self.keep_alive`,
    /// but the borrow-checker cannot express self-referential structs.
    data: *const [u8],
}

impl PyBytesDeref {
    pub fn new(py: Python, bytes: PyBytes) -> Self {
        Self {
            data: bytes.data(py),
            keep_alive: bytes,
        }
    }

    pub fn unwrap(self) -> PyBytes {
        self.keep_alive
    }
}

impl std::ops::Deref for PyBytesDeref {
    type Target = [u8];

    fn deref(&self) -> &[u8] {
        // Safety: the raw pointer is valid as long as the PyBytes is still
        // alive, and the returned slice borrows `self`.
        unsafe { &*self.data }
    }
}

unsafe impl StableDeref for PyBytesDeref {}

fn require_send<T: Send>() {}

#[allow(unused)]
fn static_assert_pybytes_is_send() {
    require_send::<PyBytes>;
}

// Safety: PyBytes is Send. Raw pointers are not by default,
// but here sending one to another thread is fine since we ensure it stays
// valid.
unsafe impl Send for PyBytesDeref {}

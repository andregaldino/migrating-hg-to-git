use cpython::exc::ValueError;
use cpython::{PyErr, Python};
use hg;

py_exception!(rustext, GraphError, ValueError);

impl GraphError {
    pub fn pynew(py: Python, inner: hg::GraphError) -> PyErr {
        match inner {
            hg::GraphError::ParentOutOfRange(r) => {
                GraphError::new(py, ("ParentOutOfRange", r))
            }
        }
    }
}

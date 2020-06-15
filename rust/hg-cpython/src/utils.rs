use cpython::exc::ValueError;
use cpython::{PyBytes, PyDict, PyErr, PyObject, PyResult, PyTuple, Python};
use hg::revlog::Node;
use std::convert::TryFrom;

#[allow(unused)]
pub fn print_python_trace(py: Python) -> PyResult<PyObject> {
    eprintln!("===============================");
    eprintln!("Printing Python stack from Rust");
    eprintln!("===============================");
    let traceback = py.import("traceback")?;
    let sys = py.import("sys")?;
    let kwargs = PyDict::new(py);
    kwargs.set_item(py, "file", sys.get(py, "stderr")?)?;
    traceback.call(py, "print_stack", PyTuple::new(py, &[]), Some(&kwargs))
}

// Necessary evil for the time being, could maybe be moved to
// a TryFrom in Node itself
const NODE_BYTES_LENGTH: usize = 20;
type NodeData = [u8; NODE_BYTES_LENGTH];

/// Copy incoming Python bytes given as `PyObject` into `Node`,
/// doing the necessary checks
pub fn node_from_py_object<'a>(
    py: Python,
    bytes: &'a PyObject,
) -> PyResult<Node> {
    let as_py_bytes: &'a PyBytes = bytes.extract(py)?;
    node_from_py_bytes(py, as_py_bytes)
}

/// Clone incoming Python bytes given as `PyBytes` as a `Node`,
/// doing the necessary checks.
pub fn node_from_py_bytes(py: Python, bytes: &PyBytes) -> PyResult<Node> {
    <NodeData>::try_from(bytes.data(py))
        .map_err(|_| {
            PyErr::new::<ValueError, _>(
                py,
                format!("{}-byte hash required", NODE_BYTES_LENGTH),
            )
        })
        .map(Into::into)
}

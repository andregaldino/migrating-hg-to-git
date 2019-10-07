use cpython::{PyDict, PyObject, PyResult, PyTuple, Python};

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

use cpython::ObjectProtocol;
use cpython::PyBytes;
use cpython::PyDict;
use cpython::PyList;
use cpython::PyModule;
use cpython::PyObject;
use cpython::PyResult;
use cpython::PyTuple;
use cpython::Python;

use hg::copy_tracing::combine_changeset_copies;
use hg::copy_tracing::ChangedFiles;
use hg::copy_tracing::DataHolder;
use hg::copy_tracing::RevInfo;
use hg::copy_tracing::RevInfoMaker;
use hg::Revision;

/// Combines copies information contained into revision `revs` to build a copy
/// map.
///
/// See mercurial/copies.py for details
pub fn combine_changeset_copies_wrapper(
    py: Python,
    revs: PyList,
    children_count: PyDict,
    target_rev: Revision,
    rev_info: PyObject,
) -> PyResult<PyDict> {
    let revs: PyResult<_> =
        revs.iter(py).map(|r| Ok(r.extract(py)?)).collect();

    // Wrap the `rev_info_maker` python callback as a Rust closure
    //
    // No errors are expected from the Python side, and they will should only
    // happens in case of programing error or severe data corruption. Such
    // errors will raise panic and the rust-cpython harness will turn them into
    // Python exception.
    let rev_info_maker: RevInfoMaker<PyBytes> =
        Box::new(|rev: Revision, d: &mut DataHolder<PyBytes>| -> RevInfo {
            let res: PyTuple = rev_info
                .call(py, (rev,), None)
                .expect("rust-copy-tracing: python call to `rev_info` failed")
                .cast_into(py)
                .expect(
                    "rust-copy_tracing: python call to `rev_info` returned \
                    unexpected non-Tuple value",
                );
            let p1 = res.get_item(py, 0).extract(py).expect(
                "rust-copy-tracing: rev_info return is invalid, first item \
                is a not a revision",
            );
            let p2 = res.get_item(py, 1).extract(py).expect(
                "rust-copy-tracing: rev_info return is invalid, first item \
                is a not a revision",
            );

            let files = match res.get_item(py, 2).extract::<PyBytes>(py) {
                Ok(raw) => {
                    // Give responsability for the raw bytes lifetime to
                    // hg-core
                    d.data = Some(raw);
                    let addrs = d.data.as_ref().expect(
                        "rust-copy-tracing: failed to get a reference to the \
                        raw bytes for copy data").data(py);
                    ChangedFiles::new(addrs)
                }
                // value was presumably None, meaning they was no copy data.
                Err(_) => ChangedFiles::new_empty(),
            };

            (p1, p2, files)
        });
    let children_count: PyResult<_> = children_count
        .items(py)
        .iter()
        .map(|(k, v)| Ok((k.extract(py)?, v.extract(py)?)))
        .collect();

    let res = combine_changeset_copies(
        revs?,
        children_count?,
        target_rev,
        rev_info_maker,
    );
    let out = PyDict::new(py);
    for (dest, source) in res.into_iter() {
        out.set_item(
            py,
            PyBytes::new(py, &dest.into_vec()),
            PyBytes::new(py, &source.into_vec()),
        )?;
    }
    Ok(out)
}

/// Create the module, with `__package__` given from parent
pub fn init_module(py: Python, package: &str) -> PyResult<PyModule> {
    let dotted_name = &format!("{}.copy_tracing", package);
    let m = PyModule::new(py, dotted_name)?;

    m.add(py, "__package__", package)?;
    m.add(py, "__doc__", "Copy tracing - Rust implementation")?;

    m.add(
        py,
        "combine_changeset_copies",
        py_fn!(
            py,
            combine_changeset_copies_wrapper(
                revs: PyList,
                children: PyDict,
                target_rev: Revision,
                rev_info: PyObject
            )
        ),
    )?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;

    Ok(m)
}

use cpython::ObjectProtocol;
use cpython::PyBool;
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
use hg::copy_tracing::RevInfo;
use hg::utils::hg_path::HgPathBuf;
use hg::Revision;

/// Combines copies information contained into revision `revs` to build a copy
/// map.
///
/// See mercurial/copies.py for details
pub fn combine_changeset_copies_wrapper(
    py: Python,
    revs: PyList,
    children: PyDict,
    target_rev: Revision,
    rev_info: PyObject,
    is_ancestor: PyObject,
) -> PyResult<PyDict> {
    let revs: PyResult<_> =
        revs.iter(py).map(|r| Ok(r.extract(py)?)).collect();

    // Wrap the `is_ancestor` python callback as a Rust closure
    //
    // No errors are expected from the Python side, and they will should only
    // happens in case of programing error or severe data corruption. Such
    // errors will raise panic and the rust-cpython harness will turn them into
    // Python exception.
    let is_ancestor_wrap = |anc: Revision, desc: Revision| -> bool {
        is_ancestor
            .call(py, (anc, desc), None)
            .expect(
                "rust-copy-tracing: python call  to `is_ancestor` \
                failed",
            )
            .cast_into::<PyBool>(py)
            .expect(
                "rust-copy-tracing: python call  to `is_ancestor` \
                returned unexpected non-Bool value",
            )
            .is_true()
    };

    // Wrap the `rev_info_maker` python callback as a Rust closure
    //
    // No errors are expected from the Python side, and they will should only
    // happens in case of programing error or severe data corruption. Such
    // errors will raise panic and the rust-cpython harness will turn them into
    // Python exception.
    let rev_info_maker = |rev: Revision| -> RevInfo {
        let res: PyTuple = rev_info
            .call(py, (rev,), None)
            .expect("rust-copy-tracing: python call to `rev_info` failed")
            .cast_into(py)
            .expect(
                "rust-copy_tracing: python call to `rev_info` returned \
                unexpected non-Tuple value",
            );
        let p1 = res.get_item(py, 0).extract(py).expect(
            "rust-copy-tracing: \
            rev_info return is invalid, first item is a not a revision",
        );
        let p2 = res.get_item(py, 1).extract(py).expect(
            "rust-copy-tracing: \
            rev_info return is invalid, second item is a not a revision",
        );

        let changes = res.get_item(py, 2);

        let files;
        if !changes
            .hasattr(py, "copied_from_p1")
            .expect("rust-copy-tracing: python call to `hasattr` failed")
        {
            files = ChangedFiles::new_empty();
        } else {
            let p1_copies: PyDict = changes
                .getattr(py, "copied_from_p1")
                .expect(
                    "rust-copy-tracing: retrieval of python attribute \
                    `copied_from_p1` failed",
                )
                .cast_into(py)
                .expect(
                    "rust-copy-tracing: failed to convert `copied_from_p1` \
                    to PyDict",
                );
            let p1_copies: PyResult<_> = p1_copies
                .items(py)
                .iter()
                .map(|(key, value)| {
                    let key = key.extract::<PyBytes>(py).expect(
                        "rust-copy-tracing: conversion of copy destination to\
                        PyBytes failed",
                    );
                    let key = key.data(py);
                    let value = value.extract::<PyBytes>(py).expect(
                        "rust-copy-tracing: conversion of copy source to \
                        PyBytes failed",
                    );
                    let value = value.data(py);
                    Ok((
                        HgPathBuf::from_bytes(key),
                        HgPathBuf::from_bytes(value),
                    ))
                })
                .collect();

            let p2_copies: PyDict = changes
                .getattr(py, "copied_from_p2")
                .expect(
                    "rust-copy-tracing: retrieval of python attribute \
                    `copied_from_p2` failed",
                )
                .cast_into(py)
                .expect(
                    "rust-copy-tracing: failed to convert `copied_from_p2` \
                    to PyDict",
                );
            let p2_copies: PyResult<_> = p2_copies
                .items(py)
                .iter()
                .map(|(key, value)| {
                    let key = key.extract::<PyBytes>(py).expect(
                        "rust-copy-tracing: conversion of copy destination to \
                        PyBytes failed");
                    let key = key.data(py);
                    let value = value.extract::<PyBytes>(py).expect(
                        "rust-copy-tracing: conversion of copy source to \
                        PyBytes failed",
                    );
                    let value = value.data(py);
                    Ok((
                        HgPathBuf::from_bytes(key),
                        HgPathBuf::from_bytes(value),
                    ))
                })
                .collect();

            let removed: PyObject = changes.getattr(py, "removed").expect(
                "rust-copy-tracing: retrieval of python attribute \
                    `removed` failed",
            );
            let removed: PyResult<_> = removed
                .iter(py)
                .expect(
                    "rust-copy-tracing: getting a python iterator over the \
                    `removed` set failed",
                )
                .map(|filename| {
                    let filename = filename
                        .expect(
                            "rust-copy-tracing: python iteration over the \
                            `removed` set failed",
                        )
                        .extract::<PyBytes>(py)
                        .expect(
                            "rust-copy-tracing: \
                            conversion of `removed` item to PyBytes failed",
                        );
                    let filename = filename.data(py);
                    Ok(HgPathBuf::from_bytes(filename))
                })
                .collect();

            let merged: PyObject = changes.getattr(py, "merged").expect(
                "rust-copy-tracing: retrieval of python attribute \
                    `merged` failed",
            );
            let merged: PyResult<_> = merged
                .iter(py)
                .expect(
                    "rust-copy-tracing: getting a python iterator over the \
                    `merged` set failed",
                )
                .map(|filename| {
                    let filename = filename
                        .expect(
                            "rust-copy-tracing: python iteration over the \
                            `merged` set failed",
                        )
                        .extract::<PyBytes>(py)
                        .expect(
                            "rust-copy-tracing: \
                            conversion of `merged` item to PyBytes failed",
                        );
                    let filename = filename.data(py);
                    Ok(HgPathBuf::from_bytes(filename))
                })
                .collect();

            let salvaged: PyObject = changes.getattr(py, "salvaged").expect(
                "rust-copy-tracing: retrieval of python attribute \
                    `salvaged` failed",
            );
            let salvaged: PyResult<_> = salvaged
                .iter(py)
                .expect(
                    "rust-copy-tracing: getting a python iterator over the \
                    `salvaged` set failed",
                )
                .map(|filename| {
                    let filename = filename
                        .expect(
                            "rust-copy-tracing: python iteration over the \
                            `salvaged` set failed",
                        )
                        .extract::<PyBytes>(py)
                        .expect(
                            "rust-copy-tracing: \
                            conversion of `salvaged` item to PyBytes failed",
                        );
                    let filename = filename.data(py);
                    Ok(HgPathBuf::from_bytes(filename))
                })
                .collect();
            files = ChangedFiles::new(
                removed.unwrap(),
                merged.unwrap(),
                salvaged.unwrap(),
                p1_copies.unwrap(),
                p2_copies.unwrap(),
            );
        }

        (p1, p2, files)
    };
    let children: PyResult<_> = children
        .items(py)
        .iter()
        .map(|(k, v)| {
            let v: &PyList = v.cast_as(py)?;
            let v: PyResult<_> =
                v.iter(py).map(|child| Ok(child.extract(py)?)).collect();
            Ok((k.extract(py)?, v?))
        })
        .collect();

    let res = combine_changeset_copies(
        revs?,
        children?,
        target_rev,
        &rev_info_maker,
        &is_ancestor_wrap,
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
                rev_info: PyObject,
                is_ancestor: PyObject
            )
        ),
    )?;

    let sys = PyModule::import(py, "sys")?;
    let sys_modules: PyDict = sys.get(py, "modules")?.extract(py)?;
    sys_modules.set_item(py, dotted_name, &m)?;

    Ok(m)
}

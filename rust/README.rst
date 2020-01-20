===================
Mercurial Rust Code
===================

This directory contains various Rust code for the Mercurial project.
Rust is not required to use (or build) Mercurial, but using it
improves performance in some areas.

There are currently three independent rust projects:
- chg. An implementation of chg, in rust instead of C.
- hgcli. A experiment for starting hg in rust rather than in python,
  by linking with the python runtime. Probably meant to be replaced by
  PyOxidizer at some point.
- hg-core (and hg-cpython/hg-directffi): implementation of some
  functionality of mercurial in rust, e.g. ancestry computations in
  revision graphs or pull discovery. The top-level ``Cargo.toml`` file
  defines a workspace containing these crates.

Using hg-core
=============

Local use (you need to clean previous build artifacts if you have
built without rust previously)::

  $ HGWITHRUSTEXT=cpython make local # to use ./hg
  $ HGWITHRUSTEXT=cpython make tests # to run all tests
  $ (cd tests; HGWITHRUSTEXT=cpython ./run-tests.py) # only the .t
  $ ./hg debuginstall | grep rust # to validate rust is in use
  checking module policy (rust+c-allow)

Setting ``HGWITHRUSTEXT`` to other values like ``true`` is deprecated
and enables only a fraction of the rust code.

Developing hg-core
==================

Simply run::

   $ cargo build --release

It is possible to build without ``--release``, but it is not
recommended if performance is of any interest: there can be an order
of magnitude of degradation when removing ``--release``.

For faster builds, you may want to skip code generation::

  $ cargo check

You can run only the rust-specific tests (as opposed to tests of
mercurial as a whole) with::

  $ cargo test --all

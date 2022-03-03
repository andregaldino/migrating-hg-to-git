===================
Mercurial Rust Code
===================

This directory contains various Rust code for the Mercurial project.
Rust is not required to use (or build) Mercurial, but using it
improves performance in some areas.

There are currently four independent Rust projects:
- chg. An implementation of chg, in Rust instead of C.
- hgcli. A project that provides a (mostly) self-contained "hg" binary,
  for ease of deployment and a bit of speed, using PyOxidizer. See
  hgcli/README.md.
- hg-core (and hg-cpython): implementation of some
  functionality of mercurial in Rust, e.g. ancestry computations in
  revision graphs, status or pull discovery. The top-level ``Cargo.toml`` file
  defines a workspace containing these crates.
- rhg: a pure Rust implementation of Mercurial, with a fallback mechanism for
  unsupported invocations. It reuses the logic `hg-core` but completely forgoes
  interaction with Python. See `rust/rhg/README.md` for more details.

Using Rust code
===============

Local use (you need to clean previous build artifacts if you have
built without rust previously)::

  $ make PURE=--rust local # to use ./hg
  $ ./tests/run-tests.py --rust # to run all tests
  $ ./hg debuginstall | grep -i rust # to validate rust is in use
  checking Rust extensions (installed)
  checking module policy (rust+c-allow)

If the environment variable ``HGWITHRUSTEXT=cpython`` is set, the Rust
extension will be used by default unless ``--no-rust``.

One day we may use this environment variable to switch to new experimental
binding crates like a hypothetical ``HGWITHRUSTEXT=hpy``.

Special features
================

In the future, compile-time opt-ins may be added
to the `features` section in ``hg-cpython/Cargo.toml``.

To use features from the Makefile, use the `HG_RUST_FEATURES` environment
variable: for instance `HG_RUST_FEATURES="some-feature other-feature"`

Profiling
=========

Setting the environment variable ``RUST_LOG=trace`` will make hg print
a few high level rust-related performance numbers. It can also
indicate why the rust code cannot be used (say, using lookarounds in
hgignore).

Creating a ``.cargo/config`` file with the following content enables
debug information in optimized builds. This make profiles more informative
with source file name and line number for Rust stack frames and
(in some cases) stack frames for Rust functions that have been inlined.

  [profile.release]
  debug = true

``py-spy`` (https://github.com/benfred/py-spy) can be used to
construct a single profile with rust functions and python functions
(as opposed to ``hg --profile``, which attributes time spent in rust
to some unlucky python code running shortly after the rust code, and
as opposed to tools for native code like ``perf``, which attribute
time to the python interpreter instead of python functions).

Example usage:

  $ make PURE=--rust local # Don't forget to recompile after a code change
  $ py-spy record --native --output /tmp/profile.svg -- ./hg ...

Developing Rust
===============

The current version of Rust in use is ``1.48.0``, because it's what Debian
stable has. You can use ``rustup override set 1.48.0`` at the root of the repo
to make it easier on you.

Go to the ``hg-cpython`` folder::

  $ cd rust/hg-cpython

Or, only the ``hg-core`` folder. Be careful not to break compatibility::

  $ cd rust/hg-core

Simply run::

   $ cargo build --release

It is possible to build without ``--release``, but it is not
recommended if performance is of any interest: there can be an order
of magnitude of degradation when removing ``--release``.

For faster builds, you may want to skip code generation::

  $ cargo check

For even faster typing::

  $ cargo c

You can run only the rust-specific tests (as opposed to tests of
mercurial as a whole) with::

  $ cargo test --all

Formatting the code
-------------------

We use ``rustfmt`` to keep the code formatted at all times. For now, we are
using the nightly version because it has been stable enough and provides
comment folding.

To format the entire Rust workspace::

  $ cargo +nightly fmt

This requires you to have the nightly toolchain installed.

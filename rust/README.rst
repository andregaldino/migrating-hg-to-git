===================
Mercurial Rust Code
===================

This directory contains various Rust code for the Mercurial project.
Rust is not required to use (or build) Mercurial, but using it
improves performance in some areas.

There are currently three independent rust projects:
- chg. An implementation of chg, in rust instead of C.
- hgcli. A project that provide a (mostly) self-contained "hg" binary,
  for ease of deployment and a bit of speed, using PyOxidizer. See
  hgcli/README.md.
- hg-core (and hg-cpython): implementation of some
  functionality of mercurial in rust, e.g. ancestry computations in
  revision graphs, status or pull discovery. The top-level ``Cargo.toml`` file
  defines a workspace containing these crates.

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

Profiling
=========

Setting the environment variable ``RUST_LOG=trace`` will make hg print
a few high level rust-related performance numbers. It can also
indicate why the rust code cannot be used (say, using lookarounds in
hgignore).

``py-spy`` (https://github.com/benfred/py-spy) can be used to
construct a single profile with rust functions and python functions
(as opposed to ``hg --profile``, which attributes time spent in rust
to some unlucky python code running shortly after the rust code, and
as opposed to tools for native code like ``perf``, which attribute
time to the python interpreter instead of python functions).

Developing Rust
===============

The current version of Rust in use is ``1.34.2``, because it's what Debian
stable has. You can use ``rustup override set 1.34.2`` at the root of the repo
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

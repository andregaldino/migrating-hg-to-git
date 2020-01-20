===================
Mercurial Rust Code
===================

This directory contains various Rust code for the Mercurial project.

The top-level ``Cargo.toml`` file defines a workspace containing
all primary Mercurial crates.

Building
========

To build the Rust components::

   $ cargo build

If you prefer a non-debug / release configuration::

   $ cargo build --release

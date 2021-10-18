# Oxidized Mercurial

This project provides a Rust implementation of the Mercurial (`hg`)
version control tool.

Under the hood, the project uses
[PyOxidizer](https://github.com/indygreg/PyOxidizer) to embed a Python
interpreter in a binary built with Rust. At run-time, the Rust `fn main()`
is called and Rust code handles initial process startup. An in-process
Python interpreter is started (if needed) to provide additional
functionality.

# Building

First, acquire and build a copy of PyOxidizer; you probably want to do this in
some directory outside of your clone of Mercurial:

    $ git clone https://github.com/indygreg/PyOxidizer.git
    $ cd PyOxidizer
    $ cargo build --release

Then build this Rust project using the built `pyoxidizer` executable:

    $ /path/to/pyoxidizer/target/release/pyoxidizer build --release

If all goes according to plan, there should be an assembled application
under `build/<arch>/release/app/` with an `hg` executable:

    $ build/x86_64-unknown-linux-gnu/release/app/hg version
    Mercurial Distributed SCM (version 5.3.1+433-f99cd77d53dc+20200331)
    (see https://mercurial-scm.org for more information)

    Copyright (C) 2005-2020 Olivia Mackall and others
    This is free software; see the source for copying conditions. There is NO
    warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# Running Tests

To run tests with a built `hg` executable, you can use the `--with-hg`
argument to `run-tests.py`. But there's a wrinkle: many tests run custom
Python scripts that need to `import` modules provided by Mercurial. Since
these modules are embedded in the produced `hg` executable, a regular
Python interpreter can't access them! To work around this, set `PYTHONPATH`
to the Mercurial source directory. e.g.:

    $ cd /path/to/hg/src/tests
    $ PYTHONPATH=`pwd`/.. python3.9 run-tests.py \
        --with-hg `pwd`/../rust/hgcli/build/x86_64-unknown-linux-gnu/release/app/hg

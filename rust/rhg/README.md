# `rhg`

The `rhg` executable implements a subset of the functionnality of `hg`
using only Rust, to avoid the startup cost of a Python interpreter.
This subset is initially small but grows over time as `rhg` is improved.
When fallback to the Python implementation is configured (see below),
`rhg` aims to be a drop-in replacement for `hg` that should behave the same,
except that some commands run faster.


## Building

To compile `rhg`, either run `cargo build --release` from this `rust/rhg/`
directory, or run `make build-rhg` from the repository root.
The executable can then be found at `rust/target/release/rhg`.


## Mercurial configuration

`rhg` reads Mercurial configuration from the usual sources:
the user’s `~/.hgrc`, a repository’s `.hg/hgrc`, command line `--config`, etc.
It has some specific configuration in the `[rhg]` section:

* `on-unsupported` governs the behavior of `rhg` when it encounters something
  that it does not support but “full” `hg` possibly does.
  This can be in configuration, on the command line, or in a repository.

  - `abort`, the default value, makes `rhg` print a message to stderr
    to explain what is not supported, then terminate with a 252 exit code.
  - `abort-silent` makes it terminate with the same exit code,
    but without printing anything.
  - `fallback` makes it silently call a (presumably Python-based) `hg`
    subprocess with the same command-line parameters.
    The `rhg.fallback-executable` configuration must be set.

* `fallback-executable`: path to the executable to run in a sub-process
  when falling back to a Python implementation of Mercurial.

* `allowed-extensions`: a list of extension names that `rhg` can ignore.

  Mercurial extensions can modify the behavior of existing `hg` sub-commands,
  including those that `rhg` otherwise supports.
  Because it cannot load Python extensions, finding them
  enabled in configuration is considered “unsupported” (see above).
  A few exceptions are made for extensions that `rhg` does know about,
  with the Rust implementation duplicating their behavior.

  This configuration makes additional exceptions: `rhg` will proceed even if
  those extensions are enabled.


## Installation and configuration example

For example, to install `rhg` as `hg` for the current user with fallback to
the system-wide install of Mercurial, and allow it to run even though the
`rebase` and `absorb` extensions are enabled, on a Unix-like platform:

* Build `rhg` (see above)
* Make sure the `~/.local/bin` exists and is in `$PATH`
* From the repository root, make a symbolic link with
  `ln -s rust/target/release/rhg ~/.local/bin/hg`
* Configure `~/.hgrc` with:

```
[rhg]
on-unsupported = fallback
fallback-executable = /usr/bin/hg
allowed-extensions = rebase, absorb
```

* Check that the output of running
  `hg notarealsubcommand`
  starts with `hg: unknown command`, which indicates fallback.

* Check that the output of running
  `hg notarealsubcommand --config rhg.on-unsupported=abort`
  starts with `unsupported feature:`.

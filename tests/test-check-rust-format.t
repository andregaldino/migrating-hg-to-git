#require rustfmt test-repo

  $ . "$TESTDIR/helpers-testrepo.sh"

  $ cd "$TESTDIR"/..
  $ RUSTFMT=$(rustup which --toolchain nightly rustfmt)
  $ for f in `testrepohg files 'glob:**/*.rs'` ; do
  >   $RUSTFMT --check --edition=2018 --unstable-features --color=never $f
  > done

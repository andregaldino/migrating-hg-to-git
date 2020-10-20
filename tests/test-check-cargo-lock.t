#require cargo test-repo
  $ . "$TESTDIR/helpers-testrepo.sh"
  $ cd "$TESTDIR"/../rust

Check if Cargo.lock is up-to-date. Will fail with a 101 error code if not.

  $ cargo check --locked --all --quiet

However most CIs will run `cargo build` or similar before running the tests, so we need to check if it was modified

  $ testrepohg diff Cargo.lock

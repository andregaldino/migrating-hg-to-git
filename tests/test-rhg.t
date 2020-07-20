#require rust

  $ rhg() {
  > if [ -f "$RUNTESTDIR/../rust/target/debug/rhg" ]; then
  >   "$RUNTESTDIR/../rust/target/debug/rhg" "$@"
  > else
  >   echo "skipped: Cannot find rhg. Try to run cargo build in rust/rhg."
  >   exit 80
  > fi
  > }
  $ rhg unimplemented-command
  [252]
  $ rhg root
  abort: no repository found in '$TESTTMP' (.hg not found)!
  [255]
  $ hg init repository
  $ cd repository
  $ rhg root
  $TESTTMP/repository
  $ rhg root > /dev/full
  abort: No space left on device (os error 28)
  [255]
  $ rm -rf `pwd`
  $ rhg root
  abort: error getting current working directory: $ENOENT$
  [255]

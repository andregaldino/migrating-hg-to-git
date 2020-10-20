#require rust

Define an rhg function that will only run if rhg exists
  $ rhg() {
  > if [ -f "$RUNTESTDIR/../rust/target/debug/rhg" ]; then
  >   "$RUNTESTDIR/../rust/target/debug/rhg" "$@"
  > else
  >   echo "skipped: Cannot find rhg. Try to run cargo build in rust/rhg."
  >   exit 80
  > fi
  > }

Unimplemented command
  $ rhg unimplemented-command
  error: Found argument 'unimplemented-command' which wasn't expected, or isn't valid in this context
  
  USAGE:
      rhg <SUBCOMMAND>
  
  For more information try --help
  [252]

Finding root
  $ rhg root
  abort: no repository found in '$TESTTMP' (.hg not found)!
  [255]

  $ hg init repository
  $ cd repository
  $ rhg root
  $TESTTMP/repository

Unwritable file descriptor
  $ rhg root > /dev/full
  abort: No space left on device (os error 28)
  [255]

Deleted repository
  $ rm -rf `pwd`
  $ rhg root
  abort: error getting current working directory: $ENOENT$
  [255]

Listing tracked files
  $ cd $TESTTMP
  $ hg init repository
  $ cd repository
  $ for i in 1 2 3; do
  >   echo $i >> file$i
  >   hg add file$i
  > done
  > hg commit -m "commit $i" -q

Listing tracked files from root
  $ rhg files
  file1
  file2
  file3

Listing tracked files from subdirectory
  $ mkdir -p path/to/directory
  $ cd path/to/directory
  $ rhg files
  ../../../file1
  ../../../file2
  ../../../file3

Listing tracked files through broken pipe
  $ rhg files | head -n 1
  ../../../file1

Debuging data in inline index
  $ cd $TESTTMP
  $ rm -rf repository
  $ hg init repository
  $ cd repository
  $ for i in 1 2 3; do
  >   echo $i >> file$i
  >   hg add file$i
  >   hg commit -m "commit $i" -q
  > done
  $ rhg debugdata -c 2
  e36fa63d37a576b27a69057598351db6ee5746bd
  test
  0 0
  file3
  
  commit 3 (no-eol)
  $ rhg debugdata -m 2
  file1\x00b8e02f6433738021a065f94175c7cd23db5f05be (esc)
  file2\x005d9299349fc01ddd25d0070d149b124d8f10411e (esc)
  file3\x002661d26c649684b482d10f91960cc3db683c38b4 (esc)

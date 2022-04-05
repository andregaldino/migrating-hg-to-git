#require curses
#testcases committed wdir

Revert interactive tests with the Curses interface

  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interactive = true
  > interface = curses
  > [experimental]
  > crecordtest = testModeCommands
  > EOF

TODO: Make a curses version of the other tests from test-revert-interactive.t.

#if committed
  $ maybe_commit() {
  >   hg ci "$@"
  > }
  $ do_revert() {
  >   hg revert -ir'.^'
  > }
#else
  $ maybe_commit() {
  >   true
  > }
  $ do_revert() {
  >   hg revert -i
  > }
#endif

When a line without EOL is selected during "revert -i"

  $ hg init $TESTTMP/revert-i-curses-eol
  $ cd $TESTTMP/revert-i-curses-eol
  $ echo 0 > a
  $ hg ci -qAm 0
  $ printf 1 >> a
  $ maybe_commit -qAm 1
  $ cat a
  0
  1 (no-eol)

  $ cat <<EOF >testModeCommands
  > c
  > EOF

  $ do_revert
  reverting a
  $ cat a
  0

When a selected line is reverted to have no EOL

  $ hg init $TESTTMP/revert-i-curses-eol2
  $ cd $TESTTMP/revert-i-curses-eol2
  $ printf 0 > a
  $ hg ci -qAm 0
  $ echo 0 > a
  $ maybe_commit -qAm 1
  $ cat a
  0

  $ cat <<EOF >testModeCommands
  > c
  > EOF

  $ do_revert
  reverting a
  $ cat a
  0 (no-eol)


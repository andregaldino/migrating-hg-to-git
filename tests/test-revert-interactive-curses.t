#require tic

Revert interactive tests with the Curses interface

  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interactive = true
  > interface = curses
  > [experimental]
  > crecordtest = testModeCommands
  > EOF

TODO: Make a curses version of the other tests from test-revert-interactive.t.

When a line without EOL is selected during "revert -i"

  $ hg init $TESTTMP/revert-i-curses-eol
  $ cd $TESTTMP/revert-i-curses-eol
  $ echo 0 > a
  $ hg ci -qAm 0
  $ printf 1 >> a
  $ hg ci -qAm 1
  $ cat a
  0
  1 (no-eol)

  $ cat <<EOF >testModeCommands
  > c
  > EOF

  $ hg revert -ir'.^'
  reverting a
  $ cat a
  0

When a selected line is reverted to have no EOL

  $ hg init $TESTTMP/revert-i-curses-eol2
  $ cd $TESTTMP/revert-i-curses-eol2
  $ printf 0 > a
  $ hg ci -qAm 0
  $ echo 0 > a
  $ hg ci -qAm 1
  $ cat a
  0

  $ cat <<EOF >testModeCommands
  > c
  > EOF

  $ hg revert -ir'.^'
  reverting a
  $ cat a
  0 (no-eol)


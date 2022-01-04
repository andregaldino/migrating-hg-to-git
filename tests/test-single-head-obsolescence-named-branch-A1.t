=========================================
Testing single head enforcement: Case A-1
=========================================

A repository is set to only accept a single head per name (typically named
branch). However, obsolete changesets can make this enforcement more
complicated, because they can be kept visible by other changeset on other
branch.

This case is part of a series of tests checking this behavior.

Category A: Involving obsolescence
TestCase 1: A fully obsolete branch kept visible by another one

.. old-state:
..
.. * 2 changesets on branch default
.. * 2 changesets on branch Z on top of them
..
.. new-state:
..
.. * 2 changesets on branch Z at the same location
.. * 2 changesets on branch default superseding the other ones
..
.. expected-result:
..
.. * only one head detected
..
.. graph-summary:
..
..   D ●      (branch Z)
..     |
..   C ●      (branch Z)
..     |
..   B ø⇠◔ B'
..     | |
..   A ø⇠◔ A'
..     |/
..     ●

  $ . $TESTDIR/testlib/push-checkheads-util.sh

  $ cat >> $HGRCPATH << EOF
  > [command-templates]
  > log = "{node|short} [{branch}] ({phase}): {desc}\n"
  > EOF

Test setup
----------

  $ mkdir A1
  $ cd A1
  $ setuprepos single-head
  creating basic server and client repo
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd client
  $ mkcommit B0
  $ hg branch Z
  marked working directory as branch Z
  (branches are permanent and global, did you want a bookmark?)
  $ mkcommit C0
  $ mkcommit D0
  $ hg push --new-branch
  pushing to $TESTTMP/A1/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  $ hg up 0
  0 files updated, 0 files merged, 4 files removed, 0 files unresolved
  $ mkcommit A1
  created new head
  $ mkcommit B1
  $ hg debugobsolete `getid "desc(A0)"` `getid "desc(A1)"`
  1 new obsolescence markers
  obsoleted 1 changesets
  3 new orphan changesets
  $ hg debugobsolete `getid "desc(B0)"` `getid "desc(B1)"`
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg heads
  262c8c798096 [default] (draft): B1
  cdf1dbb37a67 [Z] (draft): D0
  $ hg log -G --hidden
  @  262c8c798096 [default] (draft): B1
  |
  o  f6082bc4ffef [default] (draft): A1
  |
  | *  cdf1dbb37a67 [Z] (draft): D0
  | |
  | *  3213e3e16c67 [Z] (draft): C0
  | |
  | x  d73caddc5533 [default] (draft): B0
  | |
  | x  8aaa48160adc [default] (draft): A0
  |/
  o  1e4be0697311 [default] (public): root
  

Actual testing
--------------

  $ hg push -r 'desc("B1")'
  pushing to $TESTTMP/A1/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files (+1 heads)
  2 new obsolescence markers
  obsoleted 2 changesets
  2 new orphan changesets

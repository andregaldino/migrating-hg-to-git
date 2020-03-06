====================================
Testing head checking code: Case E-1
====================================

Mercurial checks for the introduction of new heads on push. Evolution comes
into play to detect if existing branches on the server are being replaced by
some of the new one we push.

This case is part of a series of tests checking this behavior.

Category E: case involving changeset on multiple branch
TestCase 8: moving a branch to another location

.. old-state:
..
.. * 1-changeset on branch default
.. * 1-changeset on branch Z (above default)
..
.. new-state:
..
.. * 1-changeset on branch default
.. * 1-changeset on branch Z (rebased away from A0)
..
.. expected-result:
..
.. * push allowed
..
.. graph-summary:
..
..   B ø⇠◔ B'
..     | |
..   A ◔ |
..     |/
..     ●

  $ . $TESTDIR/testlib/push-checkheads-util.sh

Test setup
----------

  $ mkdir E1
  $ cd E1
  $ setuprepos
  creating basic server and client repo
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd client
  $ hg branch Z
  marked working directory as branch Z
  (branches are permanent and global, did you want a bookmark?)
  $ mkcommit B0
  $ hg push --new-branch
  pushing to $TESTTMP/E1/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  $ hg up 0
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg branch --force Z
  marked working directory as branch Z
  $ mkcommit B1
  created new head
  $ hg debugobsolete `getid "desc(B0)" ` `getid "desc(B1)"`
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg log -G --hidden
  @  c98b855401e7 (draft): B1
  |
  | x  93e5c1321ece (draft): B0
  | |
  | o  8aaa48160adc (draft): A0
  |/
  o  1e4be0697311 (public): root
  

Actual testing
--------------

  $ hg push
  pushing to $TESTTMP/E1/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)
  1 new obsolescence markers
  obsoleted 1 changesets

  $ cd ../..

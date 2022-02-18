=========================================
Testing single head enforcement: Case A-2
=========================================

A repository is set to only accept a single head per name (typically named
branch). However, obsolete changesets can make this enforcement more
complicated, because they can be kept visible by other changeset on other
branch.

This case is part of a series of tests checking this behavior.

Category A: Involving obsolescence
TestCase 2: A branch is split in two, effectively creating two heads

.. old-state:
..
.. * 2 changesets on branch default
.. * 2 changesets on branch Z on top of them
..
.. new-state:
..
.. * 2 changesets on branch Z at the same location
.. * 1 changeset on branch default unchanged
.. * 1 changeset on branch default superseding the other ones
..
.. expected-result:
..
.. * two heads detected
..
.. graph-summary:
..
..   D ●      (branch Z)
..     |
..   C ●      (branch Z)
..     |
..   B ø⇠◔ B'
..     | |
..   A ● |
..     |/
..     ●

  $ . $TESTDIR/testlib/push-checkheads-util.sh

  $ cat >> $HGRCPATH << EOF
  > [command-templates]
  > log = "{node|short} [{branch}] ({phase}): {desc}\n"
  > EOF

Test setup
----------

  $ mkdir A2
  $ cd A2
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
  pushing to $TESTTMP/A2/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  $ hg up 0
  0 files updated, 0 files merged, 4 files removed, 0 files unresolved
  $ mkcommit B1
  created new head
  $ hg debugobsolete `getid "desc(B0)"` `getid "desc(B1)"`
  1 new obsolescence markers
  obsoleted 1 changesets
  2 new orphan changesets
  $ hg heads
  25c56d33e4c4 [default] (draft): B1
  cdf1dbb37a67 [Z] (draft): D0
  8aaa48160adc [default] (draft): A0
  $ hg log -G --hidden
  @  25c56d33e4c4 [default] (draft): B1
  |
  | *  cdf1dbb37a67 [Z] (draft): D0
  | |
  | *  3213e3e16c67 [Z] (draft): C0
  | |
  | x  d73caddc5533 [default] (draft): B0
  | |
  | o  8aaa48160adc [default] (draft): A0
  |/
  o  1e4be0697311 [default] (public): root
  

Actual testing
--------------

(force push to make sure we get the changeset on the remote)

  $ hg push -r 'desc("B1")' --force
  pushing to $TESTTMP/A2/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  transaction abort!
  rollback completed
  abort: rejecting multiple heads on branch "default"
  (2 heads: 8aaa48160adc 25c56d33e4c4)
  [255]

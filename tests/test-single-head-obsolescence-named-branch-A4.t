=========================================
Testing single head enforcement: Case A-4
=========================================

A repository is set to only accept a single head per name (typically named
branch). However, obsolete changesets can make this enforcement more
complicated, because they can be kept visible by other changeset on other
branch.

This case is part of a series of tests checking this behavior.

Category A: Involving obsolescence
TestCase 4: Partial rewrite of a branch to deinterleave it

.. old-state:
..
.. * 2 changesets on branch default
.. * 2 changesets on branch Z interleaved with the other one
..
.. new-state:
..
.. * 2 changesets on branch Z at the same location
.. * 1 changeset on default untouched (the lower one)
.. * 1 changeset on default moved on the other one
..
.. expected-result:
..
.. * only one head detected
..
.. graph-summary:
..
..   D ●      (branch Z)
..     |
..   C ø⇠◔ C'
..     | |
..   B ● |    (branch Z)
..     |/
..   A ●
..     |
..     ●

  $ . $TESTDIR/testlib/push-checkheads-util.sh

  $ cat >> $HGRCPATH << EOF
  > [command-templates]
  > log = "{node|short} [{branch}] ({phase}): {desc}\n"
  > EOF

Test setup
----------

  $ mkdir A4
  $ cd A4
  $ setuprepos single-head
  creating basic server and client repo
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd client
  $ hg branch Z
  marked working directory as branch Z
  (branches are permanent and global, did you want a bookmark?)
  $ mkcommit B0
  $ hg branch default --force
  marked working directory as branch default
  $ mkcommit C0
  created new head
  $ hg branch Z --force
  marked working directory as branch Z
  $ mkcommit D0
  created new head
  $ hg push --new-branch
  pushing to $TESTTMP/A4/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  $ hg up 'desc("A0")'
  0 files updated, 0 files merged, 3 files removed, 0 files unresolved
  $ mkcommit C1
  created new head
  $ hg debugobsolete `getid "desc(C0)"` `getid "desc(C1)"`
  1 new obsolescence markers
  obsoleted 1 changesets
  1 new orphan changesets
  $ hg heads
  cfe9ed94fa4a [default] (draft): C1
  78578c4306ce [Z] (draft): D0
  $ hg log -G --hidden
  @  cfe9ed94fa4a [default] (draft): C1
  |
  | *  78578c4306ce [Z] (draft): D0
  | |
  | x  afc55ba2ce61 [default] (draft): C0
  | |
  | o  93e5c1321ece [Z] (draft): B0
  |/
  o  8aaa48160adc [default] (draft): A0
  |
  o  1e4be0697311 [default] (public): root
  

Actual testing
--------------

(force push to make sure we get the changeset on the remote)

  $ hg push -r 'desc("C1")' --force
  pushing to $TESTTMP/A4/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)
  1 new obsolescence markers
  obsoleted 1 changesets
  1 new orphan changesets

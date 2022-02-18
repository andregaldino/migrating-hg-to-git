=========================================
Testing single head enforcement: Case A-3
=========================================

A repository is set to only accept a single head per name (typically named
branch). However, obsolete changesets can make this enforcement more
complicated, because they can be kept visible by other changeset on other
branch.

This case is part of a series of tests checking this behavior.

Category A: Involving obsolescence
TestCase 3: Full superseding of a branch interleaved with another

.. old-state:
..
.. * 2 changesets on branch default
.. * 2 changesets on branch Z interleaved with the other
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
..   C ø⇠◔ C'
..     | |
..   B ● |    (branch Z)
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

  $ mkdir A3
  $ cd A3
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
  pushing to $TESTTMP/A3/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  $ hg up 0
  0 files updated, 0 files merged, 4 files removed, 0 files unresolved
  $ mkcommit A1
  created new head
  $ mkcommit C1
  $ hg debugobsolete `getid "desc(A0)"` `getid "desc(A1)"`
  1 new obsolescence markers
  obsoleted 1 changesets
  3 new orphan changesets
  $ hg debugobsolete `getid "desc(C0)"` `getid "desc(C1)"`
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg heads
  0c76bc104656 [default] (draft): C1
  78578c4306ce [Z] (draft): D0
  $ hg log -G --hidden
  @  0c76bc104656 [default] (draft): C1
  |
  o  f6082bc4ffef [default] (draft): A1
  |
  | *  78578c4306ce [Z] (draft): D0
  | |
  | x  afc55ba2ce61 [default] (draft): C0
  | |
  | *  93e5c1321ece [Z] (draft): B0
  | |
  | x  8aaa48160adc [default] (draft): A0
  |/
  o  1e4be0697311 [default] (public): root
  

Actual testing
--------------

  $ hg push -r 'desc("C1")'
  pushing to $TESTTMP/A3/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files (+1 heads)
  2 new obsolescence markers
  obsoleted 2 changesets
  2 new orphan changesets

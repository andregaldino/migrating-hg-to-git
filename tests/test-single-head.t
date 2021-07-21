=====================
Test workflow options
=====================

  $ . "$TESTDIR/testlib/obsmarker-common.sh"

Test single head enforcing - Setup
=============================================

  $ cat << EOF >> $HGRCPATH
  > [experimental]
  > evolution = all
  > EOF
  $ hg init single-head-server
  $ cd single-head-server
  $ cat <<EOF >> .hg/hgrc
  > [phases]
  > publish = no
  > [experimental]
  > single-head-per-branch = yes
  > EOF
  $ mkcommit ROOT
  $ mkcommit c_dA0
  $ cd ..

  $ hg clone single-head-server client
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

Test single head enforcing - with branch only
---------------------------------------------

  $ cd client

continuing the current defaultbranch

  $ mkcommit c_dB0
  $ hg push
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files

creating a new branch

  $ hg up 'desc("ROOT")'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg branch branch_A
  marked working directory as branch branch_A
  (branches are permanent and global, did you want a bookmark?)
  $ mkcommit c_aC0
  $ hg push --new-branch
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)

Create a new head on the default branch

  $ hg up 'desc("c_dA0")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ mkcommit c_dD0
  created new head
  $ hg log -r 'heads(::branch("default"))' -T '{node|short}\n'
  286d02a6e2a2
  9bf953aa81f6
  $ hg push -f
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  transaction abort!
  rollback completed
  abort: rejecting multiple heads on branch "default"
  (2 heads: 286d02a6e2a2 9bf953aa81f6)
  [255]

remerge them

  $ hg merge
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ mkcommit c_dE0
  $ hg push
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files

Test single head enforcing - after rewrite
------------------------------------------

  $ mkcommit c_dF0
  $ hg push
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  $ hg commit --amend -m c_dF1
  $ hg push
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 1 files (+1 heads)
  1 new obsolescence markers
  obsoleted 1 changesets

Check it does not interfer with strip
-------------------------------------

setup

  $ hg branch branch_A --force
  marked working directory as branch branch_A
  $ mkcommit c_aG0
  created new head
  $ hg update 'desc("c_dF1")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ mkcommit c_dH0
  $ hg update 'desc("c_aG0")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ mkcommit c_aI0
  $ hg log -G
  @    changeset:   10:49003e504178
  |\   branch:      branch_A
  | |  tag:         tip
  | |  parent:      8:a33fb808fb4b
  | |  parent:      3:840af1c6bc88
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     c_aI0
  | |
  | | o  changeset:   9:fe47ea669cea
  | | |  parent:      7:99a2dc242c5d
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  summary:     c_dH0
  | | |
  | o |  changeset:   8:a33fb808fb4b
  | |/   branch:      branch_A
  | |    user:        test
  | |    date:        Thu Jan 01 00:00:00 1970 +0000
  | |    summary:     c_aG0
  | |
  | o  changeset:   7:99a2dc242c5d
  | |  parent:      5:6ed1df20edb1
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     c_dF1
  | |
  | o    changeset:   5:6ed1df20edb1
  | |\   parent:      4:9bf953aa81f6
  | | |  parent:      2:286d02a6e2a2
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  summary:     c_dE0
  | | |
  | | o  changeset:   4:9bf953aa81f6
  | | |  parent:      1:134bc3852ad2
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  summary:     c_dD0
  | | |
  o | |  changeset:   3:840af1c6bc88
  | | |  branch:      branch_A
  | | |  parent:      0:ea207398892e
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  summary:     c_aC0
  | | |
  | o |  changeset:   2:286d02a6e2a2
  | |/   user:        test
  | |    date:        Thu Jan 01 00:00:00 1970 +0000
  | |    summary:     c_dB0
  | |
  | o  changeset:   1:134bc3852ad2
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     c_dA0
  |
  o  changeset:   0:ea207398892e
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     ROOT
  

actual stripping

  $ hg strip --config extensions.strip= --rev 'desc("c_dH0")'
  saved backup bundle to $TESTTMP/client/.hg/strip-backup/fe47ea669cea-a41bf5a9-backup.hg

Test that closing heads are ignored by default
-----------------------------------------------

  $ hg up 'desc("c_aG0")'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ mkcommit c_aJ0
  created new head

pushing the new head should fails

  $ hg push -f
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  transaction abort!
  rollback completed
  abort: rejecting multiple heads on branch "branch_A"
  (2 heads: 49003e504178 468bd81ccc5d)
  [255]


closing the head and pushing should succeed

  $ mkcommit c_aK0 --close-branch
  $ hg push -f
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 4 changes to 4 files (-1 heads)


Test that closing heads can be explicitly accounted for
-------------------------------------------------------

  $ cat <<EOF >> $TESTTMP/single-head-server/.hg/hgrc
  > [experimental]
  > single-head-per-branch:account-closed-heads = yes
  > EOF

  $ hg up 'desc("c_aG0")'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ mkcommit c_aL0
  created new head
  $ mkcommit c_aM0 --close-branch
  $ hg push -f
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  transaction abort!
  rollback completed
  abort: rejecting multiple heads on branch "branch_A"
  (3 heads: 49003e504178 5254bcccab93 42b9fe70a3c1)
  [255]


Test that config can be overriden as the boolean it is
------------------------------------------------------

  $ cat <<EOF >> $TESTTMP/single-head-server/.hg/hgrc
  > [experimental]
  > single-head-per-branch = no
  > EOF

Because of previous test, we'll also push c_aL0 and c_aM0.

  $ hg out -T "{desc}\n"
  comparing with $TESTTMP/single-head-server
  searching for changes
  c_aL0
  c_aM0

Let's make a new head and push everything. The server feedback will mention
exactly one new head because c_aM0 is closed.

  $ hg up 'desc("c_aG0")'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ mkcommit c_aN0
  created new head
  $ hg push -f
  pushing to $TESTTMP/single-head-server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files (+1 heads)
  $ cd ..


Test that singe-head-per-branch can be restricted to public changes
-------------------------------------------------------------------

  $ hg clone -r 49003e504178 single-head-server public-only
  adding changesets
  adding manifests
  adding file changes
  added 9 changesets with 9 changes to 9 files
  1 new obsolescence markers
  new changesets ea207398892e:49003e504178 (9 drafts)
  updating to branch branch_A
  9 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd public-only
  $ cat <<EOF >> .hg/hgrc
  > [phases]
  > publish = no
  > [experimental]
  > single-head-per-branch = yes
  > single-head-per-branch:public-changes-only = yes
  > EOF
  > hg phase -p :
  $ hg update 'desc("c_aG0")'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ mkcommit c_dO0
  created new head
  $ hg log -G
  @  changeset:   9:8058fd35cc2b
  |  branch:      branch_A
  |  tag:         tip
  |  parent:      7:a33fb808fb4b
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     c_dO0
  |
  | o  changeset:   8:49003e504178
  |/|  branch:      branch_A
  | |  parent:      7:a33fb808fb4b
  | |  parent:      3:840af1c6bc88
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     c_aI0
  | |
  o |  changeset:   7:a33fb808fb4b
  | |  branch:      branch_A
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     c_aG0
  | |
  o |  changeset:   6:99a2dc242c5d
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     c_dF1
  | |
  o |    changeset:   5:6ed1df20edb1
  |\ \   parent:      4:9bf953aa81f6
  | | |  parent:      2:286d02a6e2a2
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  summary:     c_dE0
  | | |
  | o |  changeset:   4:9bf953aa81f6
  | | |  parent:      1:134bc3852ad2
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  summary:     c_dD0
  | | |
  | | o  changeset:   3:840af1c6bc88
  | | |  branch:      branch_A
  | | |  parent:      0:ea207398892e
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  summary:     c_aC0
  | | |
  o | |  changeset:   2:286d02a6e2a2
  |/ /   user:        test
  | |    date:        Thu Jan 01 00:00:00 1970 +0000
  | |    summary:     c_dB0
  | |
  o |  changeset:   1:134bc3852ad2
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     c_dA0
  |
  o  changeset:   0:ea207398892e
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     ROOT
  
  $ hg phase -p .
  abort: rejecting multiple heads on branch "branch_A"
  (2 heads: 49003e504178 8058fd35cc2b)
  [255]

===========================
Tests for sidedata exchange
===========================

Check simple exchange behavior
==============================

Pusher and pushed have sidedata enabled
---------------------------------------

  $ hg init sidedata-source --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> sidedata-source/.hg/hgrc
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata-5.py
  > EOF
  $ hg init sidedata-target --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> sidedata-target/.hg/hgrc
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata-5.py
  > EOF
  $ cd sidedata-source
  $ echo a > a
  $ echo b > b
  $ echo c > c
  $ hg commit -Am "initial"
  adding a
  adding b
  adding c
  $ echo aa > a
  $ hg commit -m "other"
  $ hg push -r . ../sidedata-target
  pushing to ../sidedata-target
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 4 changes to 3 files
  $ hg -R ../sidedata-target debugsidedata -c 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg -R ../sidedata-target debugsidedata -c 1 -v
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x00:'
   entry-0002 size 32
    '\xa3\xee4v\x99\x85$\x9f\x1f\x8dKe\x0f\xc3\x9d-\xc9\xb5%[\x15=h\xe9\xf2O\xb5\xd9\x1f*\xff\xe5'
  $ hg -R ../sidedata-target debugsidedata -m 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg -R ../sidedata-target debugsidedata -m 1 -v
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x00\x81'
   entry-0002 size 32
    '-bL\xc5\xa4uu"#\xac\x1b`,\xc0\xbc\x9d\xf5\xac\xf0\x1d\x89)2\xf8N\xb1\x14m\xce\xd7\xbc\xae'
  $ hg -R ../sidedata-target debugsidedata a 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg -R ../sidedata-target debugsidedata a 1 -v
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x00\x03'
   entry-0002 size 32
    '\xd9\xcd\x81UvL5C\xf1\x0f\xad\x8aH\rt17Fo\x8dU!<\x8e\xae\xfc\xd1/\x06\xd4:\x80'
  $ cd ..

Puller and pulled have sidedata enabled
---------------------------------------

  $ rm -rf sidedata-source sidedata-target
  $ hg init sidedata-source --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> sidedata-source/.hg/hgrc
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata-5.py
  > EOF
  $ hg init sidedata-target --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> sidedata-target/.hg/hgrc
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata-5.py
  > EOF
  $ cd sidedata-source
  $ echo a > a
  $ echo b > b
  $ echo c > c
  $ hg commit -Am "initial"
  adding a
  adding b
  adding c
  $ echo aa > a
  $ hg commit -m "other"
  $ hg pull -R ../sidedata-target ../sidedata-source
  pulling from ../sidedata-source
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 4 changes to 3 files
  new changesets 05da661850d7:7ec8b4049447
  (run 'hg update' to get a working copy)
  $ hg -R ../sidedata-target debugsidedata -c 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg -R ../sidedata-target debugsidedata -c 1 -v
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x00:'
   entry-0002 size 32
    '\xa3\xee4v\x99\x85$\x9f\x1f\x8dKe\x0f\xc3\x9d-\xc9\xb5%[\x15=h\xe9\xf2O\xb5\xd9\x1f*\xff\xe5'
  $ hg -R ../sidedata-target debugsidedata -m 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg -R ../sidedata-target debugsidedata -m 1 -v
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x00\x81'
   entry-0002 size 32
    '-bL\xc5\xa4uu"#\xac\x1b`,\xc0\xbc\x9d\xf5\xac\xf0\x1d\x89)2\xf8N\xb1\x14m\xce\xd7\xbc\xae'
  $ hg -R ../sidedata-target debugsidedata a 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg -R ../sidedata-target debugsidedata a 1 -v
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x00\x03'
   entry-0002 size 32
    '\xd9\xcd\x81UvL5C\xf1\x0f\xad\x8aH\rt17Fo\x8dU!<\x8e\xae\xfc\xd1/\x06\xd4:\x80'
  $ cd ..

Now on to asymmetric configs.

Pusher has sidedata enabled, pushed does not
--------------------------------------------

  $ rm -rf sidedata-source sidedata-target
  $ hg init sidedata-source --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> sidedata-source/.hg/hgrc
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata-5.py
  > EOF
  $ hg init sidedata-target --config experimental.revlogv2=no
  $ cd sidedata-source
  $ echo a > a
  $ echo b > b
  $ echo c > c
  $ hg commit -Am "initial"
  adding a
  adding b
  adding c
  $ echo aa > a
  $ hg commit -m "other"
  $ hg push -r . ../sidedata-target --traceback
  pushing to ../sidedata-target
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 4 changes to 3 files
  $ hg -R ../sidedata-target log -G
  o  changeset:   1:7ec8b4049447
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     other
  |
  o  changeset:   0:05da661850d7
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     initial
  

  $ hg -R ../sidedata-target debugsidedata -c 0
  $ hg -R ../sidedata-target debugsidedata -c 1 -v
  $ hg -R ../sidedata-target debugsidedata -m 0
  $ hg -R ../sidedata-target debugsidedata -m 1 -v
  $ hg -R ../sidedata-target debugsidedata a 0
  $ hg -R ../sidedata-target debugsidedata a 1 -v
  $ cd ..

Pulled has sidedata enabled, puller does not
--------------------------------------------

  $ rm -rf sidedata-source sidedata-target
  $ hg init sidedata-source --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> sidedata-source/.hg/hgrc
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata-5.py
  > EOF
  $ hg init sidedata-target --config experimental.revlogv2=no
  $ cd sidedata-source
  $ echo a > a
  $ echo b > b
  $ echo c > c
  $ hg commit -Am "initial"
  adding a
  adding b
  adding c
  $ echo aa > a
  $ hg commit -m "other"
  $ hg pull -R ../sidedata-target ../sidedata-source
  pulling from ../sidedata-source
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 4 changes to 3 files
  new changesets 05da661850d7:7ec8b4049447
  (run 'hg update' to get a working copy)
  $ hg -R ../sidedata-target log -G
  o  changeset:   1:7ec8b4049447
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     other
  |
  o  changeset:   0:05da661850d7
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     initial
  

  $ hg -R ../sidedata-target debugsidedata -c 0
  $ hg -R ../sidedata-target debugsidedata -c 1 -v
  $ hg -R ../sidedata-target debugsidedata -m 0
  $ hg -R ../sidedata-target debugsidedata -m 1 -v
  $ hg -R ../sidedata-target debugsidedata a 0
  $ hg -R ../sidedata-target debugsidedata a 1 -v
  $ cd ..


Check sidedata exchange with on-the-fly generation and removal
==============================================================

(Push) Target has strict superset of the source
-----------------------------------------------

  $ hg init source-repo --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ hg init target-repo --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> target-repo/.hg/hgrc
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata.py
  > EOF
  $ cd source-repo
  $ echo aaa > a
  $ hg add a
  $ hg commit -m a
  $ echo aaa > b
  $ hg add b
  $ hg commit -m b
  $ echo xxx >> a
  $ hg commit -m aa

No sidedata is generated in the source
  $ hg debugsidedata -c 0

Check that sidedata capabilities are advertised
  $ hg debugcapabilities ../target-repo | grep sidedata
    exp-wanted-sidedata=1,2

We expect the client to abort the push since it's not capable of generating
what the server is asking
  $ hg push -r . ../target-repo
  pushing to ../target-repo
  abort: cannot push: required sidedata category not supported by this client: '1'
  [255]

Add the required capabilities
  $ cat << EOF >> .hg/hgrc
  > [extensions]
  > testsidedata2=$TESTDIR/testlib/ext-sidedata-2.py
  > EOF

We expect the target to have sidedata that was generated by the source on push
  $ hg push -r . ../target-repo
  pushing to ../target-repo
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 2 files
  $ cd ../target-repo
  $ hg debugsidedata -c 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg debugsidedata -c 1 -v
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x006'
   entry-0002 size 32
    '\x98\t\xf9\xc4v\xf0\xc5P\x90\xf7wRf\xe8\xe27e\xfc\xc1\x93\xa4\x96\xd0\x1d\x97\xaaG\x1d\xd7t\xfa\xde'
  $ hg debugsidedata -m 2
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg debugsidedata a 1
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ cd ..

(Push) Difference is not subset/superset
----------------------------------------

Source has one in common, one missing and one more sidedata category with the
target.

  $ rm -rf source-repo target-repo
  $ hg init source-repo --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> source-repo/.hg/hgrc
  > [extensions]
  > testsidedata3=$TESTDIR/testlib/ext-sidedata-3.py
  > EOF
  $ hg init target-repo --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> target-repo/.hg/hgrc
  > [extensions]
  > testsidedata4=$TESTDIR/testlib/ext-sidedata-4.py
  > EOF
  $ cd source-repo
  $ echo aaa > a
  $ hg add a
  $ hg commit -m a
  $ echo aaa > b
  $ hg add b
  $ hg commit -m b
  $ echo xxx >> a
  $ hg commit -m aa

Check that sidedata capabilities are advertised
  $ hg debugcapabilities . | grep sidedata
    exp-wanted-sidedata=1,2
  $ hg debugcapabilities ../target-repo | grep sidedata
    exp-wanted-sidedata=2,3

Sidedata is generated in the source, but only the right categories (entry-0001 and entry-0002)
  $ hg debugsidedata -c 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg debugsidedata -c 1 -v
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x006'
   entry-0002 size 32
    '\x98\t\xf9\xc4v\xf0\xc5P\x90\xf7wRf\xe8\xe27e\xfc\xc1\x93\xa4\x96\xd0\x1d\x97\xaaG\x1d\xd7t\xfa\xde'
  $ hg debugsidedata -m 2
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg debugsidedata a 1
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32


We expect the target to have sidedata that was generated by the source on push,
and also removed the sidedata categories that are not supported by the target.
Namely, we expect entry-0002 (only exchanged) and entry-0003 (generated),
but not entry-0001.

  $ hg push -r . ../target-repo --traceback
  pushing to ../target-repo
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 2 files
  $ cd ../target-repo
  $ hg log -G
  o  changeset:   2:40f977031323
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     aa
  |
  o  changeset:   1:2707720c6597
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     b
  |
  o  changeset:   0:7049e48789d7
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     a
  
  $ hg debugsidedata -c 0
  2 sidedata entries
   entry-0002 size 32
   entry-0003 size 48
  $ hg debugsidedata -c 1 -v
  2 sidedata entries
   entry-0002 size 32
    '\x98\t\xf9\xc4v\xf0\xc5P\x90\xf7wRf\xe8\xe27e\xfc\xc1\x93\xa4\x96\xd0\x1d\x97\xaaG\x1d\xd7t\xfa\xde'
   entry-0003 size 48
    '\x87\xcf\xdfI/\xb5\xed\xeaC\xc1\xf0S\xf3X\x1c\xcc\x00m\xee\xe6#\xc1\xe3\xcaB8Fk\x82e\xfc\xc01\xf6\xb7\xb9\xb3([\xf6D\xa6\xcf\x9b\xea\x11{\x08'
  $ hg debugsidedata -m 2
  2 sidedata entries
   entry-0002 size 32
   entry-0003 size 48
  $ hg debugsidedata a 1
  2 sidedata entries
   entry-0002 size 32
   entry-0003 size 48
  $ cd ..

(Pull) Target has strict superset of the source
-----------------------------------------------

  $ rm -rf source-repo target-repo
  $ hg init source-repo --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ hg init target-repo --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ cat << EOF >> target-repo/.hg/hgrc
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata.py
  > EOF
  $ cd source-repo
  $ echo aaa > a
  $ hg add a
  $ hg commit -m a
  $ echo aaa > b
  $ hg add b
  $ hg commit -m b
  $ echo xxx >> a
  $ hg commit -m aa

No sidedata is generated in the source
  $ hg debugsidedata -c 0

Check that sidedata capabilities are advertised
  $ hg debugcapabilities ../target-repo | grep sidedata
    exp-wanted-sidedata=1,2

  $ cd ../target-repo

Add the required capabilities
  $ cat << EOF >> .hg/hgrc
  > [extensions]
  > testsidedata2=$TESTDIR/testlib/ext-sidedata-2.py
  > EOF

We expect the target to have sidedata that it generated on-the-fly during pull
  $ hg pull -r . ../source-repo  --traceback
  pulling from ../source-repo
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 2 files
  new changesets 7049e48789d7:40f977031323
  (run 'hg update' to get a working copy)
  $ hg debugsidedata -c 0 --traceback
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg debugsidedata -c 1 -v --traceback
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x006'
   entry-0002 size 32
    '\x98\t\xf9\xc4v\xf0\xc5P\x90\xf7wRf\xe8\xe27e\xfc\xc1\x93\xa4\x96\xd0\x1d\x97\xaaG\x1d\xd7t\xfa\xde'
  $ hg debugsidedata -m 2
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg debugsidedata a 1
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ cd ..

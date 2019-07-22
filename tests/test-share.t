  $ echo "[extensions]"      >> $HGRCPATH
  $ echo "share = "          >> $HGRCPATH

prepare repo1

  $ hg init repo1
  $ cd repo1
  $ echo a > a
  $ hg commit -A -m'init'
  adding a

share it

  $ cd ..
  $ hg share repo1 repo2
  updating working directory
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

share shouldn't have a store dir

  $ cd repo2
  $ test -d .hg/store
  [1]
  $ hg root -Tjson | sed 's|\\\\|\\|g'
  [
   {
    "hgpath": "$TESTTMP/repo2/.hg",
    "reporoot": "$TESTTMP/repo2",
    "storepath": "$TESTTMP/repo1/.hg/store"
   }
  ]

share shouldn't have a full cache dir, original repo should

  $ hg branches
  default                        0:d3873e73d99e
  $ hg tags
  tip                                0:d3873e73d99e
  $ test -d .hg/cache
  [1]
  $ ls -1 .hg/wcache || true
  checkisexec (execbit !)
  checklink (symlink !)
  checklink-target (symlink !)
  manifestfulltextcache (reporevlogstore !)
  $ ls -1 ../repo1/.hg/cache
  branch2-served
  rbc-names-v1
  rbc-revs-v1
  tags2-visible

Some sed versions appends newline, some don't, and some just fails

  $ cat .hg/sharedpath; echo
  $TESTTMP/repo1/.hg

trailing newline on .hg/sharedpath is ok
  $ hg tip -q
  0:d3873e73d99e
  $ echo '' >> .hg/sharedpath
  $ cat .hg/sharedpath
  $TESTTMP/repo1/.hg
  $ hg tip -q
  0:d3873e73d99e

commit in shared clone

  $ echo a >> a
  $ hg commit -m'change in shared clone'

check original

  $ cd ../repo1
  $ hg log
  changeset:   1:8af4dc49db9e
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     change in shared clone
  
  changeset:   0:d3873e73d99e
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     init
  
  $ hg update
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cat a             # should be two lines of "a"
  a
  a

commit in original

  $ echo b > b
  $ hg commit -A -m'another file'
  adding b

check in shared clone

  $ cd ../repo2
  $ hg log
  changeset:   2:c2e0ac586386
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     another file
  
  changeset:   1:8af4dc49db9e
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     change in shared clone
  
  changeset:   0:d3873e73d99e
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     init
  
  $ hg update
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cat b             # should exist with one "b"
  b

hg serve shared clone

  $ hg serve -n test -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid >> $DAEMON_PIDS
  $ get-with-headers.py localhost:$HGPORT 'raw-file/'
  200 Script output follows
  
  
  -rw-r--r-- 4 a
  -rw-r--r-- 2 b
  
  
Cloning a shared repo via bundle2 results in a non-shared clone

  $ cd ..
  $ hg clone -q --stream --config ui.ssh="\"$PYTHON\" \"$TESTDIR/dummyssh\"" ssh://user@dummy/`pwd`/repo2 cloned-via-bundle2
  $ cat ./cloned-via-bundle2/.hg/requires | grep "shared"
  [1]
  $ hg id --cwd cloned-via-bundle2 -r tip
  c2e0ac586386 tip
  $ cd repo2

test unshare command

  $ hg unshare
  $ test -d .hg/store
  $ test -f .hg/sharedpath
  [1]
  $ grep shared .hg/requires
  [1]
  $ hg unshare
  abort: this is not a shared repo
  [255]

check that a change does not propagate

  $ echo b >> b
  $ hg commit -m'change in unshared'
  $ cd ../repo1
  $ hg id -r tip
  c2e0ac586386 tip

  $ cd ..


non largefiles repos won't enable largefiles

  $ hg share --config extensions.largefiles= repo2 sharedrepo
  The fsmonitor extension is incompatible with the largefiles extension and has been disabled. (fsmonitor !)
  The fsmonitor extension is incompatible with the largefiles extension and has been disabled. (fsmonitor !)
  updating working directory
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ [ -f sharedrepo/.hg/hgrc ]
  [1]

test shared clones using relative paths work

  $ mkdir thisdir
  $ hg init thisdir/orig
  $ hg share -U thisdir/orig thisdir/abs
  $ hg share -U --relative thisdir/abs thisdir/rel
  $ cat thisdir/rel/.hg/sharedpath
  ../../orig/.hg (no-eol)
  $ grep shared thisdir/*/.hg/requires
  thisdir/abs/.hg/requires:shared
  thisdir/rel/.hg/requires:relshared
  thisdir/rel/.hg/requires:shared

test that relative shared paths aren't relative to $PWD

  $ cd thisdir
  $ hg -R rel root
  $TESTTMP/thisdir/rel
  $ cd ..

now test that relative paths really are relative, survive across
renames and changes of PWD

  $ hg -R thisdir/abs root
  $TESTTMP/thisdir/abs
  $ hg -R thisdir/rel root
  $TESTTMP/thisdir/rel
  $ mv thisdir thatdir
  $ hg -R thatdir/abs root
  abort: .hg/sharedpath points to nonexistent directory $TESTTMP/thisdir/orig/.hg!
  [255]
  $ hg -R thatdir/rel root
  $TESTTMP/thatdir/rel

test unshare relshared repo

  $ cd thatdir/rel
  $ hg unshare
  $ test -d .hg/store
  $ test -f .hg/sharedpath
  [1]
  $ grep shared .hg/requires
  [1]
  $ hg unshare
  abort: this is not a shared repo
  [255]
  $ cd ../..

  $ rm -r thatdir

Demonstrate buggy behavior around requirements validation
See comment in localrepo.py:makelocalrepository() for more.

  $ hg init sharenewrequires
  $ hg share sharenewrequires shareoldrequires
  updating working directory
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cat >> sharenewrequires/.hg/requires << EOF
  > missing-requirement
  > EOF

We cannot open the repo with the unknown requirement

  $ hg -R sharenewrequires status
  abort: repository requires features unknown to this Mercurial: missing-requirement!
  (see https://mercurial-scm.org/wiki/MissingRequirement for more information)
  [255]

BUG: we don't get the same error when opening the shared repo pointing to it

  $ hg -R shareoldrequires status

Explicitly kill daemons to let the test exit on Windows

  $ killdaemons.py


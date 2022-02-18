#testcases safe normal

#if safe
  $ echo "[format]"         >> $HGRCPATH
  $ echo "use-share-safe = True" >> $HGRCPATH
#endif

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
  checklink (symlink no-rust !)
  checklink-target (symlink no-rust !)
  manifestfulltextcache (reporevlogstore !)
  $ ls -1 ../repo1/.hg/cache
  branch2-served
  rbc-names-v1
  rbc-revs-v1
  tags2-visible

Cloning a shared repo should pick up the full cache dir on the other hand.

  $ hg clone . ../repo2-clone
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ ls -1 ../repo2-clone/.hg/cache
  branch2-base
  branch2-immutable
  branch2-served
  branch2-served.hidden
  branch2-visible
  branch2-visible-hidden
  rbc-names-v1
  rbc-revs-v1
  tags2
  tags2-served
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
  $ hg clone -q --stream ssh://user@dummy/`pwd`/repo2 cloned-via-bundle2
  $ hg -R cloned-via-bundle2 debugrequires | grep "shared"
  [1]
  $ hg id --cwd cloned-via-bundle2 -r tip
  c2e0ac586386 tip
  $ cd repo2

test unshare command

  $ hg unshare
  $ test -d .hg/store
  $ test -f .hg/sharedpath
  [1]
  $ hg debugrequires | grep shared
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
  $ hg debugrequires -R thisdir/abs/ | grep shared
  shared
  $ hg debugrequires -R thisdir/rel/ | grep shared
  relshared
  shared

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
  abort: .hg/sharedpath points to nonexistent directory $TESTTMP/thisdir/orig/.hg
  [255]
  $ hg -R thatdir/rel root
  $TESTTMP/thatdir/rel

test unshare relshared repo

  $ cd thatdir/rel
  $ hg unshare
  $ test -d .hg/store
  $ test -f .hg/sharedpath
  [1]
  $ hg debugrequires | grep shared
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
  abort: repository requires features unknown to this Mercurial: missing-requirement
  (see https://mercurial-scm.org/wiki/MissingRequirement for more information)
  [255]

BUG: we don't get the same error when opening the shared repo pointing to it

  $ hg -R shareoldrequires status

Explicitly kill daemons to let the test exit on Windows

  $ killdaemons.py

Test sharing a repository which was created with store requirement disable

  $ hg init nostore --config format.usestore=false
  ignoring enabled 'format.use-share-safe' config because it is incompatible with disabled 'format.usestore' config (safe !)
  $ hg share nostore sharednostore
  abort: cannot create shared repository as source was created with 'format.usestore' config disabled
  [255]

Check that (safe) share can control wc-specific format variant at creation time
-------------------------------------------------------------------------------

#if no-rust

  $ cat << EOF >> $HGRCPATH
  > [storage]
  > dirstate-v2.slow-path = allow
  > EOF

#endif

  $ hg init repo-safe-d1 --config format.use-share-safe=yes --config format.exp-rc-dirstate-v2=no
  $ hg debugformat -R repo-safe-d1 | grep dirstate-v2
  dirstate-v2:         no

  $ hg share repo-safe-d1 share-safe-d2 --config format.use-share-safe=yes --config format.exp-rc-dirstate-v2=yes
  updating working directory
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugformat  -R share-safe-d2 | grep dirstate-v2
  dirstate-v2:        yes

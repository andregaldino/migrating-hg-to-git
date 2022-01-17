This file contains tests case that deal with format change accross stream clone

#require serve no-reposimplestore no-chg

#testcases stream-legacy

(the #stream-bundle2 variant is actually buggy for the moment)

#if stream-legacy
  $ cat << EOF >> $HGRCPATH
  > [server]
  > bundle2.stream = no
  > EOF
#endif

Initialize repository

  $ hg init server
  $ cd server
  $ sh $TESTDIR/testlib/stream_clone_setup.sh
  adding 00changelog-ab349180a0405010.nd
  adding 00changelog.d
  adding 00changelog.i
  adding 00changelog.n
  adding 00manifest.d
  adding 00manifest.i
  adding container/isam-build-centos7/bazel-coverage-generator-sandboxfs-compatibility-0758e3e4f6057904d44399bd666faba9e7f40686.patch
  adding data/foo.d
  adding data/foo.i
  adding data/foo.n
  adding data/undo.babar
  adding data/undo.d
  adding data/undo.foo.d
  adding data/undo.foo.i
  adding data/undo.foo.n
  adding data/undo.i
  adding data/undo.n
  adding data/undo.py
  adding foo.d
  adding foo.i
  adding foo.n
  adding meta/foo.d
  adding meta/foo.i
  adding meta/foo.n
  adding meta/undo.babar
  adding meta/undo.d
  adding meta/undo.foo.d
  adding meta/undo.foo.i
  adding meta/undo.foo.n
  adding meta/undo.i
  adding meta/undo.n
  adding meta/undo.py
  adding savanah/foo.d
  adding savanah/foo.i
  adding savanah/foo.n
  adding savanah/undo.babar
  adding savanah/undo.d
  adding savanah/undo.foo.d
  adding savanah/undo.foo.i
  adding savanah/undo.foo.n
  adding savanah/undo.i
  adding savanah/undo.n
  adding savanah/undo.py
  adding store/C\xc3\xa9lesteVille_is_a_Capital_City (esc)
  adding store/foo.d
  adding store/foo.i
  adding store/foo.n
  adding store/undo.babar
  adding store/undo.d
  adding store/undo.foo.d
  adding store/undo.foo.i
  adding store/undo.foo.n
  adding store/undo.i
  adding store/undo.n
  adding store/undo.py
  adding undo.babar
  adding undo.d
  adding undo.foo.d
  adding undo.foo.i
  adding undo.foo.n
  adding undo.i
  adding undo.n
  adding undo.py
  $ cd ..


Test streaming from/to repository without a store:
==================================================

  $ hg clone --pull --config format.usestore=no server server-no-store
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 1088 changes to 1088 files
  new changesets 96ee1d7354c4:5223b5e3265f
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg verify -R server-no-store
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg -R server serve -p $HGPORT -d --pid-file=hg-1.pid --error errors-1.txt
  $ cat hg-1.pid > $DAEMON_PIDS
  $ hg -R server-no-store serve -p $HGPORT2 -d --pid-file=hg-2.pid --error errors-2.txt
  $ cat hg-2.pid >> $DAEMON_PIDS
  $ hg debugrequires -R server | grep store
  store
  $ hg debugrequires -R server-no-store | grep store
  [1]

store → no-store cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT clone-remove-store --config format.usestore=no
  $ cat errors-1.txt
  $ hg -R clone-remove-store verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-remove-store | grep store
  [1]


no-store → store cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT2 clone-add-store --config format.usestore=yes
  $ cat errors-2.txt
  $ hg -R clone-add-store verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-add-store | grep store
  store


  $ killdaemons.py


Test streaming from/to repository without a fncache
===================================================

  $ rm hg-*.pid errors-*.txt
  $ hg clone --pull --config format.usefncache=no server server-no-fncache
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 1088 changes to 1088 files
  new changesets 96ee1d7354c4:5223b5e3265f
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg verify -R server-no-fncache
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg -R server serve -p $HGPORT -d --pid-file=hg-1.pid --error errors-1.txt
  $ cat hg-1.pid > $DAEMON_PIDS
  $ hg -R server-no-fncache serve -p $HGPORT2 -d --pid-file=hg-2.pid --error errors-2.txt
  $ cat hg-2.pid >> $DAEMON_PIDS
  $ hg debugrequires -R server | grep fncache
  fncache
  $ hg debugrequires -R server-no-fncache | grep fncache
  [1]

fncache → no-fncache cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT clone-remove-fncache --config format.usefncache=no
  $ cat errors-1.txt
  $ hg -R clone-remove-fncache verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-remove-fncache | grep fncache
  [1]


no-fncache → fncache cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT2 clone-add-fncache --config format.usefncache=yes
  $ cat errors-2.txt
  $ hg -R clone-add-fncache verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-add-fncache | grep fncache
  fncache


  $ killdaemons.py



Test streaming from/to repository without a dotencode
===================================================

  $ rm hg-*.pid errors-*.txt
  $ hg clone --pull --config format.dotencode=no server server-no-dotencode
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 1088 changes to 1088 files
  new changesets 96ee1d7354c4:5223b5e3265f
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg verify -R server-no-dotencode
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg -R server serve -p $HGPORT -d --pid-file=hg-1.pid --error errors-1.txt
  $ cat hg-1.pid > $DAEMON_PIDS
  $ hg -R server-no-dotencode serve -p $HGPORT2 -d --pid-file=hg-2.pid --error errors-2.txt
  $ cat hg-2.pid >> $DAEMON_PIDS
  $ hg debugrequires -R server | grep dotencode
  dotencode
  $ hg debugrequires -R server-no-dotencode | grep dotencode
  [1]

dotencode → no-dotencode cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT clone-remove-dotencode --config format.dotencode=no
  $ cat errors-1.txt
  $ hg -R clone-remove-dotencode verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-remove-dotencode | grep dotencode
  [1]


no-dotencode → dotencode cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT2 clone-add-dotencode --config format.dotencode=yes
  $ cat errors-2.txt
  $ hg -R clone-add-dotencode verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-add-dotencode | grep dotencode
  dotencode


  $ killdaemons.py

Cloning from a share
--------------------

We should be able to clone from a "share" repository, it will use the source store for streaming.

The resulting clone should not use share.

  $ rm hg-*.pid errors-*.txt
  $ hg share --config extensions.share= server server-share -U
  $ hg -R server-share serve -p $HGPORT -d --pid-file=hg-1.pid --error errors-1.txt
  $ cat hg-1.pid > $DAEMON_PIDS

  $ hg clone --quiet --stream -U http://localhost:$HGPORT clone-from-share
  $ hg -R clone-from-share verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-from-share | grep share
  [1]

  $ killdaemons.py

This file contains tests case that deal with format change accross stream clone

#require serve no-reposimplestore no-chg

#testcases stream-legacy stream-bundle2

  $ cat << EOF >> $HGRCPATH
  > [storage]
  > revlog.persistent-nodemap.slow-path=allow
  > EOF

#if stream-legacy
  $ cat << EOF >> $HGRCPATH
  > [server]
  > bundle2.stream = no
  > EOF
#endif

Initialize repository

  $ hg init server --config format.use-share-safe=yes --config format.use-persistent-nodemap=yes
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
  $ hg debugbuilddag .+5000 --from-existing
  $ ls -1 .hg/store/00changelog*
  .hg/store/00changelog-*.nd (glob)
  .hg/store/00changelog.d
  .hg/store/00changelog.i
  .hg/store/00changelog.n
  $ cd ..


#if no-windows

Test streaming from/to repository without a store:
==================================================

This is skipped Windows needs dot-encode to handle some of the file in this
tests, and dot-encode need the store enabled.

  $ hg clone --pull --config format.usestore=no server server-no-store
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 5004 changesets with 1088 changes to 1088 files (+1 heads)
  new changesets 96ee1d7354c4:06ddac466af5
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg verify -R server-no-store
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 5004 changesets with 1088 changes to 1088 files
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
  checked 5004 changesets with 1088 changes to 1088 files
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
  checked 5004 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-add-store | grep store
  store


  $ killdaemons.py
  $ rm hg-*.pid errors-*.txt

#endif


Test streaming from/to repository without a fncache
===================================================

  $ hg clone --pull --config format.usefncache=no server server-no-fncache
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 5004 changesets with 1088 changes to 1088 files (+1 heads)
  new changesets 96ee1d7354c4:06ddac466af5
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg verify -R server-no-fncache
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 5004 changesets with 1088 changes to 1088 files
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
  checked 5004 changesets with 1088 changes to 1088 files
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
  checked 5004 changesets with 1088 changes to 1088 files
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
  added 5004 changesets with 1088 changes to 1088 files (+1 heads)
  new changesets 96ee1d7354c4:06ddac466af5
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg verify -R server-no-dotencode
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 5004 changesets with 1088 changes to 1088 files
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
  checked 5004 changesets with 1088 changes to 1088 files
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
  checked 5004 changesets with 1088 changes to 1088 files
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
  checked 5004 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-from-share | egrep 'share$'
  [1]

  $ killdaemons.py

Test streaming from/to repository without a share-safe
======================================================

  $ rm hg-*.pid errors-*.txt
  $ hg clone --pull --config format.use-share-safe=no server server-no-share-safe
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 5004 changesets with 1088 changes to 1088 files (+1 heads)
  new changesets 96ee1d7354c4:06ddac466af5
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg verify -R server-no-share-safe
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 5004 changesets with 1088 changes to 1088 files
  $ hg -R server serve -p $HGPORT -d --pid-file=hg-1.pid --error errors-1.txt
  $ cat hg-1.pid > $DAEMON_PIDS
  $ hg -R server-no-share-safe serve -p $HGPORT2 -d --pid-file=hg-2.pid --error errors-2.txt
  $ cat hg-2.pid >> $DAEMON_PIDS
  $ hg debugrequires -R server | grep share-safe
  share-safe
  $ hg debugrequires -R server-no-share-safe | grep share-safe
  [1]

share-safe → no-share-safe cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT clone-remove-share-safe --config format.use-share-safe=no
  $ cat errors-1.txt
  $ hg -R clone-remove-share-safe verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 5004 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-remove-share-safe | grep share-safe
  [1]


no-share-safe → share-safe cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT2 clone-add-share-safe --config format.use-share-safe=yes
  $ cat errors-2.txt
  $ hg -R clone-add-share-safe verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 5004 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-add-share-safe | grep share-safe
  share-safe


  $ killdaemons.py


Test streaming from/to repository without a persistent-nodemap
==============================================================

persistent nodemap affects revlog, but they are easy to generate locally, so we allow it to be changed over a stream clone

  $ rm hg-*.pid errors-*.txt
  $ hg clone --pull --config format.use-persistent-nodemap=no server server-no-persistent-nodemap
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 5004 changesets with 1088 changes to 1088 files (+1 heads)
  new changesets 96ee1d7354c4:06ddac466af5
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg verify -R server-no-persistent-nodemap
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 5004 changesets with 1088 changes to 1088 files
  $ hg -R server serve -p $HGPORT -d --pid-file=hg-1.pid --error errors-1.txt
  $ cat hg-1.pid > $DAEMON_PIDS
  $ hg -R server-no-persistent-nodemap serve -p $HGPORT2 -d --pid-file=hg-2.pid --error errors-2.txt
  $ cat hg-2.pid >> $DAEMON_PIDS
  $ hg debugrequires -R server | grep persistent-nodemap
  persistent-nodemap
  $ hg debugrequires -R server-no-persistent-nodemap | grep persistent-nodemap
  [1]
  $ ls -1 server/.hg/store/00changelog*
  server/.hg/store/00changelog-*.nd (glob)
  server/.hg/store/00changelog.d
  server/.hg/store/00changelog.i
  server/.hg/store/00changelog.n
  $ ls -1 server-no-persistent-nodemap/.hg/store/00changelog*
  server-no-persistent-nodemap/.hg/store/00changelog.d
  server-no-persistent-nodemap/.hg/store/00changelog.i

persistent-nodemap → no-persistent-nodemap cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT clone-remove-persistent-nodemap --config format.use-persistent-nodemap=no
  $ cat errors-1.txt
  $ hg -R clone-remove-persistent-nodemap verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 5004 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-remove-persistent-nodemap | grep persistent-nodemap
  [1]

The persistent-nodemap files should no longer exists

  $ ls -1 clone-remove-persistent-nodemap/.hg/store/00changelog*
  clone-remove-persistent-nodemap/.hg/store/00changelog.d
  clone-remove-persistent-nodemap/.hg/store/00changelog.i


no-persistent-nodemap → persistent-nodemap cloning

  $ hg clone --quiet --stream -U http://localhost:$HGPORT2 clone-add-persistent-nodemap --config format.use-persistent-nodemap=yes
  $ cat errors-2.txt
  $ hg -R clone-add-persistent-nodemap verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 5004 changesets with 1088 changes to 1088 files
  $ hg debugrequires -R clone-add-persistent-nodemap | grep persistent-nodemap
  persistent-nodemap

The persistent-nodemap files should exists

  $ ls -1 clone-add-persistent-nodemap/.hg/store/00changelog*
  clone-add-persistent-nodemap/.hg/store/00changelog-*.nd (glob)
  clone-add-persistent-nodemap/.hg/store/00changelog.d
  clone-add-persistent-nodemap/.hg/store/00changelog.i
  clone-add-persistent-nodemap/.hg/store/00changelog.n


  $ killdaemons.py

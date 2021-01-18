setup

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > share =
  > [format]
  > use-share-safe = True
  > [storage]
  > revlog.persistent-nodemap.slow-path=allow
  > EOF

prepare source repo

  $ hg init source
  $ cd source
  $ cat .hg/requires
  share-safe
  $ cat .hg/store/requires
  dotencode
  fncache
  generaldelta
  revlogv1
  sparserevlog
  store
  $ hg debugrequirements
  dotencode
  fncache
  generaldelta
  revlogv1
  share-safe
  sparserevlog
  store

  $ echo a > a
  $ hg ci -Aqm "added a"
  $ echo b > b
  $ hg ci -Aqm "added b"

  $ HGEDITOR=cat hg config --shared
  abort: repository is not shared; can't use --shared
  [10]
  $ cd ..

Create a shared repo and check the requirements are shared and read correctly
  $ hg share source shared1
  updating working directory
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd shared1
  $ cat .hg/requires
  share-safe
  shared

  $ hg debugrequirements -R ../source
  dotencode
  fncache
  generaldelta
  revlogv1
  share-safe
  sparserevlog
  store

  $ hg debugrequirements
  dotencode
  fncache
  generaldelta
  revlogv1
  share-safe
  shared
  sparserevlog
  store

  $ echo c > c
  $ hg ci -Aqm "added c"

Check that config of the source repository is also loaded

  $ hg showconfig ui.curses
  [1]

  $ echo "[ui]" >> ../source/.hg/hgrc
  $ echo "curses=true" >> ../source/.hg/hgrc

  $ hg showconfig ui.curses
  true

Test that extensions of source repository are also loaded

  $ hg debugextensions
  share
  $ hg extdiff -p echo
  hg: unknown command 'extdiff'
  'extdiff' is provided by the following extension:
  
      extdiff       command to allow external programs to compare revisions
  
  (use 'hg help extensions' for information on enabling extensions)
  [10]

  $ echo "[extensions]" >> ../source/.hg/hgrc
  $ echo "extdiff=" >> ../source/.hg/hgrc

  $ hg debugextensions -R ../source
  extdiff
  share
  $ hg extdiff -R ../source -p echo

BROKEN: the command below will not work if config of shared source is not loaded
on dispatch but debugextensions says that extension
is loaded
  $ hg debugextensions
  extdiff
  share

  $ hg extdiff -p echo

However, local .hg/hgrc should override the config set by share source

  $ echo "[ui]" >> .hg/hgrc
  $ echo "curses=false" >> .hg/hgrc

  $ hg showconfig ui.curses
  false

  $ HGEDITOR=cat hg config --shared
  [ui]
  curses=true
  [extensions]
  extdiff=

  $ HGEDITOR=cat hg config --local
  [ui]
  curses=false

Testing that hooks set in source repository also runs in shared repo

  $ cd ../source
  $ cat <<EOF >> .hg/hgrc
  > [extensions]
  > hooklib=
  > [hooks]
  > pretxnchangegroup.reject_merge_commits = \
  >   python:hgext.hooklib.reject_merge_commits.hook
  > EOF

  $ cd ..
  $ hg clone source cloned
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd cloned
  $ hg up 0
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ echo bar > bar
  $ hg ci -Aqm "added bar"
  $ hg merge
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "merge commit"

  $ hg push ../source
  pushing to ../source
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  error: pretxnchangegroup.reject_merge_commits hook failed: bcde3522682d rejected as merge on the same branch. Please consider rebase.
  transaction abort!
  rollback completed
  abort: bcde3522682d rejected as merge on the same branch. Please consider rebase.
  [255]

  $ hg push ../shared1
  pushing to ../shared1
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  error: pretxnchangegroup.reject_merge_commits hook failed: bcde3522682d rejected as merge on the same branch. Please consider rebase.
  transaction abort!
  rollback completed
  abort: bcde3522682d rejected as merge on the same branch. Please consider rebase.
  [255]

Test that if share source config is untrusted, we dont read it

  $ cd ../shared1

  $ cat << EOF > $TESTTMP/untrusted.py
  > from mercurial import scmutil, util
  > def uisetup(ui):
  >     class untrustedui(ui.__class__):
  >         def _trusted(self, fp, f):
  >             if util.normpath(fp.name).endswith(b'source/.hg/hgrc'):
  >                 return False
  >             return super(untrustedui, self)._trusted(fp, f)
  >     ui.__class__ = untrustedui
  > EOF

  $ hg showconfig hooks
  hooks.pretxnchangegroup.reject_merge_commits=python:hgext.hooklib.reject_merge_commits.hook

  $ hg showconfig hooks --config extensions.untrusted=$TESTTMP/untrusted.py
  [1]

Update the source repository format and check that shared repo works

  $ cd ../source

Disable zstd related tests because its not present on pure version
#if zstd
  $ echo "[format]" >> .hg/hgrc
  $ echo "revlog-compression=zstd" >> .hg/hgrc

  $ hg debugupgraderepo --run -q
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, share-safe, sparserevlog, store
     added: revlog-compression-zstd
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg log -r .
  changeset:   1:5f6d8a4bf34a
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     added b
  
#endif
  $ echo "[format]" >> .hg/hgrc
  $ echo "use-persistent-nodemap=True" >> .hg/hgrc

  $ hg debugupgraderepo --run -q -R ../shared1
  abort: cannot upgrade repository; unsupported source requirement: shared
  [255]

  $ hg debugupgraderepo --run -q
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, share-safe, sparserevlog, store (no-zstd !)
     preserved: dotencode, fncache, generaldelta, revlog-compression-zstd, revlogv1, share-safe, sparserevlog, store (zstd !)
     added: persistent-nodemap
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg log -r .
  changeset:   1:5f6d8a4bf34a
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     added b
  

Shared one should work
  $ cd ../shared1
  $ hg log -r .
  changeset:   2:155349b645be
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     added c
  

Testing that nonsharedrc is loaded for source and not shared

  $ cd ../source
  $ touch .hg/hgrc-not-shared
  $ echo "[ui]" >> .hg/hgrc-not-shared
  $ echo "traceback=true" >> .hg/hgrc-not-shared

  $ hg showconfig ui.traceback
  true

  $ HGEDITOR=cat hg config --non-shared
  [ui]
  traceback=true

  $ cd ../shared1
  $ hg showconfig ui.traceback
  [1]

Unsharing works

  $ hg unshare

Test that source config is added to the shared one after unshare, and the config
of current repo is still respected over the config which came from source config
  $ cd ../cloned
  $ hg push ../shared1
  pushing to ../shared1
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  error: pretxnchangegroup.reject_merge_commits hook failed: bcde3522682d rejected as merge on the same branch. Please consider rebase.
  transaction abort!
  rollback completed
  abort: bcde3522682d rejected as merge on the same branch. Please consider rebase.
  [255]
  $ hg showconfig ui.curses -R ../shared1
  false

  $ cd ../

Test that upgrading using debugupgraderepo works
=================================================

  $ hg init non-share-safe --config format.use-share-safe=false
  $ cd non-share-safe
  $ hg debugrequirements
  dotencode
  fncache
  generaldelta
  revlogv1
  sparserevlog
  store
  $ echo foo > foo
  $ hg ci -Aqm 'added foo'
  $ echo bar > bar
  $ hg ci -Aqm 'added bar'

Create a share before upgrading

  $ cd ..
  $ hg share non-share-safe nss-share
  updating working directory
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugrequirements -R nss-share
  dotencode
  fncache
  generaldelta
  revlogv1
  shared
  sparserevlog
  store
  $ cd non-share-safe

Upgrade

  $ hg debugupgraderepo -q
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store
     added: share-safe
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg debugupgraderepo --run -q
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store
     added: share-safe
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  repository upgraded to share safe mode, existing shares will still work in old non-safe mode. Re-share existing shares to use them in safe mode New shares will be created in safe mode.

  $ hg debugrequirements
  dotencode
  fncache
  generaldelta
  revlogv1
  share-safe
  sparserevlog
  store

  $ cat .hg/requires
  share-safe

  $ cat .hg/store/requires
  dotencode
  fncache
  generaldelta
  revlogv1
  sparserevlog
  store

  $ hg log -GT "{node}: {desc}\n"
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  

Make sure existing shares dont work with default config

  $ hg log -GT "{node}: {desc}\n" -R ../nss-share
  abort: version mismatch: source uses share-safe functionality while the current share does not
  [255]


Create a safe share from upgrade one

  $ cd ..
  $ hg share non-share-safe ss-share
  updating working directory
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd ss-share
  $ hg log -GT "{node}: {desc}\n"
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  
  $ cd ../non-share-safe

Test that downgrading works too

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > share =
  > [format]
  > use-share-safe = False
  > EOF

  $ hg debugupgraderepo -q
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store
     removed: share-safe
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg debugupgraderepo -q --run
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store
     removed: share-safe
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  repository downgraded to not use share safe mode, existing shares will not work and needs to be reshared.

  $ hg debugrequirements
  dotencode
  fncache
  generaldelta
  revlogv1
  sparserevlog
  store

  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  revlogv1
  sparserevlog
  store

  $ test -f .hg/store/requires
  [1]

  $ hg log -GT "{node}: {desc}\n"
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  

Make sure existing shares still works

  $ hg log -GT "{node}: {desc}\n" -R ../nss-share
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  

  $ hg log -GT "{node}: {desc}\n" -R ../ss-share
  abort: share source does not support exp-sharesafe requirement
  [255]

Testing automatic downgrade of shares when config is set

  $ touch ../ss-share/.hg/wlock
  $ hg log -GT "{node}: {desc}\n" -R ../ss-share --config share.safe-mismatch.source-not-safe=downgrade-abort
  abort: failed to downgrade share, got error: Lock held
  [255]
  $ rm ../ss-share/.hg/wlock

  $ hg log -GT "{node}: {desc}\n" -R ../ss-share --config share.safe-mismatch.source-not-safe=downgrade-abort
  repository downgraded to not use share-safe mode
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  

  $ hg log -GT "{node}: {desc}\n" -R ../ss-share
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  


Testing automatic upgrade of shares when config is set

  $ hg debugupgraderepo -q --run --config format.use-share-safe=True
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store
     added: share-safe
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  repository upgraded to share safe mode, existing shares will still work in old non-safe mode. Re-share existing shares to use them in safe mode New shares will be created in safe mode.
  $ hg debugrequirements
  dotencode
  fncache
  generaldelta
  revlogv1
  share-safe
  sparserevlog
  store
  $ hg log -GT "{node}: {desc}\n" -R ../nss-share
  abort: version mismatch: source uses share-safe functionality while the current share does not
  [255]

Check that if lock is taken, upgrade fails but read operation are successful
  $ hg log -GT "{node}: {desc}\n" -R ../nss-share --config share.safe-mismatch.source-safe=upgra
  abort: share-safe mismatch with source.
  Unrecognized value 'upgra' of `share.safe-mismatch.source-safe` set.
  (run `hg help config.share.safe-mismatch.source-safe`)
  [255]
  $ touch ../nss-share/.hg/wlock
  $ hg log -GT "{node}: {desc}\n" -R ../nss-share --config share.safe-mismatch.source-safe=upgrade-allow
  failed to upgrade share, got error: Lock held
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  

  $ hg log -GT "{node}: {desc}\n" -R ../nss-share --config share.safe-mismatch.source-safe=upgrade-allow --config share.safe-mismatch.source-safe.warn=False
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  

  $ hg log -GT "{node}: {desc}\n" -R ../nss-share --config share.safe-mismatch.source-safe=upgrade-abort
  abort: failed to upgrade share, got error: Lock held
  [255]

  $ rm ../nss-share/.hg/wlock
  $ hg log -GT "{node}: {desc}\n" -R ../nss-share --config share.safe-mismatch.source-safe=upgrade-abort
  repository upgraded to use share-safe mode
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  

Test that unshare works

  $ hg unshare -R ../nss-share
  $ hg log -GT "{node}: {desc}\n" -R ../nss-share
  @  f63db81e6dde1d9c78814167f77fb1fb49283f4f: added bar
  |
  o  f3ba8b99bb6f897c87bbc1c07b75c6ddf43a4f77: added foo
  

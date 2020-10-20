setup

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > share =
  > [format]
  > exp-share-safe = True
  > EOF

prepare source repo

  $ hg init source
  $ cd source
  $ cat .hg/requires
  exp-sharesafe
  $ cat .hg/store/requires
  dotencode
  fncache
  generaldelta
  revlogv1
  sparserevlog
  store
  $ hg debugrequirements
  dotencode
  exp-sharesafe
  fncache
  generaldelta
  revlogv1
  sparserevlog
  store

  $ echo a > a
  $ hg ci -Aqm "added a"
  $ echo b > b
  $ hg ci -Aqm "added b"

  $ HGEDITOR=cat hg config --shared
  abort: repository is not shared; can't use --shared
  [255]
  $ cd ..

Create a shared repo and check the requirements are shared and read correctly
  $ hg share source shared1
  updating working directory
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd shared1
  $ cat .hg/requires
  exp-sharesafe
  shared

  $ hg debugrequirements -R ../source
  dotencode
  exp-sharesafe
  fncache
  generaldelta
  revlogv1
  sparserevlog
  store

  $ hg debugrequirements
  dotencode
  exp-sharesafe
  fncache
  generaldelta
  revlogv1
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

However, local .hg/hgrc should override the config set by share source

  $ echo "[ui]" >> .hg/hgrc
  $ echo "curses=false" >> .hg/hgrc

  $ hg showconfig ui.curses
  false

  $ HGEDITOR=cat hg config --shared
  [ui]
  curses=true

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
     preserved: dotencode, exp-sharesafe, fncache, generaldelta, revlogv1, sparserevlog, store
     added: revlog-compression-zstd
  
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
     preserved: dotencode, exp-sharesafe, fncache, generaldelta, revlogv1, sparserevlog, store (no-zstd !)
     preserved: dotencode, exp-sharesafe, fncache, generaldelta, revlog-compression-zstd, revlogv1, sparserevlog, store (zstd !)
     added: persistent-nodemap
  
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

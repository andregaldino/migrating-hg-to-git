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

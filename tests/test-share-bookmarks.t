#testcases vfs svfs
#testcases safe normal

#if safe
  $ echo "[format]"         >> $HGRCPATH
  $ echo "use-share-safe = True" >> $HGRCPATH
#endif

  $ echo "[extensions]"      >> $HGRCPATH
  $ echo "share = "          >> $HGRCPATH

#if svfs
  $ echo "[format]"                  >> $HGRCPATH
  $ echo "bookmarks-in-store = yes " >> $HGRCPATH
#endif

prepare repo1

  $ hg init repo1
  $ cd repo1
  $ echo a > a
  $ hg commit -A -m'init'
  adding a
  $ echo a >> a
  $ hg commit -m'change in shared clone'
  $ echo b > b
  $ hg commit -A -m'another file'
  adding b

share it

  $ cd ..
  $ hg share repo1 repo2
  updating working directory
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

test sharing bookmarks

  $ hg share -B repo1 repo3
  updating working directory
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd repo1
  $ hg bookmark bm1
  $ hg bookmarks
   * bm1                       2:c2e0ac586386
  $ cd ../repo2
  $ hg book bm2
  $ hg bookmarks
     bm1                       2:c2e0ac586386 (svfs !)
   * bm2                       2:c2e0ac586386
  $ cd ../repo3
  $ hg bookmarks
     bm1                       2:c2e0ac586386
     bm2                       2:c2e0ac586386 (svfs !)
  $ hg book bm3
  $ hg bookmarks
     bm1                       2:c2e0ac586386
     bm2                       2:c2e0ac586386 (svfs !)
   * bm3                       2:c2e0ac586386
  $ cd ../repo1
  $ hg bookmarks
   * bm1                       2:c2e0ac586386
     bm2                       2:c2e0ac586386 (svfs !)
     bm3                       2:c2e0ac586386

check whether HG_PENDING makes pending changes only in relatd
repositories visible to an external hook.

In "hg share" case, another transaction can't run in other
repositories sharing same source repository, because starting
transaction requires locking store of source repository.

Therefore, this test scenario ignores checking visibility of
.hg/bookmarks.pending in repo2, which shares repo1 without bookmarks.

  $ cat > $TESTTMP/checkbookmarks.sh <<EOF
  > echo "@repo1"
  > hg -R "$TESTTMP/repo1" bookmarks
  > echo "@repo2"
  > hg -R "$TESTTMP/repo2" bookmarks
  > echo "@repo3"
  > hg -R "$TESTTMP/repo3" bookmarks
  > exit 1 # to avoid adding new bookmark for subsequent tests
  > EOF

  $ cd ../repo1
  $ hg --config hooks.pretxnclose="sh $TESTTMP/checkbookmarks.sh" -q book bmX
  @repo1
     bm1                       2:c2e0ac586386
     bm2                       2:c2e0ac586386 (svfs !)
     bm3                       2:c2e0ac586386
   * bmX                       2:c2e0ac586386
  @repo2
     bm1                       2:c2e0ac586386 (svfs !)
   * bm2                       2:c2e0ac586386
     bm3                       2:c2e0ac586386 (svfs !)
  @repo3
     bm1                       2:c2e0ac586386
     bm2                       2:c2e0ac586386 (svfs !)
   * bm3                       2:c2e0ac586386
     bmX                       2:c2e0ac586386 (vfs !)
  transaction abort!
  rollback completed
  abort: pretxnclose hook exited with status 1
  [40]
  $ hg book bm1

FYI, in contrast to above test, bmX is invisible in repo1 (= shared
src), because (1) HG_PENDING refers only repo3 and (2)
"bookmarks.pending" is written only into repo3.

  $ cd ../repo3
  $ hg --config hooks.pretxnclose="sh $TESTTMP/checkbookmarks.sh" -q book bmX
  @repo1
   * bm1                       2:c2e0ac586386
     bm2                       2:c2e0ac586386 (svfs !)
     bm3                       2:c2e0ac586386
  @repo2
     bm1                       2:c2e0ac586386 (svfs !)
   * bm2                       2:c2e0ac586386
     bm3                       2:c2e0ac586386 (svfs !)
  @repo3
     bm1                       2:c2e0ac586386
     bm2                       2:c2e0ac586386 (svfs !)
     bm3                       2:c2e0ac586386
   * bmX                       2:c2e0ac586386
  transaction abort!
  rollback completed
  abort: pretxnclose hook exited with status 1
  [40]
  $ hg book bm3

clean up bm2 since it's uninteresting (not shared in the vfs case and
same as bm3 in the svfs case)
  $ cd ../repo2
  $ hg book -d bm2

  $ cd ../repo1

test that commits work

  $ echo 'shared bookmarks' > a
  $ hg commit -m 'testing shared bookmarks'
  $ hg bookmarks
   * bm1                       3:b87954705719
     bm3                       2:c2e0ac586386
  $ cd ../repo3
  $ hg bookmarks
     bm1                       3:b87954705719
   * bm3                       2:c2e0ac586386
  $ echo 'more shared bookmarks' > a
  $ hg commit -m 'testing shared bookmarks'
  created new head
  $ hg bookmarks
     bm1                       3:b87954705719
   * bm3                       4:62f4ded848e4
  $ cd ../repo1
  $ hg bookmarks
   * bm1                       3:b87954705719
     bm3                       4:62f4ded848e4
  $ cd ..

test pushing bookmarks works

  $ hg clone repo3 repo4
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd repo4
  $ hg boo bm4
  $ echo foo > b
  $ hg commit -m 'foo in b'
  $ hg boo
     bm1                       3:b87954705719
     bm3                       4:62f4ded848e4
   * bm4                       5:92793bfc8cad
  $ hg push -B bm4
  pushing to $TESTTMP/repo3
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  exporting bookmark bm4
  $ cd ../repo1
  $ hg bookmarks
   * bm1                       3:b87954705719
     bm3                       4:62f4ded848e4
     bm4                       5:92793bfc8cad
  $ cd ../repo3
  $ hg bookmarks
     bm1                       3:b87954705719
   * bm3                       4:62f4ded848e4
     bm4                       5:92793bfc8cad
  $ cd ..

test behavior when sharing a shared repo

  $ hg share -B repo3 missingdir/repo5
  updating working directory
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd missingdir/repo5
  $ hg book
     bm1                       3:b87954705719
     bm3                       4:62f4ded848e4
     bm4                       5:92793bfc8cad
  $ cd ../..

test what happens when an active bookmark is deleted

  $ cd repo1
  $ hg boo -d bm3
  $ hg boo
   * bm1                       3:b87954705719
     bm4                       5:92793bfc8cad
  $ cd ../repo3
  $ hg boo
     bm1                       3:b87954705719
     bm4                       5:92793bfc8cad
  $ cd ..

verify that bookmarks are not written on failed transaction

  $ cat > failpullbookmarks.py << EOF
  > """A small extension that makes bookmark pulls fail, for testing"""
  > from mercurial import (
  >   error,
  >   exchange,
  >   extensions,
  > )
  > def _pullbookmarks(orig, pullop):
  >     orig(pullop)
  >     raise error.HookAbort(b'forced failure by extension')
  > def extsetup(ui):
  >     extensions.wrapfunction(exchange, '_pullbookmarks', _pullbookmarks)
  > EOF
  $ cd repo4
  $ hg boo
     bm1                       3:b87954705719
     bm3                       4:62f4ded848e4
   * bm4                       5:92793bfc8cad
  $ cd ../repo3
  $ hg boo
     bm1                       3:b87954705719
     bm4                       5:92793bfc8cad
  $ hg --config "extensions.failpullbookmarks=$TESTTMP/failpullbookmarks.py" pull $TESTTMP/repo4
  pulling from $TESTTMP/repo4
  searching for changes
  no changes found
  adding remote bookmark bm3
  abort: forced failure by extension
  [40]
  $ hg boo
     bm1                       3:b87954705719
     bm4                       5:92793bfc8cad
  $ hg pull $TESTTMP/repo4
  pulling from $TESTTMP/repo4
  searching for changes
  no changes found
  adding remote bookmark bm3
  1 local changesets published
  $ hg boo
     bm1                       3:b87954705719
   * bm3                       4:62f4ded848e4
     bm4                       5:92793bfc8cad
  $ cd ..

verify bookmark behavior after unshare

  $ cd repo3
  $ hg unshare
  $ hg boo
     bm1                       3:b87954705719
   * bm3                       4:62f4ded848e4
     bm4                       5:92793bfc8cad
  $ hg boo -d bm4
  $ hg boo bm5
  $ hg boo
     bm1                       3:b87954705719
     bm3                       4:62f4ded848e4
   * bm5                       4:62f4ded848e4
  $ cd ../repo1
  $ hg boo
   * bm1                       3:b87954705719
     bm3                       4:62f4ded848e4
     bm4                       5:92793bfc8cad
  $ cd ..

Test that if store is disabled, we drop the bookmarksinstore requirement

  $ hg init brokenrepo --config format.bookmarks-in-store=True --config format.usestore=false
  ignoring enabled 'format.bookmarks-in-store' config beacuse it is incompatible with disabled 'format.usestore' config
  ignoring enabled 'format.use-share-safe' config because it is incompatible with disabled 'format.usestore' config (safe !)

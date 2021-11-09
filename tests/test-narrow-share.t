#testcases flat tree
#testcases safe normal

#if safe
  $ echo "[format]"         >> $HGRCPATH
  $ echo "exp-share-safe = True" >> $HGRCPATH
#endif

  $ . "$TESTDIR/narrow-library.sh"

#if tree
  $ cat << EOF >> $HGRCPATH
  > [experimental]
  > treemanifest = 1
  > EOF
#endif

  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > share =
  > EOF

  $ hg init remote
  $ cd remote
  $ for x in `$TESTDIR/seq.py 0 10`
  > do
  >   mkdir d$x
  >   echo $x > d$x/f
  >   hg add d$x/f
  >   hg commit -m "add d$x/f"
  > done
  $ cd ..

  $ hg clone --narrow ssh://user@dummy/remote main -q \
  > --include d1 --include d3 --include d5 --include d7

Ignore file called "ignored"
  $ echo ignored > main/.hgignore

  $ hg share main share
  updating working directory
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R share tracked
  I path:d1
  I path:d3
  I path:d5
  I path:d7
  $ hg -R share files
  share/d1/f
  share/d3/f
  share/d5/f
  share/d7/f

Narrow the share and check that the main repo's working copy gets updated

# Make sure the files that are supposed to be known-clean get their timestamps set in the dirstate
  $ sleep 2
  $ hg -R main st
  $ hg -R main debugdirstate --no-dates
  n 644          2 set                 d1/f
  n 644          2 set                 d3/f
  n 644          2 set                 d5/f
  n 644          2 set                 d7/f
# Make d3/f dirty
  $ echo x >> main/d3/f
  $ echo y >> main/d3/g
  $ touch main/d3/ignored
  $ touch main/d3/untracked
  $ hg add main/d3/g
  $ hg -R main st
  M d3/f
  A d3/g
  ? d3/untracked
# Make d5/f not match the dirstate timestamp even though it's clean
  $ sleep 2
  $ hg -R main st
  M d3/f
  A d3/g
  ? d3/untracked
  $ hg -R main debugdirstate --no-dates
  n 644          2 set                 d1/f
  n 644          2 set                 d3/f
  a   0         -1 unset               d3/g
  n 644          2 set                 d5/f
  n 644          2 set                 d7/f
  $ touch main/d5/f
  $ hg -R share tracked --removeinclude d1 --removeinclude d3 --removeinclude d5
  comparing with ssh://user@dummy/remote
  searching for changes
  looking for local changes to affected paths
  deleting data/d1/f.i
  deleting data/d3/f.i
  deleting data/d5/f.i
  deleting meta/d1/00manifest.i (tree !)
  deleting meta/d3/00manifest.i (tree !)
  deleting meta/d5/00manifest.i (tree !)
  deleting unwanted files from working copy
  $ hg -R main tracked
  I path:d7
  $ hg -R main files
  abort: working copy's narrowspec is stale
  (run 'hg tracked --update-working-copy')
  [20]
  $ hg -R main tracked --update-working-copy
  not deleting possibly dirty file d3/f
  not deleting possibly dirty file d3/g
  not deleting possibly dirty file d5/f
  not deleting unknown file d3/untracked
  not deleting ignored file d3/ignored
# d1/f, d3/f, d3/g and d5/f should no longer be reported
  $ hg -R main files
  main/d7/f
# d1/f should no longer be there, d3/f should be since it was dirty, d3/g should be there since
# it was added, and d5/f should be since we couldn't be sure it was clean
  $ find main/d* -type f | sort
  main/d3/f
  main/d3/g
  main/d3/ignored
  main/d3/untracked
  main/d5/f
  main/d7/f

Widen the share and check that the main repo's working copy gets updated

  $ hg -R share tracked --addinclude d1 --addinclude d3 -q
  $ hg -R share tracked
  I path:d1
  I path:d3
  I path:d7
  $ hg -R share files
  share/d1/f
  share/d3/f
  share/d7/f
  $ hg -R main tracked
  I path:d1
  I path:d3
  I path:d7
  $ hg -R main files
  abort: working copy's narrowspec is stale
  (run 'hg tracked --update-working-copy')
  [20]
  $ hg -R main tracked --update-working-copy
# d1/f, d3/f should be back
  $ hg -R main files
  main/d1/f
  main/d3/f
  main/d7/f
# d3/f should be modified (not clobbered by the widening), and d3/g should be untracked
  $ hg -R main st --all
  M d3/f
  ? d3/g
  ? d3/untracked
  I d3/ignored
  C d1/f
  C d7/f

We should also be able to unshare without breaking everything:

  $ hg share main share-unshare
  updating working directory
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd share-unshare
  $ hg unshare
  $ hg verify
  checking changesets
  checking manifests
  checking directory manifests (tree !)
  crosschecking files in changesets and manifests
  checking files
  checked 11 changesets with 3 changes to 3 files
  $ cd ..

Dirstate should be left alone when upgrading from version of hg that didn't support narrow+share

  $ hg share main share-upgrade
  updating working directory
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd share-upgrade
  $ echo x >> d1/f
  $ echo y >> d3/g
  $ hg add d3/g
  $ hg rm d7/f
  $ hg st
  M d1/f
  A d3/g
  R d7/f
Make it look like a repo from before narrow+share was supported
  $ rm .hg/narrowspec.dirstate
  $ hg ci -Am test
  abort: working copy's narrowspec is stale
  (run 'hg tracked --update-working-copy')
  [20]
  $ hg tracked --update-working-copy
  $ hg st
  M d1/f
  A d3/g
  R d7/f
  $ cd ..

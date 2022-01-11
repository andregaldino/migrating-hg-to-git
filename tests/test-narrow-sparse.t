Testing interaction of sparse and narrow when both are enabled on the client
side and we do a non-ellipsis clone

#testcases tree flat
  $ . "$TESTDIR/narrow-library.sh"
  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > sparse =
  > EOF

#if tree
  $ cat << EOF >> $HGRCPATH
  > [experimental]
  > treemanifest = 1
  > EOF
#endif

  $ hg init master
  $ cd master

  $ mkdir inside
  $ echo 'inside' > inside/f
  $ hg add inside/f
  $ hg commit -m 'add inside'

  $ mkdir widest
  $ echo 'widest' > widest/f
  $ hg add widest/f
  $ hg commit -m 'add widest'

  $ mkdir outside
  $ echo 'outside' > outside/f
  $ hg add outside/f
  $ hg commit -m 'add outside'

  $ cd ..

narrow clone the inside file

  $ hg clone --narrow ssh://user@dummy/master narrow --include inside/f
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 1 changes to 1 files
  new changesets *:* (glob)
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd narrow
  $ hg tracked
  I path:inside/f
  $ hg files
  inside/f

XXX: we should have a flag in `hg debugsparse` to list the sparse profile
  $ test -f .hg/sparse
  [1]

  $ hg debugrequires
  dotencode
  dirstate-v2 (dirstate-v2 !)
  fncache
  generaldelta
  narrowhg-experimental
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  revlogv1
  share-safe
  sparserevlog
  store
  treemanifest (tree !)

  $ hg debugrebuilddirstate

We only make the following assertions for the flat test case since in the
treemanifest test case debugsparse fails with "path ends in directory
separator: outside/" which seems like a bug unrelated to the regression this is
testing for.

#if flat
widening with both sparse and narrow is possible

  $ cat >> .hg/hgrc <<EOF
  > [extensions]
  > sparse = 
  > narrow = 
  > EOF

  $ hg debugsparse -X outside/f -X widest/f
  $ hg tracked -q --addinclude outside/f
  $ find . -name .hg -prune -o -type f -print | sort
  ./inside/f

  $ hg debugsparse -d outside/f
  $ find . -name .hg -prune -o -type f -print | sort
  ./inside/f
  ./outside/f
#endif

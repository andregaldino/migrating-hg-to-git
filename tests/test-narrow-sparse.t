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

  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  narrowhg-experimental
  revlogv1
  sparserevlog
  store
  treemanifest (tree !)

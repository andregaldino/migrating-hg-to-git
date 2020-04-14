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

  $ hg unshare

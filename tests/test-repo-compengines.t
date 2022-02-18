A new repository uses zlib storage, which doesn't need a requirement

  $ cat << EOF >> $HGRCPATH
  > [format]
  > # stabilize test accross variant
  > revlog-compression=zlib
  > EOF


  $ hg init default
  $ cd default
  $ hg debugrequires | grep compression
  [1]

  $ touch foo
  $ hg -q commit -A -m 'initial commit with a lot of repeated repeated repeated text to trigger compression'
  $ hg debugrevlog -c | grep 0x78
      0x78 (x)  :   1 (100.00%)
      0x78 (x)  : 110 (100.00%)

  $ cd ..

Unknown compression engine to format.compression aborts

  $ hg --config format.revlog-compression=unknown init unknown
  abort: compression engines "unknown" defined by format.revlog-compression not available
  (run "hg debuginstall" to list available compression engines)
  [255]

unknown compression engine in a list with known one works fine

  $ hg --config format.revlog-compression=zlib,unknown init zlib-before-unknow
  $ hg --config format.revlog-compression=unknown,zlib init unknown-before-zlib

A requirement specifying an unknown compression engine results in bail

  $ hg init unknownrequirement
  $ cd unknownrequirement
  $ echo exp-compression-unknown >> .hg/requires
  $ hg log
  abort: repository requires features unknown to this Mercurial: exp-compression-unknown
  (see https://mercurial-scm.org/wiki/MissingRequirement for more information)
  [255]

  $ cd ..

Specifying a new format.compression on an existing repo won't introduce data
with that engine or a requirement

  $ cd default
  $ touch bar
  $ hg --config format.revlog-compression=none -q commit -A -m 'add bar with a lot of repeated repeated repeated text'

  $ hg debugrequires | grep compression
  [1]

  $ hg debugrevlog -c | grep 0x78
      0x78 (x)  :   2 (100.00%)
      0x78 (x)  : 199 (100.00%)
  $ cd ..

#if zstd

  $ hg --config format.revlog-compression=zstd init zstd
  $ cd zstd
  $ hg debugrequires | grep compression
  revlog-compression-zstd

  $ touch foo
  $ hg -q commit -A -m 'initial commit with a lot of repeated repeated repeated text'

  $ hg debugrevlog -c | grep 0x28
      0x28      :  1 (100.00%)
      0x28      : 98 (100.00%)

  $ cd ..


#endif

checking zlib options
=====================

  $ hg init zlib-level-default
  $ hg init zlib-level-1
  $ cat << EOF >> zlib-level-1/.hg/hgrc
  > [storage]
  > revlog.zlib.level=1
  > EOF
  $ hg init zlib-level-9
  $ cat << EOF >> zlib-level-9/.hg/hgrc
  > [storage]
  > revlog.zlib.level=9
  > EOF


  $ commitone() {
  >    repo=$1
  >    cp $RUNTESTDIR/bundles/issue4438-r1.hg $repo/a
  >    hg -R $repo add $repo/a
  >    hg -R $repo commit -m some-commit
  > }

  $ for repo in zlib-level-default zlib-level-1 zlib-level-9; do
  >     commitone $repo
  > done

  $ $RUNTESTDIR/f -s */.hg/store/data/*
  default/.hg/store/data/bar.i: size=64
  default/.hg/store/data/foo.i: size=64
  zlib-level-1/.hg/store/data/a.i: size=4146
  zlib-level-9/.hg/store/data/a.i: size=4138
  zlib-level-default/.hg/store/data/a.i: size=4138
  zstd/.hg/store/data/foo.i: size=64 (zstd !)

Test error cases

  $ hg init zlib-level-invalid
  $ cat << EOF >> zlib-level-invalid/.hg/hgrc
  > [storage]
  > revlog.zlib.level=foobar
  > EOF
  $ commitone zlib-level-invalid
  config error: storage.revlog.zlib.level is not a valid integer ('foobar')
  config error: storage.revlog.zlib.level is not a valid integer ('foobar')
  [30]

  $ hg init zlib-level-out-of-range
  $ cat << EOF >> zlib-level-out-of-range/.hg/hgrc
  > [storage]
  > revlog.zlib.level=42
  > EOF

  $ commitone zlib-level-out-of-range
  abort: invalid value for `storage.revlog.zlib.level` config: 42
  abort: invalid value for `storage.revlog.zlib.level` config: 42
  [255]

checking details of none compression
====================================

  $ hg init none-compression --config format.revlog-compression=none

  $ commitone() {
  >    repo=$1
  >    cp $RUNTESTDIR/bundles/issue4438-r1.hg $repo/a
  >    hg -R $repo add $repo/a
  >    hg -R $repo commit -m some-commit
  > }

  $ commitone none-compression

  $ hg log -R none-compression
  changeset:   0:68b53da39cd8
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     some-commit
  

  $ hg debugrequires -R none-compression/ | grep compression
  exp-compression-none

  $ $RUNTESTDIR/f -s none-compression/.hg/store/data/*
  none-compression/.hg/store/data/a.i: size=4216

#if zstd

checking zstd options
=====================

  $ hg init zstd-level-default --config format.revlog-compression=zstd
  $ hg init zstd-level-1 --config format.revlog-compression=zstd
  $ cat << EOF >> zstd-level-1/.hg/hgrc
  > [storage]
  > revlog.zstd.level=1
  > EOF
  $ hg init zstd-level-22 --config format.revlog-compression=zstd
  $ cat << EOF >> zstd-level-22/.hg/hgrc
  > [storage]
  > revlog.zstd.level=22
  > EOF


  $ commitone() {
  >    repo=$1
  >    cp $RUNTESTDIR/bundles/issue4438-r1.hg $repo/a
  >    hg -R $repo add $repo/a
  >    hg -R $repo commit -m some-commit
  > }

  $ for repo in zstd-level-default zstd-level-1 zstd-level-22; do
  >     commitone $repo
  > done

  $ $RUNTESTDIR/f -s zstd-*/.hg/store/data/*
  zstd-level-1/.hg/store/data/a.i: size=4114
  zstd-level-22/.hg/store/data/a.i: size=4091
  zstd-level-default/\.hg/store/data/a\.i: size=(4094|4102) (re)

Test error cases

  $ hg init zstd-level-invalid --config format.revlog-compression=zstd
  $ cat << EOF >> zstd-level-invalid/.hg/hgrc
  > [storage]
  > revlog.zstd.level=foobar
  > EOF
  $ commitone zstd-level-invalid
  config error: storage.revlog.zstd.level is not a valid integer ('foobar')
  config error: storage.revlog.zstd.level is not a valid integer ('foobar')
  [30]

  $ hg init zstd-level-out-of-range --config format.revlog-compression=zstd
  $ cat << EOF >> zstd-level-out-of-range/.hg/hgrc
  > [storage]
  > revlog.zstd.level=42
  > EOF

  $ commitone zstd-level-out-of-range
  abort: invalid value for `storage.revlog.zstd.level` config: 42
  abort: invalid value for `storage.revlog.zstd.level` config: 42
  [255]

#endif

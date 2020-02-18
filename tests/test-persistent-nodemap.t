===================================
Test the persistent on-disk nodemap
===================================

  $ hg init test-repo
  $ cd test-repo
  $ cat << EOF >> .hg/hgrc
  > [experimental]
  > exp-persistent-nodemap=yes
  > [devel]
  > persistent-nodemap=yes
  > EOF
  $ hg debugbuilddag .+5000
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5000
  data-length: 122880
  data-unused: 0
  $ f --size .hg/store/00changelog.n
  .hg/store/00changelog.n: size=42

Simple lookup works

  $ ANYNODE=`hg log --template '{node|short}\n' --rev tip`
  $ hg log -r "$ANYNODE" --template '{rev}\n'
  5000


#if rust

  $ f --sha256 .hg/store/00changelog-*.nd
  .hg/store/00changelog-????????????????.nd: sha256=1e38e9ffaa45cad13f15c1a9880ad606f4241e8beea2f61b4d5365abadfb55f6 (glob)
  $ hg debugnodemap --dump-new | f --sha256 --size
  size=122880, sha256=1e38e9ffaa45cad13f15c1a9880ad606f4241e8beea2f61b4d5365abadfb55f6
  $ hg debugnodemap --dump-disk | f --sha256 --bytes=256 --hexdump --size
  size=122880, sha256=1e38e9ffaa45cad13f15c1a9880ad606f4241e8beea2f61b4d5365abadfb55f6
  0000: 00 00 00 76 00 00 01 65 00 00 00 95 00 00 01 34 |...v...e.......4|
  0010: 00 00 00 19 00 00 01 69 00 00 00 ab 00 00 00 4b |.......i.......K|
  0020: 00 00 00 07 00 00 01 4c 00 00 00 f8 00 00 00 8f |.......L........|
  0030: 00 00 00 c0 00 00 00 a7 00 00 00 89 00 00 01 46 |...............F|
  0040: 00 00 00 92 00 00 01 bc 00 00 00 71 00 00 00 ac |...........q....|
  0050: 00 00 00 af 00 00 00 b4 00 00 00 34 00 00 01 ca |...........4....|
  0060: 00 00 00 23 00 00 01 45 00 00 00 2d 00 00 00 b2 |...#...E...-....|
  0070: 00 00 00 56 00 00 01 0f 00 00 00 4e 00 00 02 4c |...V.......N...L|
  0080: 00 00 00 e7 00 00 00 cd 00 00 01 5b 00 00 00 78 |...........[...x|
  0090: 00 00 00 e3 00 00 01 8e 00 00 00 4f 00 00 00 b1 |...........O....|
  00a0: 00 00 00 30 00 00 00 11 00 00 00 25 00 00 00 d2 |...0.......%....|
  00b0: 00 00 00 ec 00 00 00 69 00 00 01 2b 00 00 01 2e |.......i...+....|
  00c0: 00 00 00 aa 00 00 00 15 00 00 00 3a 00 00 01 4e |...........:...N|
  00d0: 00 00 00 4d 00 00 00 9d 00 00 00 8e 00 00 00 a4 |...M............|
  00e0: 00 00 00 c3 00 00 00 eb 00 00 00 29 00 00 00 ad |...........)....|
  00f0: 00 00 01 3a 00 00 01 32 00 00 00 04 00 00 00 53 |...:...2.......S|


#else

  $ f --sha256 .hg/store/00changelog-*.nd
  .hg/store/00changelog-????????????????.nd: sha256=b961925120e1c9bc345c199b2cc442abc477029fdece37ef9d99cbe59c0558b7 (glob)
  $ hg debugnodemap --dump-new | f --sha256 --size
  size=122880, sha256=b961925120e1c9bc345c199b2cc442abc477029fdece37ef9d99cbe59c0558b7
  $ hg debugnodemap --dump-disk | f --sha256 --bytes=256 --hexdump --size
  size=122880, sha256=b961925120e1c9bc345c199b2cc442abc477029fdece37ef9d99cbe59c0558b7
  0000: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0010: ff ff ff ff ff ff ff ff ff ff fa c2 ff ff ff ff |................|
  0020: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0030: ff ff ff ff ff ff ed b3 ff ff ff ff ff ff ff ff |................|
  0040: ff ff ff ff ff ff ee 34 00 00 00 00 ff ff ff ff |.......4........|
  0050: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0060: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0070: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0080: ff ff ff ff ff ff f8 50 ff ff ff ff ff ff ff ff |.......P........|
  0090: ff ff ff ff ff ff ff ff ff ff ec c7 ff ff ff ff |................|
  00a0: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  00b0: ff ff ff ff ff ff fa be ff ff f2 fc ff ff ff ff |................|
  00c0: ff ff ff ff ff ff ef ea ff ff ff ff ff ff f9 17 |................|
  00d0: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  00e0: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  00f0: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|

#endif

  $ hg debugnodemap --check
  revision in index:   5001
  revision in nodemap: 5001

add a new commit

  $ hg up
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo foo > foo
  $ hg add foo
  $ hg ci -m 'foo'

#if no-pure no-rust
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5001
  data-length: 122880
  data-unused: 0
#else
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5001
  data-length: 123072
  data-unused: 192
#endif

  $ f --size .hg/store/00changelog.n
  .hg/store/00changelog.n: size=42

(The pure code use the debug code that perform incremental update, the C code reencode from scratch)

#if pure
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????????????.nd: size=123072, sha256=136472751566c8198ff09e306a7d2f9bd18bd32298d614752b73da4d6df23340 (glob)
#endif

#if rust
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????????????.nd: size=123072, sha256=ccc8a43310ace13812fcc648683e259346754ef934c12dd238cf9b7fadfe9a4b (glob)
#endif

#if no-pure no-rust
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????????????.nd: size=122880, sha256=bfafebd751c4f6d116a76a37a1dee2a251747affe7efbcc4f4842ccc746d4db9 (glob)
#endif

  $ hg debugnodemap --check
  revision in index:   5002
  revision in nodemap: 5002

Test code path without mmap
---------------------------

  $ echo bar > bar
  $ hg add bar
  $ hg ci -m 'bar' --config experimental.exp-persistent-nodemap.mmap=no

  $ hg debugnodemap --check --config experimental.exp-persistent-nodemap.mmap=yes
  revision in index:   5003
  revision in nodemap: 5003
  $ hg debugnodemap --check --config experimental.exp-persistent-nodemap.mmap=no
  revision in index:   5003
  revision in nodemap: 5003


#if pure
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5002
  data-length: 123328
  data-unused: 384
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????????????.nd: size=123328, sha256=10d26e9776b6596af0f89143a54eba8cc581e929c38242a02a7b0760698c6c70 (glob)
#endif
#if rust
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5002
  data-length: 123328
  data-unused: 384
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????????????.nd: size=123328, sha256=081eec9eb6708f2bf085d939b4c97bc0b6762bc8336bc4b93838f7fffa1516bf (glob)
#endif
#if no-pure no-rust
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5002
  data-length: 122944
  data-unused: 0
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????????????.nd: size=122944, sha256=755976b22b64ab680401b45395953504e64e7fa8c31ac570f58dee21e15f9bc0 (glob)
#endif

Test force warming the cache

  $ rm .hg/store/00changelog.n
  $ hg debugnodemap --metadata
  $ hg debugupdatecache
#if pure
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5002
  data-length: 122944
  data-unused: 0
#else
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5002
  data-length: 122944
  data-unused: 0
#endif

Check out of sync nodemap
=========================

First copy old data on the side.

  $ mkdir ../tmp-copies
  $ cp .hg/store/00changelog-????????????????.nd .hg/store/00changelog.n ../tmp-copies

Nodemap lagging behind
----------------------

make a new commit

  $ echo bar2 > bar
  $ hg ci -m 'bar2'
  $ NODE=`hg log -r tip -T '{node}\n'`
  $ hg log -r "$NODE" -T '{rev}\n'
  5003

If the nodemap is lagging behind, it can catch up fine

  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5003
  data-length: 123200 (pure !)
  data-length: 123200 (rust !)
  data-length: 122944 (no-rust no-pure !)
  data-unused: 256 (pure !)
  data-unused: 256 (rust !)
  data-unused: 0 (no-rust no-pure !)
  $ cp -f ../tmp-copies/* .hg/store/
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5002
  data-length: 122944
  data-unused: 0
  $ hg log -r "$NODE" -T '{rev}\n'
  5003

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
  $ hg debugnodemap --check
  revision in index:   5001
  revision in nodemap: 5001

add a new commit

  $ hg up
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo foo > foo
  $ hg add foo
  $ hg ci -m 'foo'

#if pure
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5001
  data-length: 123072
  data-unused: 192
#else
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5001
  data-length: 122880
  data-unused: 0
#endif
  $ f --size .hg/store/00changelog.n
  .hg/store/00changelog.n: size=42

(The pure code use the debug code that perform incremental update, the C code reencode from scratch)

#if pure
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????????????.nd: size=123072, sha256=136472751566c8198ff09e306a7d2f9bd18bd32298d614752b73da4d6df23340 (glob)

#else
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

#else
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

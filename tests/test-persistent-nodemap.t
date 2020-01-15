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
  $ f --size .hg/store/00changelog.n
  .hg/store/00changelog.n: size=26
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
  $ hg debugnodemap --metadata
  uid: ???????????????? (glob)
  tip-rev: 5001
  $ f --size .hg/store/00changelog.n
  .hg/store/00changelog.n: size=26

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

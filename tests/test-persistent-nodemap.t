===================================
Test the persistent on-disk nodemap
===================================


  $ hg init test-repo
  $ cd test-repo
  $ hg debugbuilddag .+5000
  $ hg debugnodemap --dump | f --sha256 --bytes=256 --hexdump --size
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

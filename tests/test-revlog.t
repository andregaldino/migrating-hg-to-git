  $ hg init empty-repo
  $ cd empty-repo

Flags on revlog version 0 are rejected

  >>> with open('.hg/store/00changelog.i', 'wb') as fh:
  ...     fh.write(b'\x00\x01\x00\x00') and None

  $ hg log
  abort: unknown flags (0x01) in version 0 revlog 00changelog.i
  [255]

Unknown flags on revlog version 1 are rejected

  >>> with open('.hg/store/00changelog.i', 'wb') as fh:
  ...     fh.write(b'\x00\x04\x00\x01') and None

  $ hg log
  abort: unknown flags (0x04) in version 1 revlog 00changelog.i
  [255]

Unknown version is rejected

  >>> with open('.hg/store/00changelog.i', 'wb') as fh:
  ...     fh.write(b'\x00\x00\x00\x02') and None

  $ hg log
  abort: unknown version (2) in revlog 00changelog.i
  [255]

  $ cd ..

Test for CVE-2016-3630

  $ hg init

  >>> import codecs
  >>> open("a.i", "wb").write(codecs.decode(codecs.decode(
  ... b"""eJxjYGZgZIAAYQYGxhgom+k/FMx8YKx9ZUaKSOyqo4cnuKb8mbqHV5cBCVTMWb1Cwqkhe4Gsg9AD
  ... Joa3dYtcYYYBAQ8Qr4OqZAYRICPTSr5WKd/42rV36d+8/VmrNpv7NP1jQAXrQE4BqQUARngwVA==""",
  ... "base64"), "zlib")) and None

  $ hg debugrevlogindex a.i
     rev linkrev nodeid       p1           p2
       0       2 99e0332bd498 000000000000 000000000000
       1       3 6674f57a23d8 99e0332bd498 000000000000

  >>> from mercurial import revlog, vfs
  >>> tvfs = vfs.vfs(b'.')
  >>> tvfs.options = {b'revlogv1': True}
  >>> rl = revlog.revlog(tvfs, b'a.i')
  >>> rl.revision(1)
  mpatchError(*'patch cannot be decoded'*) (glob)

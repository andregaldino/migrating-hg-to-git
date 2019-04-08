#require no-windows

  $ . "$TESTDIR/remotefilelog-library.sh"

  $ hg init master
  $ cd master
  $ cat >> .hg/hgrc <<EOF
  > [remotefilelog]
  > server=True
  > EOF
  $ echo x > x
  $ hg commit -qAm x
  $ echo y >> x
  $ hg commit -qAm y
  $ echo z >> x
  $ hg commit -qAm z
  $ echo a > a
  $ hg commit -qAm a

  $ cd ..

  $ hgcloneshallow ssh://user@dummy/master shallow -q
  2 files fetched over 1 fetches - (2 misses, 0.00% hit ratio) over *s (glob)
  $ cd shallow

Test blame

  $ hg blame x
  0: x
  1: y
  2: z
  2 files fetched over 1 fetches - (2 misses, 0.00% hit ratio) over *s (glob)

Test grepping the working directory.

  $ hg grep --all-files x
  x:x
BROKEN: modifications in the wdir tries to fetch from the server.
  $ echo foo >> x
  $ hg grep --all-files x
  remote: abort: working directory revision cannot be specified
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)
  abort: error downloading file contents:
  'connection closed early'
  [255]

An extension which will set fncache chunksize to 1 byte to make sure that logic
does not break

  $ cat > chunksize.py <<EOF
  > from __future__ import absolute_import
  > from mercurial import store
  > store.fncache_chunksize = 1
  > EOF

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > chunksize = $TESTTMP/chunksize.py
  > EOF

  .hg/wcache/manifestfulltextcache (reporevlogstore !)
  .hg/wcache/manifestfulltextcache (reporevlogstore !)
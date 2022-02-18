#require sqlite no-chg

The sqlitestore backend leaves transactions around when used with chg.
Since this backend is primarily intended as proof-of-concept for
alternative storage backends, disable it for chg test runs to avoid
the instability.

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > sqlitestore =
  > EOF

New repo should not use SQLite by default

  $ hg init empty-no-sqlite
  $ hg debugrequires -R empty-no-sqlite
  dotencode
  dirstate-v2 (dirstate-v2 !)
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  revlogv1
  share-safe
  sparserevlog
  store

storage.new-repo-backend=sqlite is recognized

  $ hg --config storage.new-repo-backend=sqlite init empty-sqlite
  $ hg debugrequires -R empty-sqlite
  dotencode
  dirstate-v2 (dirstate-v2 !)
  exp-sqlite-001
  exp-sqlite-comp-001=zstd (zstd !)
  exp-sqlite-comp-001=$BUNDLE2_COMPRESSIONS$ (no-zstd !)
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  revlogv1
  share-safe
  sparserevlog
  store

  $ cat >> $HGRCPATH << EOF
  > [storage]
  > new-repo-backend = sqlite
  > EOF

Can force compression to zlib

  $ hg --config storage.sqlite.compression=zlib init empty-zlib
  $ hg debugrequires -R empty-zlib
  dotencode
  dirstate-v2 (dirstate-v2 !)
  exp-sqlite-001
  exp-sqlite-comp-001=$BUNDLE2_COMPRESSIONS$
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  revlogv1
  share-safe
  sparserevlog
  store

Can force compression to none

  $ hg --config storage.sqlite.compression=none init empty-none
  $ hg debugrequires -R empty-none
  dotencode
  dirstate-v2 (dirstate-v2 !)
  exp-sqlite-001
  exp-sqlite-comp-001=none
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  revlogv1
  share-safe
  sparserevlog
  store

Can make a local commit

  $ hg init local-commit
  $ cd local-commit
  $ echo 0 > foo
  $ hg commit -A -m initial
  adding foo

That results in a row being inserted into various tables

  $ sqlite3 .hg/store/db.sqlite -init /dev/null << EOF
  > SELECT * FROM filepath;
  > EOF
  1|foo

  $ sqlite3 .hg/store/db.sqlite -init /dev/null << EOF
  > SELECT * FROM fileindex;
  > EOF
  1|1|0|-1|-1|0|0|1||6/\xef(L\xe2\xca\x02\xae\xcc\x8d\xe6\xd5\xe8\xa1\xc3\xaf\x05V\xfe (esc)

  $ sqlite3 .hg/store/db.sqlite -init /dev/null << EOF
  > SELECT * FROM delta;
  > EOF
  1|1|	\xd2\xaf\x8d\xd2"\x01\xdd\x8dH\xe5\xdc\xfc\xae\xd2\x81\xff\x94"\xc7|0 (esc)
  

Tracking multiple files works

  $ echo 1 > bar
  $ hg commit -A -m 'add bar'
  adding bar

  $ sqlite3 .hg/store/db.sqlite -init /dev/null << EOF
  > SELECT * FROM filedata ORDER BY id ASC;
  > EOF
  1|1|foo|0|6/\xef(L\xe2\xca\x02\xae\xcc\x8d\xe6\xd5\xe8\xa1\xc3\xaf\x05V\xfe|-1|-1|0|0|1| (esc)
  2|2|bar|0|\xb8\xe0/d3s\x80!\xa0e\xf9Au\xc7\xcd#\xdb_\x05\xbe|-1|-1|1|0|2| (esc)

Multiple revisions of a file works

  $ echo a >> foo
  $ hg commit -m 'modify foo'

  $ sqlite3 .hg/store/db.sqlite -init /dev/null << EOF
  > SELECT * FROM filedata ORDER BY id ASC;
  > EOF
  1|1|foo|0|6/\xef(L\xe2\xca\x02\xae\xcc\x8d\xe6\xd5\xe8\xa1\xc3\xaf\x05V\xfe|-1|-1|0|0|1| (esc)
  2|2|bar|0|\xb8\xe0/d3s\x80!\xa0e\xf9Au\xc7\xcd#\xdb_\x05\xbe|-1|-1|1|0|2| (esc)
  3|1|foo|1|\xdd\xb3V\xcd\xde1p@\xf7\x8e\x90\xb8*\x8b,\xe9\x0e\xd6j+|0|-1|2|0|3|1 (esc)

  $ cd ..

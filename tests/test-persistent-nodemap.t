===================================
Test the persistent on-disk nodemap
===================================


  $ cat << EOF >> $HGRCPATH
  > [format]
  > use-share-safe=yes
  > [extensions]
  > share=
  > EOF

#if no-rust

  $ cat << EOF >> $HGRCPATH
  > [format]
  > use-persistent-nodemap=yes
  > [devel]
  > persistent-nodemap=yes
  > EOF

#endif

  $ hg init test-repo --config storage.revlog.persistent-nodemap.slow-path=allow
  $ cd test-repo

Check handling of the default slow-path value

#if no-pure no-rust

  $ hg id
  abort: accessing `persistent-nodemap` repository without associated fast implementation.
  (check `hg help config.format.use-persistent-nodemap` for details)
  [255]

Unlock further check (we are here to test the feature)

  $ cat << EOF >> $HGRCPATH
  > [storage]
  > # to avoid spamming the test
  > revlog.persistent-nodemap.slow-path=allow
  > EOF

#endif

#if rust

Regression test for a previous bug in Rust/C FFI for the `Revlog_CAPI` capsule:
in places where `mercurial/cext/revlog.c` function signatures use `Py_ssize_t`
(64 bits on Linux x86_64), corresponding declarations in `rust/hg-cpython/src/cindex.rs`
incorrectly used `libc::c_int` (32 bits).
As a result, -1 passed from Rust for the null revision became 4294967295 in C.

  $ hg log -r 00000000
  changeset:   -1:000000000000
  tag:         tip
  user:        
  date:        Thu Jan 01 00:00:00 1970 +0000
  

#endif


  $ hg debugformat
  format-variant     repo
  fncache:            yes
  dirstate-v2:         no
  tracked-hint:        no
  dotencode:          yes
  generaldelta:       yes
  share-safe:         yes
  sparserevlog:       yes
  persistent-nodemap: yes
  copies-sdc:          no
  revlog-v2:           no
  changelog-v2:        no
  plain-cl-delta:     yes
  compression:        zlib (no-zstd !)
  compression:        zstd (zstd !)
  compression-level:  default
  $ hg debugbuilddag .+5000 --new-file

  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5000
  tip-node: 6b02b8c7b96654c25e86ba69eda198d7e6ad8b3c
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
  $ f --size .hg/store/00changelog.n
  .hg/store/00changelog.n: size=62

Simple lookup works

  $ ANYNODE=`hg log --template '{node|short}\n' --rev tip`
  $ hg log -r "$ANYNODE" --template '{rev}\n'
  5000


#if rust

  $ f --sha256 .hg/store/00changelog-*.nd
  .hg/store/00changelog-????????.nd: sha256=2e029d3200bd1a986b32784fc2ef1a3bd60dc331f025718bcf5ff44d93f026fd (glob)

  $ f --sha256 .hg/store/00manifest-*.nd
  .hg/store/00manifest-????????.nd: sha256=97117b1c064ea2f86664a124589e47db0e254e8d34739b5c5cc5bf31c9da2b51 (glob)
  $ hg debugnodemap --dump-new | f --sha256 --size
  size=121088, sha256=2e029d3200bd1a986b32784fc2ef1a3bd60dc331f025718bcf5ff44d93f026fd
  $ hg debugnodemap --dump-disk | f --sha256 --bytes=256 --hexdump --size
  size=121088, sha256=2e029d3200bd1a986b32784fc2ef1a3bd60dc331f025718bcf5ff44d93f026fd
  0000: 00 00 00 91 00 00 00 20 00 00 00 bb 00 00 00 e7 |....... ........|
  0010: 00 00 00 66 00 00 00 a1 00 00 01 13 00 00 01 22 |...f..........."|
  0020: 00 00 00 23 00 00 00 fc 00 00 00 ba 00 00 00 5e |...#...........^|
  0030: 00 00 00 df 00 00 01 4e 00 00 01 65 00 00 00 ab |.......N...e....|
  0040: 00 00 00 a9 00 00 00 95 00 00 00 73 00 00 00 38 |...........s...8|
  0050: 00 00 00 cc 00 00 00 92 00 00 00 90 00 00 00 69 |...............i|
  0060: 00 00 00 ec 00 00 00 8d 00 00 01 4f 00 00 00 12 |...........O....|
  0070: 00 00 02 0c 00 00 00 77 00 00 00 9c 00 00 00 8f |.......w........|
  0080: 00 00 00 d5 00 00 00 6b 00 00 00 48 00 00 00 b3 |.......k...H....|
  0090: 00 00 00 e5 00 00 00 b5 00 00 00 8e 00 00 00 ad |................|
  00a0: 00 00 00 7b 00 00 00 7c 00 00 00 0b 00 00 00 2b |...{...|.......+|
  00b0: 00 00 00 c6 00 00 00 1e 00 00 01 08 00 00 00 11 |................|
  00c0: 00 00 01 30 00 00 00 26 00 00 01 9c 00 00 00 35 |...0...&.......5|
  00d0: 00 00 00 b8 00 00 01 31 00 00 00 2c 00 00 00 55 |.......1...,...U|
  00e0: 00 00 00 8a 00 00 00 9a 00 00 00 0c 00 00 01 1e |................|
  00f0: 00 00 00 a4 00 00 00 83 00 00 00 c9 00 00 00 8c |................|


#else

  $ f --sha256 .hg/store/00changelog-*.nd
  .hg/store/00changelog-????????.nd: sha256=f544f5462ff46097432caf6d764091f6d8c46d6121be315ead8576d548c9dd79 (glob)
  $ hg debugnodemap --dump-new | f --sha256 --size
  size=121088, sha256=f544f5462ff46097432caf6d764091f6d8c46d6121be315ead8576d548c9dd79
  $ hg debugnodemap --dump-disk | f --sha256 --bytes=256 --hexdump --size
  size=121088, sha256=f544f5462ff46097432caf6d764091f6d8c46d6121be315ead8576d548c9dd79
  0000: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0010: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0020: ff ff ff ff ff ff f5 06 ff ff ff ff ff ff f3 e7 |................|
  0030: ff ff ef ca ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0040: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0050: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ed 08 |................|
  0060: ff ff ed 66 ff ff ff ff ff ff ff ff ff ff ff ff |...f............|
  0070: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0080: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  0090: ff ff ff ff ff ff ff ff ff ff ff ff ff ff f6 ed |................|
  00a0: ff ff ff ff ff ff fe 61 ff ff ff ff ff ff ff ff |.......a........|
  00b0: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  00c0: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  00d0: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff |................|
  00e0: ff ff ff ff ff ff ff ff ff ff ff ff ff ff f1 02 |................|
  00f0: ff ff ff ff ff ff ed 1b ff ff ff ff ff ff ff ff |................|

#endif

  $ hg debugnodemap --check
  revision in index:   5001
  revision in nodemap: 5001

add a new commit

  $ hg up
  5001 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo foo > foo
  $ hg add foo


Check slow-path config value handling
-------------------------------------

#if no-pure no-rust

  $ hg id --config "storage.revlog.persistent-nodemap.slow-path=invalid-value"
  unknown value for config "storage.revlog.persistent-nodemap.slow-path": "invalid-value"
  falling back to default value: abort
  abort: accessing `persistent-nodemap` repository without associated fast implementation.
  (check `hg help config.format.use-persistent-nodemap` for details)
  [255]

  $ hg log -r . --config "storage.revlog.persistent-nodemap.slow-path=warn"
  warning: accessing `persistent-nodemap` repository without associated fast implementation.
  (check `hg help config.format.use-persistent-nodemap` for details)
  changeset:   5000:6b02b8c7b966
  tag:         tip
  user:        debugbuilddag
  date:        Thu Jan 01 01:23:20 1970 +0000
  summary:     r5000
  
  $ hg ci -m 'foo' --config "storage.revlog.persistent-nodemap.slow-path=abort"
  abort: accessing `persistent-nodemap` repository without associated fast implementation.
  (check `hg help config.format.use-persistent-nodemap` for details)
  [255]

#else

  $ hg id --config "storage.revlog.persistent-nodemap.slow-path=invalid-value"
  unknown value for config "storage.revlog.persistent-nodemap.slow-path": "invalid-value"
  falling back to default value: abort
  6b02b8c7b966+ tip

#endif

  $ hg ci -m 'foo'

#if no-pure no-rust
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5001
  tip-node: 16395c3cf7e231394735e6b1717823ada303fb0c
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
#else
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5001
  tip-node: 16395c3cf7e231394735e6b1717823ada303fb0c
  data-length: 121344
  data-unused: 256
  data-unused: 0.211%
#endif

  $ f --size .hg/store/00changelog.n
  .hg/store/00changelog.n: size=62

(The pure code use the debug code that perform incremental update, the C code reencode from scratch)

#if pure
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????.nd: size=121344, sha256=cce54c5da5bde3ad72a4938673ed4064c86231b9c64376b082b163fdb20f8f66 (glob)
#endif

#if rust
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????.nd: size=121344, sha256=952b042fcf614ceb37b542b1b723e04f18f83efe99bee4e0f5ccd232ef470e58 (glob)
#endif

#if no-pure no-rust
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????.nd: size=121088, sha256=df7c06a035b96cb28c7287d349d603baef43240be7736fe34eea419a49702e17 (glob)
#endif

  $ hg debugnodemap --check
  revision in index:   5002
  revision in nodemap: 5002

Test code path without mmap
---------------------------

  $ echo bar > bar
  $ hg add bar
  $ hg ci -m 'bar' --config storage.revlog.persistent-nodemap.mmap=no

  $ hg debugnodemap --check --config storage.revlog.persistent-nodemap.mmap=yes
  revision in index:   5003
  revision in nodemap: 5003
  $ hg debugnodemap --check --config storage.revlog.persistent-nodemap.mmap=no
  revision in index:   5003
  revision in nodemap: 5003


#if pure
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5002
  tip-node: 880b18d239dfa9f632413a2071bfdbcc4806a4fd
  data-length: 121600
  data-unused: 512
  data-unused: 0.421%
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????.nd: size=121600, sha256=def52503d049ccb823974af313a98a935319ba61f40f3aa06a8be4d35c215054 (glob)
#endif
#if rust
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5002
  tip-node: 880b18d239dfa9f632413a2071bfdbcc4806a4fd
  data-length: 121600
  data-unused: 512
  data-unused: 0.421%
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????.nd: size=121600, sha256=dacf5b5f1d4585fee7527d0e67cad5b1ba0930e6a0928f650f779aefb04ce3fb (glob)
#endif
#if no-pure no-rust
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5002
  tip-node: 880b18d239dfa9f632413a2071bfdbcc4806a4fd
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
  $ f --sha256 .hg/store/00changelog-*.nd --size
  .hg/store/00changelog-????????.nd: size=121088, sha256=59fcede3e3cc587755916ceed29e3c33748cd1aa7d2f91828ac83e7979d935e8 (glob)
#endif

Test force warming the cache

  $ rm .hg/store/00changelog.n
  $ hg debugnodemap --metadata
  $ hg debugupdatecache
#if pure
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5002
  tip-node: 880b18d239dfa9f632413a2071bfdbcc4806a4fd
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
#else
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5002
  tip-node: 880b18d239dfa9f632413a2071bfdbcc4806a4fd
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
#endif

Check out of sync nodemap
=========================

First copy old data on the side.

  $ mkdir ../tmp-copies
  $ cp .hg/store/00changelog-????????.nd .hg/store/00changelog.n ../tmp-copies

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
  uid: ???????? (glob)
  tip-rev: 5003
  tip-node: c9329770f979ade2d16912267c38ba5f82fd37b3
  data-length: 121344 (pure !)
  data-length: 121344 (rust !)
  data-length: 121152 (no-rust no-pure !)
  data-unused: 192 (pure !)
  data-unused: 192 (rust !)
  data-unused: 0 (no-rust no-pure !)
  data-unused: 0.158% (pure !)
  data-unused: 0.158% (rust !)
  data-unused: 0.000% (no-rust no-pure !)
  $ cp -f ../tmp-copies/* .hg/store/
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5002
  tip-node: 880b18d239dfa9f632413a2071bfdbcc4806a4fd
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
  $ hg log -r "$NODE" -T '{rev}\n'
  5003

changelog altered
-----------------

If the nodemap is not gated behind a requirements, an unaware client can alter
the repository so the revlog used to generate the nodemap is not longer
compatible with the persistent nodemap. We need to detect that.

  $ hg up "$NODE~5"
  0 files updated, 0 files merged, 4 files removed, 0 files unresolved
  $ echo bar > babar
  $ hg add babar
  $ hg ci -m 'babar'
  created new head
  $ OTHERNODE=`hg log -r tip -T '{node}\n'`
  $ hg log -r "$OTHERNODE" -T '{rev}\n'
  5004

  $ hg --config extensions.strip= strip --rev "$NODE~1" --no-backup

the nodemap should detect the changelog have been tampered with and recover.

  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5002
  tip-node: b355ef8adce0949b8bdf6afc72ca853740d65944
  data-length: 121536 (pure !)
  data-length: 121088 (rust !)
  data-length: 121088 (no-pure no-rust !)
  data-unused: 448 (pure !)
  data-unused: 0 (rust !)
  data-unused: 0 (no-pure no-rust !)
  data-unused: 0.000% (rust !)
  data-unused: 0.369% (pure !)
  data-unused: 0.000% (no-pure no-rust !)

  $ cp -f ../tmp-copies/* .hg/store/
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5002
  tip-node: 880b18d239dfa9f632413a2071bfdbcc4806a4fd
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
  $ hg log -r "$OTHERNODE" -T '{rev}\n'
  5002

missing data file
-----------------

  $ UUID=`hg debugnodemap --metadata| grep 'uid:' | \
  > sed 's/uid: //'`
  $ FILE=.hg/store/00changelog-"${UUID}".nd
  $ mv $FILE ../tmp-data-file
  $ cp .hg/store/00changelog.n ../tmp-docket

mercurial don't crash

  $ hg log -r .
  changeset:   5002:b355ef8adce0
  tag:         tip
  parent:      4998:d918ad6d18d3
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     babar
  
  $ hg debugnodemap --metadata

  $ hg debugupdatecache
  $ hg debugnodemap --metadata
  uid: * (glob)
  tip-rev: 5002
  tip-node: b355ef8adce0949b8bdf6afc72ca853740d65944
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
  $ mv ../tmp-data-file $FILE
  $ mv ../tmp-docket .hg/store/00changelog.n

Check transaction related property
==================================

An up to date nodemap should be available to shell hooks,

  $ echo dsljfl > a
  $ hg add a
  $ hg ci -m a
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5003
  tip-node: a52c5079765b5865d97b993b303a18740113bbb2
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
  $ echo babar2 > babar
  $ hg ci -m 'babar2' --config "hooks.pretxnclose.nodemap-test=hg debugnodemap --metadata"
  uid: ???????? (glob)
  tip-rev: 5004
  tip-node: 2f5fb1c06a16834c5679d672e90da7c5f3b1a984
  data-length: 121280 (pure !)
  data-length: 121280 (rust !)
  data-length: 121088 (no-pure no-rust !)
  data-unused: 192 (pure !)
  data-unused: 192 (rust !)
  data-unused: 0 (no-pure no-rust !)
  data-unused: 0.158% (pure !)
  data-unused: 0.158% (rust !)
  data-unused: 0.000% (no-pure no-rust !)
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5004
  tip-node: 2f5fb1c06a16834c5679d672e90da7c5f3b1a984
  data-length: 121280 (pure !)
  data-length: 121280 (rust !)
  data-length: 121088 (no-pure no-rust !)
  data-unused: 192 (pure !)
  data-unused: 192 (rust !)
  data-unused: 0 (no-pure no-rust !)
  data-unused: 0.158% (pure !)
  data-unused: 0.158% (rust !)
  data-unused: 0.000% (no-pure no-rust !)

Another process does not see the pending nodemap content during run.

  $ echo qpoasp > a
  $ hg ci -m a2 \
  > --config "hooks.pretxnclose=sh \"$RUNTESTDIR/testlib/wait-on-file\" 20 sync-repo-read sync-txn-pending" \
  > --config "hooks.txnclose=touch sync-txn-close" > output.txt 2>&1 &

(read the repository while the commit transaction is pending)

  $ sh "$RUNTESTDIR/testlib/wait-on-file" 20 sync-txn-pending && \
  > hg debugnodemap --metadata && \
  > sh "$RUNTESTDIR/testlib/wait-on-file" 20 sync-txn-close sync-repo-read
  uid: ???????? (glob)
  tip-rev: 5004
  tip-node: 2f5fb1c06a16834c5679d672e90da7c5f3b1a984
  data-length: 121280 (pure !)
  data-length: 121280 (rust !)
  data-length: 121088 (no-pure no-rust !)
  data-unused: 192 (pure !)
  data-unused: 192 (rust !)
  data-unused: 0 (no-pure no-rust !)
  data-unused: 0.158% (pure !)
  data-unused: 0.158% (rust !)
  data-unused: 0.000% (no-pure no-rust !)
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121536 (pure !)
  data-length: 121536 (rust !)
  data-length: 121088 (no-pure no-rust !)
  data-unused: 448 (pure !)
  data-unused: 448 (rust !)
  data-unused: 0 (no-pure no-rust !)
  data-unused: 0.369% (pure !)
  data-unused: 0.369% (rust !)
  data-unused: 0.000% (no-pure no-rust !)

  $ cat output.txt

Check that a failing transaction will properly revert the data

  $ echo plakfe > a
  $ f --size --sha256 .hg/store/00changelog-*.nd
  .hg/store/00changelog-????????.nd: size=121536, sha256=bb414468d225cf52d69132e1237afba34d4346ee2eb81b505027e6197b107f03 (glob) (pure !)
  .hg/store/00changelog-????????.nd: size=121536, sha256=909ac727bc4d1c0fda5f7bff3c620c98bd4a2967c143405a1503439e33b377da (glob) (rust !)
  .hg/store/00changelog-????????.nd: size=121088, sha256=342d36d30d86dde67d3cb6c002606c4a75bcad665595d941493845066d9c8ee0 (glob) (no-pure no-rust !)
  $ hg ci -m a3 --config "extensions.abort=$RUNTESTDIR/testlib/crash_transaction_late.py"
  transaction abort!
  rollback completed
  abort: This is a late abort
  [255]
  $ hg debugnodemap --metadata
  uid: ???????? (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121536 (pure !)
  data-length: 121536 (rust !)
  data-length: 121088 (no-pure no-rust !)
  data-unused: 448 (pure !)
  data-unused: 448 (rust !)
  data-unused: 0 (no-pure no-rust !)
  data-unused: 0.369% (pure !)
  data-unused: 0.369% (rust !)
  data-unused: 0.000% (no-pure no-rust !)
  $ f --size --sha256 .hg/store/00changelog-*.nd
  .hg/store/00changelog-????????.nd: size=121536, sha256=bb414468d225cf52d69132e1237afba34d4346ee2eb81b505027e6197b107f03 (glob) (pure !)
  .hg/store/00changelog-????????.nd: size=121536, sha256=909ac727bc4d1c0fda5f7bff3c620c98bd4a2967c143405a1503439e33b377da (glob) (rust !)
  .hg/store/00changelog-????????.nd: size=121088, sha256=342d36d30d86dde67d3cb6c002606c4a75bcad665595d941493845066d9c8ee0 (glob) (no-pure no-rust !)

Check that removing content does not confuse the nodemap
--------------------------------------------------------

removing data with rollback

  $ echo aso > a
  $ hg ci -m a4
  $ hg rollback
  repository tip rolled back to revision 5005 (undo commit)
  working directory now based on revision 5005
  $ hg id -r .
  90d5d3ba2fc4 tip

removing data with strip

  $ echo aso > a
  $ hg ci -m a4
  $ hg --config extensions.strip= strip -r . --no-backup
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg id -r . --traceback
  90d5d3ba2fc4 tip

(be a good citizen and regenerate the nodemap)
  $ hg debugupdatecaches
  $ hg debugnodemap --metadata
  uid: * (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%

Check race condition when multiple process write new data to the repository
---------------------------------------------------------------------------

In this test, we check that two writers touching the repositories will not
overwrite each other data. This test is prompted by the existent of issue6554.
Where a writer ended up using and outdated docket to update the repository. See
the dedicated extension for details on the race windows and read/write schedule
necessary to end up in this situation: testlib/persistent-nodemap-race-ext.py

The issue was initially observed on a server with a high push trafic, but it
can be reproduced using a share and two commiting process which seems simpler.

The test is Rust only as the other implementation does not use the same
read/write patterns.

  $ cd ..

#if rust

  $ cp -R test-repo race-repo
  $ hg share race-repo ./other-wc --config format.use-share-safe=yes
  updating working directory
  5001 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugformat -R ./race-repo | egrep 'share-safe|persistent-nodemap'
  share-safe:         yes
  persistent-nodemap: yes
  $ hg debugformat -R ./other-wc/ | egrep 'share-safe|persistent-nodemap'
  share-safe:         yes
  persistent-nodemap: yes
  $ hg -R ./other-wc update 'min(head())'
  3 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg -R ./race-repo debugnodemap --metadata
  uid: 43c37dde
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%
  $ hg -R ./race-repo log -G -r 'head()'
  @  changeset:   5005:90d5d3ba2fc4
  |  tag:         tip
  ~  user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     a2
  
  o  changeset:   5001:16395c3cf7e2
  |  user:        test
  ~  date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     foo
  
  $ hg -R ./other-wc log -G -r 'head()'
  o  changeset:   5005:90d5d3ba2fc4
  |  tag:         tip
  ~  user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     a2
  
  @  changeset:   5001:16395c3cf7e2
  |  user:        test
  ~  date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     foo
  
  $ echo left-side-race > race-repo/left-side-race
  $ hg -R ./race-repo/ add race-repo/left-side-race

  $ echo right-side-race > ./other-wc/right-side-race
  $ hg -R ./other-wc/ add ./other-wc/right-side-race

  $ mkdir sync-files
  $ mkdir outputs
  $ (
  >    hg -R ./race-repo/ commit -m left-side-commit \
  >    --config "extensions.race=${RUNTESTDIR}/testlib/persistent-nodemap-race-ext.py" \
  >    --config 'devel.nodemap-race.role=left';
  >    touch sync-files/left-done
  > ) > outputs/left.txt 2>&1 &
  $ (
  >    hg -R ./other-wc/ commit -m right-side-commit \
  >    --config "extensions.race=${RUNTESTDIR}/testlib/persistent-nodemap-race-ext.py" \
  >    --config 'devel.nodemap-race.role=right';
  >    touch sync-files/right-done
  > ) > outputs/right.txt 2>&1 &
  $ (
  >    hg -R ./race-repo/ check-nodemap-race \
  >    --config "extensions.race=${RUNTESTDIR}/testlib/persistent-nodemap-race-ext.py" \
  >    --config 'devel.nodemap-race.role=reader';
  >    touch sync-files/reader-done
  > ) > outputs/reader.txt 2>&1 &
  $ sh "$RUNTESTDIR"/testlib/wait-on-file 10 sync-files/left-done
  $ cat outputs/left.txt
  docket-details:
    uid:         43c37dde
    actual-tip:  5005
    tip-rev:     5005
    data-length: 121088
  nodemap-race: left side locked and ready to commit
  docket-details:
    uid:         43c37dde
    actual-tip:  5005
    tip-rev:     5005
    data-length: 121088
  finalized changelog write
  persisting changelog nodemap
    new data start at 121088
  persisted changelog nodemap
  docket-details:
    uid:         43c37dde
    actual-tip:  5006
    tip-rev:     5006
    data-length: 121280
  $ sh "$RUNTESTDIR"/testlib/wait-on-file 10 sync-files/right-done
  $ cat outputs/right.txt
  nodemap-race: right side start of the locking sequence
  nodemap-race: right side reading changelog
  nodemap-race: right side reading of changelog is done
  docket-details:
    uid:         43c37dde
    actual-tip:  5006
    tip-rev:     5005
    data-length: 121088
  nodemap-race: right side ready to wait for the lock
  nodemap-race: right side locked and ready to commit
  docket-details:
    uid:         43c37dde
    actual-tip:  5006
    tip-rev:     5006
    data-length: 121280
  right ready to write, waiting for reader
  right proceeding with writing its changelog index and nodemap
  finalized changelog write
  persisting changelog nodemap
    new data start at 121280
  persisted changelog nodemap
  docket-details:
    uid:         43c37dde
    actual-tip:  5007
    tip-rev:     5007
    data-length: 121536
  $ sh "$RUNTESTDIR"/testlib/wait-on-file 10 sync-files/reader-done
  $ cat outputs/reader.txt
  reader: reading changelog
  reader ready to read the changelog, waiting for right
  reader: nodemap docket read
  record-data-length: 121280
  actual-data-length: 121280
  file-actual-length: 121536
  reader: changelog read
  docket-details:
    uid:         43c37dde
    actual-tip:  5006
    tip-rev:     5006
    data-length: 121280
  tip-rev:  5006
  tip-node: 492901161367
  node-rev: 5006

  $ hg -R ./race-repo log -G -r 'head()'
  o  changeset:   5007:ac4a2abde241
  |  tag:         tip
  ~  parent:      5001:16395c3cf7e2
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     right-side-commit
  
  @  changeset:   5006:492901161367
  |  user:        test
  ~  date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     left-side-commit
  
  $ hg -R ./other-wc log -G -r 'head()'
  @  changeset:   5007:ac4a2abde241
  |  tag:         tip
  ~  parent:      5001:16395c3cf7e2
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     right-side-commit
  
  o  changeset:   5006:492901161367
  |  user:        test
  ~  date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     left-side-commit
  
#endif

Test upgrade / downgrade
========================

  $ cd ./test-repo/

downgrading

  $ cat << EOF >> .hg/hgrc
  > [format]
  > use-persistent-nodemap=no
  > EOF
  $ hg debugformat -v
  format-variant     repo config default
  fncache:            yes    yes     yes
  dirstate-v2:         no     no      no
  tracked-hint:        no     no      no
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:         yes    yes     yes
  sparserevlog:       yes    yes     yes
  persistent-nodemap: yes     no      no
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zstd   zstd    zstd (zstd !)
  compression-level:  default default default
  $ hg debugupgraderepo --run --no-backup --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, share-safe, sparserevlog, store (no-zstd no-dirstate-v2 !)
     preserved: dotencode, fncache, generaldelta, revlog-compression-zstd, revlogv1, share-safe, sparserevlog, store (zstd no-dirstate-v2 !)
     preserved: dotencode, use-dirstate-v2, fncache, generaldelta, revlog-compression-zstd, revlogv1, share-safe, sparserevlog, store (zstd dirstate-v2 !)
     removed: persistent-nodemap
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ ls -1 .hg/store/ | egrep '00(changelog|manifest)(\.n|-.*\.nd)'
  undo.backup.00changelog.n
  undo.backup.00manifest.n
  $ hg debugnodemap --metadata


upgrading

  $ cat << EOF >> .hg/hgrc
  > [format]
  > use-persistent-nodemap=yes
  > EOF
  $ hg debugformat -v
  format-variant     repo config default
  fncache:            yes    yes     yes
  dirstate-v2:         no     no      no
  tracked-hint:        no     no      no
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:         yes    yes     yes
  sparserevlog:       yes    yes     yes
  persistent-nodemap:  no    yes      no
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zstd   zstd    zstd (zstd !)
  compression-level:  default default default
  $ hg debugupgraderepo --run --no-backup --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, share-safe, sparserevlog, store (no-zstd no-dirstate-v2 !)
     preserved: dotencode, fncache, generaldelta, revlog-compression-zstd, revlogv1, share-safe, sparserevlog, store (zstd no-dirstate-v2 !)
     preserved: dotencode, use-dirstate-v2, fncache, generaldelta, revlog-compression-zstd, revlogv1, share-safe, sparserevlog, store (zstd dirstate-v2 !)
     added: persistent-nodemap
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ ls -1 .hg/store/ | egrep '00(changelog|manifest)(\.n|-.*\.nd)'
  00changelog-*.nd (glob)
  00changelog.n
  00manifest-*.nd (glob)
  00manifest.n
  undo.backup.00changelog.n
  undo.backup.00manifest.n

  $ hg debugnodemap --metadata
  uid: * (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%

Running unrelated upgrade

  $ hg debugupgraderepo --run --no-backup --quiet --optimize re-delta-all
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, share-safe, sparserevlog, store (no-zstd no-dirstate-v2 !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlog-compression-zstd, revlogv1, share-safe, sparserevlog, store (zstd no-dirstate-v2 !)
     preserved: dotencode, use-dirstate-v2, fncache, generaldelta, persistent-nodemap, revlog-compression-zstd, revlogv1, share-safe, sparserevlog, store (zstd dirstate-v2 !)
  
  optimisations: re-delta-all
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ ls -1 .hg/store/ | egrep '00(changelog|manifest)(\.n|-.*\.nd)'
  00changelog-*.nd (glob)
  00changelog.n
  00manifest-*.nd (glob)
  00manifest.n

  $ hg debugnodemap --metadata
  uid: * (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%

Persistent nodemap and local/streaming clone
============================================

  $ cd ..

standard clone
--------------

The persistent nodemap should exist after a streaming clone

  $ hg clone --pull --quiet -U test-repo standard-clone
  $ ls -1 standard-clone/.hg/store/ | egrep '00(changelog|manifest)(\.n|-.*\.nd)'
  00changelog-*.nd (glob)
  00changelog.n
  00manifest-*.nd (glob)
  00manifest.n
  $ hg -R standard-clone debugnodemap --metadata
  uid: * (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%


local clone
------------

The persistent nodemap should exist after a streaming clone

  $ hg clone -U test-repo local-clone
  $ ls -1 local-clone/.hg/store/ | egrep '00(changelog|manifest)(\.n|-.*\.nd)'
  00changelog-*.nd (glob)
  00changelog.n
  00manifest-*.nd (glob)
  00manifest.n
  $ hg -R local-clone debugnodemap --metadata
  uid: * (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%

Test various corruption case
============================

Missing datafile
----------------

Test behavior with a missing datafile

  $ hg clone --quiet --pull test-repo corruption-test-repo
  $ ls -1 corruption-test-repo/.hg/store/00changelog*
  corruption-test-repo/.hg/store/00changelog-*.nd (glob)
  corruption-test-repo/.hg/store/00changelog.d
  corruption-test-repo/.hg/store/00changelog.i
  corruption-test-repo/.hg/store/00changelog.n
  $ rm corruption-test-repo/.hg/store/00changelog*.nd
  $ hg log -R corruption-test-repo -r .
  changeset:   5005:90d5d3ba2fc4
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     a2
  
  $ ls -1 corruption-test-repo/.hg/store/00changelog*
  corruption-test-repo/.hg/store/00changelog.d
  corruption-test-repo/.hg/store/00changelog.i
  corruption-test-repo/.hg/store/00changelog.n

Truncated data file
-------------------

Test behavior with a too short datafile

rebuild the missing data
  $ hg -R corruption-test-repo debugupdatecache
  $ ls -1 corruption-test-repo/.hg/store/00changelog*
  corruption-test-repo/.hg/store/00changelog-*.nd (glob)
  corruption-test-repo/.hg/store/00changelog.d
  corruption-test-repo/.hg/store/00changelog.i
  corruption-test-repo/.hg/store/00changelog.n

truncate the file

  $ datafilepath=`ls corruption-test-repo/.hg/store/00changelog*.nd`
  $ f -s $datafilepath
  corruption-test-repo/.hg/store/00changelog-*.nd: size=121088 (glob)
  $ dd if=$datafilepath bs=1000 count=10 of=$datafilepath-tmp
  10+0 records in
  10+0 records out
  * bytes * (glob)
  $ mv $datafilepath-tmp $datafilepath
  $ f -s $datafilepath
  corruption-test-repo/.hg/store/00changelog-*.nd: size=10000 (glob)

Check that Mercurial reaction to this event

  $ hg -R corruption-test-repo log -r . --traceback
  changeset:   5005:90d5d3ba2fc4
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     a2
  


stream clone
============

The persistent nodemap should exist after a streaming clone

Simple case
-----------

No race condition

  $ hg clone -U --stream ssh://user@dummy/test-repo stream-clone --debug | egrep '00(changelog|manifest)'
  adding [s] 00manifest.n (62 bytes)
  adding [s] 00manifest-*.nd (118 KB) (glob)
  adding [s] 00changelog.n (62 bytes)
  adding [s] 00changelog-*.nd (118 KB) (glob)
  adding [s] 00manifest.d (452 KB) (no-zstd !)
  adding [s] 00manifest.d (491 KB) (zstd no-bigendian !)
  adding [s] 00manifest.d (492 KB) (zstd bigendian !)
  adding [s] 00changelog.d (360 KB) (no-zstd !)
  adding [s] 00changelog.d (368 KB) (zstd !)
  adding [s] 00manifest.i (313 KB)
  adding [s] 00changelog.i (313 KB)
  $ ls -1 stream-clone/.hg/store/ | egrep '00(changelog|manifest)(\.n|-.*\.nd)'
  00changelog-*.nd (glob)
  00changelog.n
  00manifest-*.nd (glob)
  00manifest.n
  $ hg -R stream-clone debugnodemap --metadata
  uid: * (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%

new data appened
-----------------

Other commit happening on the server during the stream clone

setup the step-by-step stream cloning

  $ HG_TEST_STREAM_WALKED_FILE_1="$TESTTMP/sync_file_walked_1"
  $ export HG_TEST_STREAM_WALKED_FILE_1
  $ HG_TEST_STREAM_WALKED_FILE_2="$TESTTMP/sync_file_walked_2"
  $ export HG_TEST_STREAM_WALKED_FILE_2
  $ HG_TEST_STREAM_WALKED_FILE_3="$TESTTMP/sync_file_walked_3"
  $ export HG_TEST_STREAM_WALKED_FILE_3
  $ cat << EOF >> test-repo/.hg/hgrc
  > [extensions]
  > steps=$RUNTESTDIR/testlib/ext-stream-clone-steps.py
  > EOF

Check and record file state beforehand

  $ f --size test-repo/.hg/store/00changelog*
  test-repo/.hg/store/00changelog-*.nd: size=121088 (glob)
  test-repo/.hg/store/00changelog.d: size=376891 (zstd no-bigendian !)
  test-repo/.hg/store/00changelog.d: size=376889 (zstd bigendian !)
  test-repo/.hg/store/00changelog.d: size=368890 (no-zstd !)
  test-repo/.hg/store/00changelog.i: size=320384
  test-repo/.hg/store/00changelog.n: size=62
  $ hg -R test-repo debugnodemap --metadata | tee server-metadata.txt
  uid: * (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%

Prepare a commit

  $ echo foo >> test-repo/foo
  $ hg -R test-repo/ add test-repo/foo

Do a mix of clone and commit at the same time so that the file listed on disk differ at actual transfer time.

  $ (hg clone -U --stream ssh://user@dummy/test-repo stream-clone-race-1 --debug 2>> clone-output | egrep '00(changelog|manifest)' >> clone-output; touch $HG_TEST_STREAM_WALKED_FILE_3) &
  $ $RUNTESTDIR/testlib/wait-on-file 10 $HG_TEST_STREAM_WALKED_FILE_1
  $ hg -R test-repo/ commit -m foo
  $ touch $HG_TEST_STREAM_WALKED_FILE_2
  $ $RUNTESTDIR/testlib/wait-on-file 10 $HG_TEST_STREAM_WALKED_FILE_3
  $ cat clone-output
  adding [s] 00manifest.n (62 bytes)
  adding [s] 00manifest-*.nd (118 KB) (glob)
  adding [s] 00changelog.n (62 bytes)
  adding [s] 00changelog-*.nd (118 KB) (glob)
  adding [s] 00manifest.d (452 KB) (no-zstd !)
  adding [s] 00manifest.d (491 KB) (zstd no-bigendian !)
  adding [s] 00manifest.d (492 KB) (zstd bigendian !)
  adding [s] 00changelog.d (360 KB) (no-zstd !)
  adding [s] 00changelog.d (368 KB) (zstd !)
  adding [s] 00manifest.i (313 KB)
  adding [s] 00changelog.i (313 KB)

Check the result state

  $ f --size stream-clone-race-1/.hg/store/00changelog*
  stream-clone-race-1/.hg/store/00changelog-*.nd: size=121088 (glob)
  stream-clone-race-1/.hg/store/00changelog.d: size=368890 (no-zstd !)
  stream-clone-race-1/.hg/store/00changelog.d: size=376891 (zstd no-bigendian !)
  stream-clone-race-1/.hg/store/00changelog.d: size=376889 (zstd bigendian !)
  stream-clone-race-1/.hg/store/00changelog.i: size=320384
  stream-clone-race-1/.hg/store/00changelog.n: size=62

  $ hg -R stream-clone-race-1 debugnodemap --metadata | tee client-metadata.txt
  uid: * (glob)
  tip-rev: 5005
  tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
  data-length: 121088
  data-unused: 0
  data-unused: 0.000%

We get a usable nodemap, so no rewrite would be needed and the metadata should be identical
(ie: the following diff should be empty)

This isn't the case for the `no-rust` `no-pure` implementation as it use a very minimal nodemap implementation that unconditionnaly rewrite the nodemap "all the time".

#if no-rust no-pure
  $ diff -u server-metadata.txt client-metadata.txt
  --- server-metadata.txt	* (glob)
  +++ client-metadata.txt	* (glob)
  @@ -1,4 +1,4 @@
  -uid: * (glob)
  +uid: * (glob)
   tip-rev: 5005
   tip-node: 90d5d3ba2fc47db50f712570487cb261a68c8ffe
   data-length: 121088
  [1]
#else
  $ diff -u server-metadata.txt client-metadata.txt
#endif


Clean up after the test.

  $ rm -f "$HG_TEST_STREAM_WALKED_FILE_1"
  $ rm -f "$HG_TEST_STREAM_WALKED_FILE_2"
  $ rm -f "$HG_TEST_STREAM_WALKED_FILE_3"

full regeneration
-----------------

A full nodemap is generated

(ideally this test would append enough data to make sure the nodemap data file
get changed, however to make thing simpler we will force the regeneration for
this test.

Check the initial state

  $ f --size test-repo/.hg/store/00changelog*
  test-repo/.hg/store/00changelog-*.nd: size=121344 (glob) (rust !)
  test-repo/.hg/store/00changelog-*.nd: size=121344 (glob) (pure !)
  test-repo/.hg/store/00changelog-*.nd: size=121152 (glob) (no-rust no-pure !)
  test-repo/.hg/store/00changelog.d: size=376950 (zstd no-bigendian !)
  test-repo/.hg/store/00changelog.d: size=376948 (zstd bigendian !)
  test-repo/.hg/store/00changelog.d: size=368949 (no-zstd !)
  test-repo/.hg/store/00changelog.i: size=320448
  test-repo/.hg/store/00changelog.n: size=62
  $ hg -R test-repo debugnodemap --metadata | tee server-metadata-2.txt
  uid: * (glob)
  tip-rev: 5006
  tip-node: ed2ec1eef9aa2a0ec5057c51483bc148d03e810b
  data-length: 121344 (rust !)
  data-length: 121344 (pure !)
  data-length: 121152 (no-rust no-pure !)
  data-unused: 192 (rust !)
  data-unused: 192 (pure !)
  data-unused: 0 (no-rust no-pure !)
  data-unused: 0.158% (rust !)
  data-unused: 0.158% (pure !)
  data-unused: 0.000% (no-rust no-pure !)

Performe the mix of clone and full refresh of the nodemap, so that the files
(and filenames) are different between listing time and actual transfer time.

  $ (hg clone -U --stream ssh://user@dummy/test-repo stream-clone-race-2 --debug 2>> clone-output-2 | egrep '00(changelog|manifest)' >> clone-output-2; touch $HG_TEST_STREAM_WALKED_FILE_3) &
  $ $RUNTESTDIR/testlib/wait-on-file 10 $HG_TEST_STREAM_WALKED_FILE_1
  $ rm test-repo/.hg/store/00changelog.n
  $ rm test-repo/.hg/store/00changelog-*.nd
  $ hg -R test-repo/ debugupdatecache
  $ touch $HG_TEST_STREAM_WALKED_FILE_2
  $ $RUNTESTDIR/testlib/wait-on-file 10 $HG_TEST_STREAM_WALKED_FILE_3

(note: the stream clone code wronly pick the `undo.` files)

  $ cat clone-output-2
  adding [s] undo.backup.00manifest.n (62 bytes) (known-bad-output !)
  adding [s] undo.backup.00changelog.n (62 bytes) (known-bad-output !)
  adding [s] 00manifest.n (62 bytes)
  adding [s] 00manifest-*.nd (118 KB) (glob)
  adding [s] 00changelog.n (62 bytes)
  adding [s] 00changelog-*.nd (118 KB) (glob)
  adding [s] 00manifest.d (492 KB) (zstd !)
  adding [s] 00manifest.d (452 KB) (no-zstd !)
  adding [s] 00changelog.d (360 KB) (no-zstd !)
  adding [s] 00changelog.d (368 KB) (zstd !)
  adding [s] 00manifest.i (313 KB)
  adding [s] 00changelog.i (313 KB)

Check the result.

  $ f --size stream-clone-race-2/.hg/store/00changelog*
  stream-clone-race-2/.hg/store/00changelog-*.nd: size=121344 (glob) (rust !)
  stream-clone-race-2/.hg/store/00changelog-*.nd: size=121344 (glob) (pure !)
  stream-clone-race-2/.hg/store/00changelog-*.nd: size=121152 (glob) (no-rust no-pure !)
  stream-clone-race-2/.hg/store/00changelog.d: size=376950 (zstd no-bigendian !)
  stream-clone-race-2/.hg/store/00changelog.d: size=376948 (zstd bigendian !)
  stream-clone-race-2/.hg/store/00changelog.d: size=368949 (no-zstd !)
  stream-clone-race-2/.hg/store/00changelog.i: size=320448
  stream-clone-race-2/.hg/store/00changelog.n: size=62

  $ hg -R stream-clone-race-2 debugnodemap --metadata | tee client-metadata-2.txt
  uid: * (glob)
  tip-rev: 5006
  tip-node: ed2ec1eef9aa2a0ec5057c51483bc148d03e810b
  data-length: 121344 (rust !)
  data-unused: 192 (rust !)
  data-unused: 0.158% (rust !)
  data-length: 121152 (no-rust no-pure !)
  data-unused: 0 (no-rust no-pure !)
  data-unused: 0.000% (no-rust no-pure !)
  data-length: 121344 (pure !)
  data-unused: 192 (pure !)
  data-unused: 0.158% (pure !)

We get a usable nodemap, so no rewrite would be needed and the metadata should be identical
(ie: the following diff should be empty)

This isn't the case for the `no-rust` `no-pure` implementation as it use a very minimal nodemap implementation that unconditionnaly rewrite the nodemap "all the time".

#if no-rust no-pure
  $ diff -u server-metadata-2.txt client-metadata-2.txt
  --- server-metadata-2.txt	* (glob)
  +++ client-metadata-2.txt	* (glob)
  @@ -1,4 +1,4 @@
  -uid: * (glob)
  +uid: * (glob)
   tip-rev: 5006
   tip-node: ed2ec1eef9aa2a0ec5057c51483bc148d03e810b
   data-length: 121152
  [1]
#else
  $ diff -u server-metadata-2.txt client-metadata-2.txt
#endif

Clean up after the test

  $ rm -f $HG_TEST_STREAM_WALKED_FILE_1
  $ rm -f $HG_TEST_STREAM_WALKED_FILE_2
  $ rm -f $HG_TEST_STREAM_WALKED_FILE_3


Source bundle was generated with the following script:

# hg init
# echo a > a
# ln -s a l
# hg ci -Ama -d'0 0'
# mkdir b
# echo a > b/a
# chmod +x b/a
# hg ci -Amb -d'1 0'

  $ hg init
  $ hg unbundle "$TESTDIR/bundles/test-manifest.hg"
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 3 changes to 3 files
  new changesets b73562a03cfe:5bdc995175ba (2 drafts)
  (run 'hg update' to get a working copy)

The next call is expected to return nothing:

  $ hg manifest

  $ hg co
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ hg manifest
  a
  b/a
  l

  $ hg files -vr .
           2   a
           2 x b/a
           1 l l
  $ hg files -r . -X b
  a
  l
  $ hg files -T '{path} {size} {flags}\n'
  a 2 
  b/a 2 x
  l 1 l
  $ hg files -T '{path} {node|shortest}\n' -r.
  a 5bdc
  b/a 5bdc
  l 5bdc

  $ hg manifest -v
  644   a
  755 * b/a
  644 @ l
  $ hg manifest -T '{path} {rev}\n'
  a 1
  b/a 1
  l 1

  $ hg manifest --debug
  b789fdd96dc2f3bd229c1dd8eedf0fc60e2b68e3 644   a
  b789fdd96dc2f3bd229c1dd8eedf0fc60e2b68e3 755 * b/a
  047b75c6d7a3ef6a2243bd0e99f94f6ea6683597 644 @ l

  $ hg manifest -r 0
  a
  l

  $ hg manifest -r 1
  a
  b/a
  l

  $ hg manifest -r tip
  a
  b/a
  l

  $ hg manifest tip
  a
  b/a
  l

  $ hg manifest --all
  a
  b/a
  l

The next two calls are expected to abort:

  $ hg manifest -r 2
  abort: unknown revision '2'
  [10]

  $ hg manifest -r tip tip
  abort: please specify just one revision
  [10]

Testing the manifest full text cache utility
--------------------------------------------

Reminder of the manifest log content

  $ hg log --debug | grep 'manifest:'
  manifest:    1:1e01206b1d2f72bd55f2a33fa8ccad74144825b7
  manifest:    0:fce2a30dedad1eef4da95ca1dc0004157aa527cf

Showing the content of the caches after the above operations

  $ hg debugmanifestfulltextcache
  cache contains 1 manifest entries, in order of most to least recent:
  id: 1e01206b1d2f72bd55f2a33fa8ccad74144825b7, size 133 bytes
  total cache data size 157 bytes, on-disk 157 bytes

(Clearing the cache in case of any content)

  $ hg debugmanifestfulltextcache --clear

Adding a new persistent entry in the cache

  $ hg debugmanifestfulltextcache --add 1e01206b1d2f72bd55f2a33fa8ccad74144825b7

  $ hg debugmanifestfulltextcache
  cache contains 1 manifest entries, in order of most to least recent:
  id: 1e01206b1d2f72bd55f2a33fa8ccad74144825b7, size 133 bytes
  total cache data size 157 bytes, on-disk 157 bytes

Check we don't duplicated entry (added from the debug command)

  $ hg debugmanifestfulltextcache --add 1e01206b1d2f72bd55f2a33fa8ccad74144825b7
  $ hg debugmanifestfulltextcache
  cache contains 1 manifest entries, in order of most to least recent:
  id: 1e01206b1d2f72bd55f2a33fa8ccad74144825b7, size 133 bytes
  total cache data size 157 bytes, on-disk 157 bytes

Adding a second entry

  $ hg debugmanifestfulltextcache --add fce2a30dedad1eef4da95ca1dc0004157aa527cf
  $ hg debugmanifestfulltextcache
  cache contains 2 manifest entries, in order of most to least recent:
  id: fce2a30dedad1eef4da95ca1dc0004157aa527cf, size 87 bytes
  id: 1e01206b1d2f72bd55f2a33fa8ccad74144825b7, size 133 bytes
  total cache data size 268 bytes, on-disk 268 bytes

Accessing the initial entry again, refresh their order

  $ hg debugmanifestfulltextcache --add 1e01206b1d2f72bd55f2a33fa8ccad74144825b7
  $ hg debugmanifestfulltextcache
  cache contains 2 manifest entries, in order of most to least recent:
  id: 1e01206b1d2f72bd55f2a33fa8ccad74144825b7, size 133 bytes
  id: fce2a30dedad1eef4da95ca1dc0004157aa527cf, size 87 bytes
  total cache data size 268 bytes, on-disk 268 bytes

Check cache clearing

  $ hg debugmanifestfulltextcache --clear
  $ hg debugmanifestfulltextcache
  cache empty

Check adding multiple entry in one go:

  $ hg debugmanifestfulltextcache --add fce2a30dedad1eef4da95ca1dc0004157aa527cf  --add 1e01206b1d2f72bd55f2a33fa8ccad74144825b7
  $ hg debugmanifestfulltextcache
  cache contains 2 manifest entries, in order of most to least recent:
  id: 1e01206b1d2f72bd55f2a33fa8ccad74144825b7, size 133 bytes
  id: fce2a30dedad1eef4da95ca1dc0004157aa527cf, size 87 bytes
  total cache data size 268 bytes, on-disk 268 bytes
  $ hg debugmanifestfulltextcache --clear

Test caching behavior on actual operation
-----------------------------------------

Make sure we start empty

  $ hg debugmanifestfulltextcache
  cache empty

Commit should have the new node cached:

  $ echo a >> b/a
  $ hg commit -m 'foo'
  $ hg debugmanifestfulltextcache
  cache contains 2 manifest entries, in order of most to least recent:
  id: 26b8653b67af8c1a0a0317c4ee8dac50a41fdb65, size 133 bytes
  id: 1e01206b1d2f72bd55f2a33fa8ccad74144825b7, size 133 bytes
  total cache data size 314 bytes, on-disk 314 bytes
  $ hg log -r 'ancestors(., 1)' --debug | grep 'manifest:'
  manifest:    1:1e01206b1d2f72bd55f2a33fa8ccad74144825b7
  manifest:    2:26b8653b67af8c1a0a0317c4ee8dac50a41fdb65

hg update should warm the cache too

(force dirstate check to avoid flackiness in manifest order)
  $ hg debugrebuilddirstate

  $ hg update 0
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg debugmanifestfulltextcache
  cache contains 3 manifest entries, in order of most to least recent:
  id: fce2a30dedad1eef4da95ca1dc0004157aa527cf, size 87 bytes
  id: 26b8653b67af8c1a0a0317c4ee8dac50a41fdb65, size 133 bytes
  id: 1e01206b1d2f72bd55f2a33fa8ccad74144825b7, size 133 bytes
  total cache data size 425 bytes, on-disk 425 bytes
  $ hg log -r '0' --debug | grep 'manifest:'
  manifest:    0:fce2a30dedad1eef4da95ca1dc0004157aa527cf

Test file removal (especially with pure).  The tests are crafted such that there
will be contiguous spans of existing entries to ensure that is handled properly.
(In this case, a.txt, aa.txt and c.txt, cc.txt, and ccc.txt)

  $ cat > $TESTTMP/manifest.py <<EOF
  > from mercurial import (
  >     extensions,
  >     manifest,
  > )
  > def extsetup(ui):
  >     manifest.FASTDELTA_TEXTDIFF_THRESHOLD = 0
  > EOF
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > manifest = $TESTTMP/manifest.py
  > EOF

Pure removes should actually remove all dropped entries

  $ hg init repo
  $ cd repo
  $ echo a > a.txt
  $ echo aa > aa.txt
  $ echo b > b.txt
  $ echo c > c.txt
  $ echo c > cc.txt
  $ echo c > ccc.txt
  $ echo b > d.txt
  $ echo c > e.txt
  $ hg ci -Aqm 'a-e'

  $ hg rm b.txt d.txt
  $ hg ci -m 'remove b and d'

  $ hg debugdata -m 1
  a.txt\x00b789fdd96dc2f3bd229c1dd8eedf0fc60e2b68e3 (esc)
  aa.txt\x00a4bdc161c8fbb523c9a60409603f8710ff49a571 (esc)
  c.txt\x00149da44f2a4e14f488b7bd4157945a9837408c00 (esc)
  cc.txt\x00149da44f2a4e14f488b7bd4157945a9837408c00 (esc)
  ccc.txt\x00149da44f2a4e14f488b7bd4157945a9837408c00 (esc)
  e.txt\x00149da44f2a4e14f488b7bd4157945a9837408c00 (esc)

  $ hg up -qC .

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 2 changesets with 8 changes to 8 files

  $ hg rollback -q --config ui.rollback=True
  $ hg rm b.txt d.txt
  $ echo bb > bb.txt

A mix of adds and removes should remove all dropped entries.

  $ hg ci -Aqm 'remove b and d; add bb'

  $ hg debugdata -m 1
  a.txt\x00b789fdd96dc2f3bd229c1dd8eedf0fc60e2b68e3 (esc)
  aa.txt\x00a4bdc161c8fbb523c9a60409603f8710ff49a571 (esc)
  bb.txt\x0004c6faf8a9fdd848a5304dfc1704749a374dff44 (esc)
  c.txt\x00149da44f2a4e14f488b7bd4157945a9837408c00 (esc)
  cc.txt\x00149da44f2a4e14f488b7bd4157945a9837408c00 (esc)
  ccc.txt\x00149da44f2a4e14f488b7bd4157945a9837408c00 (esc)
  e.txt\x00149da44f2a4e14f488b7bd4157945a9837408c00 (esc)

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 2 changesets with 9 changes to 9 files
  $ cd ..

Test manifest cache interraction with shares
============================================

  $ echo '[extensions]' >> $HGRCPATH
  $ echo 'share=' >> $HGRCPATH

creating some history

  $ hg init share-source
  $ hg debugbuilddag .+10 -n -R share-source
  $ hg log --debug -r . -R share-source | grep 'manifest:'
  manifest:    -1:0000000000000000000000000000000000000000
  $ hg log -r . -R share-source
  changeset:   -1:000000000000
  user:        
  date:        Thu Jan 01 00:00:00 1970 +0000
  
  $ hg debugmanifestfulltextcache -R share-source
  cache contains 4 manifest entries, in order of most to least recent:
  id: b264454d7033405774b9f353b9b37a082c1a8fba, size 496 bytes
  id: c6e7b359cbbb5469e98f35acd73ac4757989c4d8, size 450 bytes
  id: 8de636143b0acc5236cb47ca914bd482d82e6f35, size 405 bytes
  id: 7d32499319983d90f97ca02a6c2057a1030bebbb, size 360 bytes
  total cache data size 1.76 KB, on-disk 1.76 KB
  $ hg -R share-source update 1
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugmanifestfulltextcache -R share-source
  cache contains 4 manifest entries, in order of most to least recent:
  id: fffc37b38c401b1ab4f8b99da4b72325e31b985f, size 90 bytes
  id: b264454d7033405774b9f353b9b37a082c1a8fba, size 496 bytes
  id: c6e7b359cbbb5469e98f35acd73ac4757989c4d8, size 450 bytes
  id: 8de636143b0acc5236cb47ca914bd482d82e6f35, size 405 bytes
  total cache data size 1.50 KB, on-disk 1.50 KB

making a share out of it. It should have its manifest cache updated

  $ hg share share-source share-dest
  updating working directory
  11 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log --debug -r . -R share-dest | grep 'manifest:'
  manifest:    10:b264454d7033405774b9f353b9b37a082c1a8fba
  $ hg debugmanifestfulltextcache -R share-dest
  cache contains 1 manifest entries, in order of most to least recent:
  id: b264454d7033405774b9f353b9b37a082c1a8fba, size 496 bytes
  total cache data size 520 bytes, on-disk 520 bytes

update on various side should only affect the target share

  $ hg update -R share-dest 4
  0 files updated, 0 files merged, 6 files removed, 0 files unresolved
  $ hg log --debug -r . -R share-dest | grep 'manifest:'
  manifest:    4:d45ead487afec2588272fcec88a25413c0ec7dc8
  $ hg debugmanifestfulltextcache -R share-dest
  cache contains 2 manifest entries, in order of most to least recent:
  id: d45ead487afec2588272fcec88a25413c0ec7dc8, size 225 bytes
  id: b264454d7033405774b9f353b9b37a082c1a8fba, size 496 bytes
  total cache data size 769 bytes, on-disk 769 bytes
  $ hg debugmanifestfulltextcache -R share-source
  cache contains 4 manifest entries, in order of most to least recent:
  id: fffc37b38c401b1ab4f8b99da4b72325e31b985f, size 90 bytes
  id: b264454d7033405774b9f353b9b37a082c1a8fba, size 496 bytes
  id: c6e7b359cbbb5469e98f35acd73ac4757989c4d8, size 450 bytes
  id: 8de636143b0acc5236cb47ca914bd482d82e6f35, size 405 bytes
  total cache data size 1.50 KB, on-disk 1.50 KB
  $ hg update -R share-source 7
  6 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log --debug -r . -R share-source | grep 'manifest:'
  manifest:    7:7d32499319983d90f97ca02a6c2057a1030bebbb
  $ hg debugmanifestfulltextcache -R share-dest
  cache contains 2 manifest entries, in order of most to least recent:
  id: d45ead487afec2588272fcec88a25413c0ec7dc8, size 225 bytes
  id: b264454d7033405774b9f353b9b37a082c1a8fba, size 496 bytes
  total cache data size 769 bytes, on-disk 769 bytes
  $ hg debugmanifestfulltextcache -R share-source
  cache contains 4 manifest entries, in order of most to least recent:
  id: 7d32499319983d90f97ca02a6c2057a1030bebbb, size 360 bytes
  id: fffc37b38c401b1ab4f8b99da4b72325e31b985f, size 90 bytes
  id: b264454d7033405774b9f353b9b37a082c1a8fba, size 496 bytes
  id: c6e7b359cbbb5469e98f35acd73ac4757989c4d8, size 450 bytes
  total cache data size 1.46 KB, on-disk 1.46 KB
  $ hg update -R share-dest 8
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log --debug -r . -R share-dest | grep 'manifest:'
  manifest:    8:8de636143b0acc5236cb47ca914bd482d82e6f35
  $ hg debugmanifestfulltextcache -R share-dest
  cache contains 3 manifest entries, in order of most to least recent:
  id: 8de636143b0acc5236cb47ca914bd482d82e6f35, size 405 bytes
  id: d45ead487afec2588272fcec88a25413c0ec7dc8, size 225 bytes
  id: b264454d7033405774b9f353b9b37a082c1a8fba, size 496 bytes
  total cache data size 1.17 KB, on-disk 1.17 KB
  $ hg debugmanifestfulltextcache -R share-source
  cache contains 4 manifest entries, in order of most to least recent:
  id: 7d32499319983d90f97ca02a6c2057a1030bebbb, size 360 bytes
  id: fffc37b38c401b1ab4f8b99da4b72325e31b985f, size 90 bytes
  id: b264454d7033405774b9f353b9b37a082c1a8fba, size 496 bytes
  id: c6e7b359cbbb5469e98f35acd73ac4757989c4d8, size 450 bytes
  total cache data size 1.46 KB, on-disk 1.46 KB


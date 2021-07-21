#require bzr

  $ . "$TESTDIR/bzr-definitions"

The file/directory replacement can only be reproduced on
bzr >= 1.4. Merge it back in test-convert-bzr-directories once
this version becomes mainstream.
replace file with dir

  $ mkdir test-replace-file-with-dir
  $ cd test-replace-file-with-dir
  $ brz init -q source
  $ cd source
  $ echo d > d
  $ brz add -q d
  $ brz commit -q -m 'add d file'
  $ rm d
  $ mkdir d
  $ brz add -q d
  $ brz commit -q -m 'replace with d dir'
  $ echo a > d/a
  $ brz add -q d/a
  $ brz commit -q -m 'add d/a'
  $ cd ..
  $ hg convert source source-hg
  initializing destination source-hg repository
  scanning source...
  sorting...
  converting...
  2 add d file
  1 replace with d dir
  0 add d/a
  $ manifest source-hg tip
  % manifest of tip
  644   d/a
  $ cd source-hg
  $ hg update
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd ../..

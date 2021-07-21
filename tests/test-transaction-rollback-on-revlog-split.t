Test correctness of revlog inline -> non-inline transition
----------------------------------------------------------

Helper extension to intercept renames.

  $ cat > $TESTTMP/intercept_rename.py << EOF
  > import os
  > import sys
  > from mercurial import extensions, util
  > 
  > def extsetup(ui):
  >     def close(orig, *args, **kwargs):
  >         path = util.normpath(args[0]._atomictempfile__name)
  >         if path.endswith(b'/.hg/store/data/file.i'):
  >             os._exit(80)
  >         return orig(*args, **kwargs)
  >     extensions.wrapfunction(util.atomictempfile, 'close', close)
  > EOF

Test offset computation to correctly factor in the index entries themselve.
Also test that the new data size has the correct size if the transaction is aborted
after the index has been replaced.

Test repo has one small, one moderate and one big change. The clone has
the small and moderate change and will transition to non-inline storage when
adding the big change.

  $ hg init troffset-computation --config format.revlog-compression=none
  $ cd troffset-computation
  $ printf '%20d' '1' > file
  $ hg commit -Aqm_
  $ printf '%1024d' '1' > file
  $ hg commit -Aqm_
  $ dd if=/dev/zero of=file bs=1k count=128 > /dev/null 2>&1
  $ hg commit -Aqm_
  $ cd ..

  $ hg clone -r 1 troffset-computation troffset-computation-copy --config format.revlog-compression=none -q
  $ cd troffset-computation-copy

Reference size:

  $ f -s .hg/store/data/file*
  .hg/store/data/file.i: size=1174

  $ cat > .hg/hgrc <<EOF
  > [hooks]
  > pretxnchangegroup = python:$TESTDIR/helper-killhook.py:killme
  > EOF
#if chg
  $ hg pull ../troffset-computation
  pulling from ../troffset-computation
  [255]
#else
  $ hg pull ../troffset-computation
  pulling from ../troffset-computation
  [80]
#endif
  $ cat .hg/store/journal | tr -s '\000' ' ' | grep data/file | tail -1
  data/file.i 128

The first file.i entry should match the size above.
The first file.d entry is the temporary record during the split,
the second entry after the split happened. The sum of the second file.d
and the second file.i entry should match the first file.i entry.

  $ cat .hg/store/journal | tr -s '\000' ' ' | grep data/file
  data/file.i 1174
  data/file.d 0
  data/file.d 1046
  data/file.i 128
  $ hg recover
  rolling back interrupted transaction
  (verify step skipped, run `hg verify` to check your repository content)
  $ f -s .hg/store/data/file*
  .hg/store/data/file.d: size=1046
  .hg/store/data/file.i: size=128
  $ hg tip
  changeset:   1:3ce491143aec
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     _
  
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
   warning: revlog 'data/file.d' not in fncache!
  checked 2 changesets with 2 changes to 1 files
  1 warnings encountered!
  hint: run "hg debugrebuildfncache" to recover from corrupt fncache
  $ cd ..


Now retry the procedure but intercept the rename of the index and check that
the journal does not contain the new index size. This demonstrates the edge case
where the data file is left as garbage.

  $ hg clone -r 1 troffset-computation troffset-computation-copy2 --config format.revlog-compression=none -q
  $ cd troffset-computation-copy2
  $ cat > .hg/hgrc <<EOF
  > [extensions]
  > intercept_rename = $TESTTMP/intercept_rename.py
  > [hooks]
  > pretxnchangegroup = python:$TESTDIR/helper-killhook.py:killme
  > EOF
#if chg
  $ hg pull ../troffset-computation
  pulling from ../troffset-computation
  [255]
#else
  $ hg pull ../troffset-computation
  pulling from ../troffset-computation
  [80]
#endif
  $ cat .hg/store/journal | tr -s '\000' ' ' | grep data/file
  data/file.i 1174
  data/file.d 0
  data/file.d 1046

  $ hg recover
  rolling back interrupted transaction
  (verify step skipped, run `hg verify` to check your repository content)
  $ f -s .hg/store/data/file*
  .hg/store/data/file.d: size=1046
  .hg/store/data/file.i: size=1174
  $ hg tip
  changeset:   1:3ce491143aec
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     _
  
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 2 changesets with 2 changes to 1 files
  $ cd ..


Repeat the original test but let hg rollback the transaction.

  $ hg clone -r 1 troffset-computation troffset-computation-copy-rb --config format.revlog-compression=none -q
  $ cd troffset-computation-copy-rb
  $ cat > .hg/hgrc <<EOF
  > [hooks]
  > pretxnchangegroup = false
  > EOF
  $ hg pull ../troffset-computation
  pulling from ../troffset-computation
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  transaction abort!
  rollback completed
  abort: pretxnchangegroup hook exited with status 1
  [40]
  $ f -s .hg/store/data/file*
  .hg/store/data/file.d: size=1046
  .hg/store/data/file.i: size=128
  $ hg tip
  changeset:   1:3ce491143aec
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     _
  
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
   warning: revlog 'data/file.d' not in fncache!
  checked 2 changesets with 2 changes to 1 files
  1 warnings encountered!
  hint: run "hg debugrebuildfncache" to recover from corrupt fncache
  $ cd ..


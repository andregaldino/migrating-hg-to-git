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
  >         path = args[0]._atomictempfile__name
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
  $ printf '% 20d' '1' > file
  $ hg commit -Aqm_
  $ printf '% 1024d' '1' > file
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
  $ cd ..

Now retry the same but intercept the rename of the index and check that
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
  $ cd ..

Test correctness of revlog inline -> non-inline transition
----------------------------------------------------------

Test offset computation to correctly factor in the index entries themselve.
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

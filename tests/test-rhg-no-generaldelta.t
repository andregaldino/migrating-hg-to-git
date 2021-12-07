
  $ NO_FALLBACK="env RHG_ON_UNSUPPORTED=abort"

  $ cat << EOF >> $HGRCPATH
  > [format]
  > sparse-revlog = no
  > EOF

  $ hg init repo --config format.generaldelta=no --config format.usegeneraldelta=no
  $ cd repo
  $ (echo header; seq.py 20) > f
  $ hg commit -q -Am initial
  $ (echo header; seq.py 20; echo footer) > f
  $ hg commit -q -Am x
  $ hg update ".^"
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ (seq.py 20; echo footer) > f
  $ hg commit -q -Am y
  $ hg debugdeltachain f --template '{rev} {prevrev} {deltatype}\n'
  0 -1 base
  1 0 prev
  2 1 prev

rhg breaks on non-generaldelta revlogs:

  $ $NO_FALLBACK hg cat f -r . | f --sha256 --size
  abort: corrupted revlog (rhg !)
  size=0, sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 (rhg !)
  size=58, sha256=0cf0386dd4813cc3b957ea790146627dfc0ec42ad3fcf47221b9842e4d5764c1 (no-rhg !)

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

rhg works on non-generaldelta revlogs:

  $ $NO_FALLBACK hg cat f -r .
  1
  2
  3
  4
  5
  6
  7
  8
  9
  10
  11
  12
  13
  14
  15
  16
  17
  18
  19
  20
  footer

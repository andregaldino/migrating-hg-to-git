=============================================================
Check that we can compute and exchange revision rank properly
=============================================================

  $ cat << EOF >> $HGRCPATH
  > [format]
  > exp-use-changelog-v2=enable-unstable-format-and-corrupt-my-data
  > EOF


Test minimal rank computation with merge

  $ hg init rank-repo-minimal
  $ cd rank-repo-minimal
  $ touch 0
  $ hg commit -Aqm 0
  $ touch 1
  $ hg commit -Aqm 1
  $ hg update -qr 0
  $ touch 2
  $ hg commit -Aqm 2
  $ hg merge -qr 1
  $ hg commit -m 3
  $ touch 4
  $ hg commit -Aqm 4
  $ hg log --graph --template '{rev} {_fast_rank}\n'
  @  4 5
  |
  o    3 4
  |\
  | o  2 2
  | |
  o |  1 2
  |/
  o  0 1
  
  $ cd ..


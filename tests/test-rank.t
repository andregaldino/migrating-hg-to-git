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


Build a bigger example repo

  $ hg init rank-repo-generated
  $ cd rank-repo-generated
  $ hg debugbuilddag '.:root1+5:mp1<root1+10:mp2/mp1+3<mp1+2:mp3/mp2$+15/mp1+4'
  $ hg log -G -T '{desc}'
  o  r42
  |
  o  r41
  |
  o  r40
  |
  o  r39
  |
  o    r38
  |\
  | o  r37
  | |
  | o  r36
  | |
  | o  r35
  | |
  | o  r34
  | |
  | o  r33
  | |
  | o  r32
  | |
  | o  r31
  | |
  | o  r30
  | |
  | o  r29
  | |
  | o  r28
  | |
  | o  r27
  | |
  | o  r26
  | |
  | o  r25
  | |
  | o  r24
  | |
  | o  r23
  |
  | o    r22
  | |\
  | | o  r21
  | | |
  +---o  r20
  | |
  | | o  r19
  | | |
  | | o  r18
  | | |
  | | o  r17
  | | |
  +---o  r16
  | |/
  | o  r15
  | |
  | o  r14
  | |
  | o  r13
  | |
  | o  r12
  | |
  | o  r11
  | |
  | o  r10
  | |
  | o  r9
  | |
  | o  r8
  | |
  | o  r7
  | |
  | o  r6
  | |
  o |  r5
  | |
  o |  r4
  | |
  o |  r3
  | |
  o |  r2
  | |
  o |  r1
  |/
  o  r0
  


Check the rank
--------------

  $ hg log -G -T '{_fast_rank}'
  o  26
  |
  o  25
  |
  o  24
  |
  o  23
  |
  o    22
  |\
  | o  15
  | |
  | o  14
  | |
  | o  13
  | |
  | o  12
  | |
  | o  11
  | |
  | o  10
  | |
  | o  9
  | |
  | o  8
  | |
  | o  7
  | |
  | o  6
  | |
  | o  5
  | |
  | o  4
  | |
  | o  3
  | |
  | o  2
  | |
  | o  1
  |
  | o    19
  | |\
  | | o  8
  | | |
  +---o  7
  | |
  | | o  20
  | | |
  | | o  19
  | | |
  | | o  18
  | | |
  +---o  17
  | |/
  | o  11
  | |
  | o  10
  | |
  | o  9
  | |
  | o  8
  | |
  | o  7
  | |
  | o  6
  | |
  | o  5
  | |
  | o  4
  | |
  | o  3
  | |
  | o  2
  | |
  o |  6
  | |
  o |  5
  | |
  o |  4
  | |
  o |  3
  | |
  o |  2
  |/
  o  1
  

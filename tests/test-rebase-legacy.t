Test rebase --continue with rebasestate written by legacy client

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase=
  > drawdag=$TESTDIR/drawdag.py
  > EOF

  $ hg init
  $ hg debugdrawdag <<'EOF'
  >    D H
  >    | |
  >    C G
  >    | |
  >    B F
  >    | |
  >  Z A E
  >   \|/
  >    R
  > EOF

rebasestate generated by a legacy client running "hg rebase -r B+D+E+G+H -d Z"

  $ touch .hg/last-message.txt
  $ cat > .hg/rebasestate <<EOF
  > 0000000000000000000000000000000000000000
  > f424eb6a8c01c4a0c0fba9f863f79b3eb5b4b69f
  > 0000000000000000000000000000000000000000
  > 0
  > 0
  > 0
  > 
  > 21a6c45028857f500f56ae84fbf40689c429305b:-2
  > de008c61a447fcfd93f808ef527d933a84048ce7:0000000000000000000000000000000000000000
  > c1e6b162678d07d0b204e5c8267d51b4e03b633c:0000000000000000000000000000000000000000
  > aeba276fcb7df8e10153a07ee728d5540693f5aa:-3
  > bd5548558fcf354d37613005737a143871bf3723:-3
  > d2fa1c02b2401b0e32867f26cce50818a4bd796a:0000000000000000000000000000000000000000
  > 6f7a236de6852570cd54649ab62b1012bb78abc8:0000000000000000000000000000000000000000
  > 6582e6951a9c48c236f746f186378e36f59f4928:0000000000000000000000000000000000000000
  > EOF

  $ hg rebase --continue
  rebasing 4:c1e6b162678d "B" (B)
  rebasing 8:6f7a236de685 "D" (D)
  rebasing 2:de008c61a447 "E" (E)
  rebasing 7:d2fa1c02b240 "G" (G)
  rebasing 9:6582e6951a9c "H" (H tip)
  warning: orphaned descendants detected, not stripping c1e6b162678d, de008c61a447
  saved backup bundle to $TESTTMP/.hg/strip-backup/6f7a236de685-9880a3dc-rebase.hg (glob)

  $ hg log -G -T '{rev}:{node|short} {desc}\n'
  o  11:721b8da0a708 H
  |
  o  10:9d65695ec3c2 G
  |
  o  9:21c8397a5d68 E
  |
  | o  8:fc52970345e8 D
  | |
  | o  7:eac96551b107 B
  |/
  | o  6:bd5548558fcf C
  | |
  | | o  5:aeba276fcb7d F
  | | |
  | o |  4:c1e6b162678d B
  | | |
  o | |  3:f424eb6a8c01 Z
  | | |
  +---o  2:de008c61a447 E
  | |
  | o  1:21a6c4502885 A
  |/
  o  0:b41ce7760717 R
  

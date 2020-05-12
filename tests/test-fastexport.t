  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > fastexport=
  > EOF

  $ hg init

  $ hg debugbuilddag -mon '+2:tbase @name1 +3:thead1 <tbase @name2 +4:thead2 @both /thead1 +2:tmaintip'

  $ hg up -r 10
  13 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg rm nf10
  $ hg commit -u debugbuilddag --date 'Thu Jan 01 02:30:12 1970 +0230' -m r12
  created new head
  $ hg up -r 11
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge -r 12
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg commit -m debugbuilddag --date 'Thu Jan 01 00:00:13 1970 +0000'

  $ hg log -G
  @    changeset:   13:5544befcb7ce
  |\   branch:      both
  | |  tag:         tip
  | |  parent:      11:2cbd52c10e88
  | |  parent:      12:66d0c21243be
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:13 1970 +0000
  | |  summary:     debugbuilddag
  | |
  | o  changeset:   12:66d0c21243be
  | |  branch:      both
  | |  parent:      10:9220596cb068
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 02:30:12 1970 +0230
  | |  summary:     r12
  | |
  o |  changeset:   11:2cbd52c10e88
  |/   branch:      both
  |    tag:         tmaintip
  |    user:        debugbuilddag
  |    date:        Thu Jan 01 00:00:11 1970 +0000
  |    summary:     r11
  |
  o  changeset:   10:9220596cb068
  |  branch:      both
  |  user:        debugbuilddag
  |  date:        Thu Jan 01 00:00:10 1970 +0000
  |  summary:     r10
  |
  o    changeset:   9:0767d147d86e
  |\   branch:      both
  | |  parent:      8:0d0219415f18
  | |  parent:      4:e8bc3a6ab9ae
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 00:00:09 1970 +0000
  | |  summary:     r9
  | |
  | o  changeset:   8:0d0219415f18
  | |  branch:      name2
  | |  tag:         thead2
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 00:00:08 1970 +0000
  | |  summary:     r8
  | |
  | o  changeset:   7:82c6c8b3ac68
  | |  branch:      name2
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 00:00:07 1970 +0000
  | |  summary:     r7
  | |
  | o  changeset:   6:94093a13175f
  | |  branch:      name2
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 00:00:06 1970 +0000
  | |  summary:     r6
  | |
  | o  changeset:   5:4baee2f72e9e
  | |  branch:      name2
  | |  parent:      1:bf4022f1addd
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 00:00:05 1970 +0000
  | |  summary:     r5
  | |
  o |  changeset:   4:e8bc3a6ab9ae
  | |  branch:      name1
  | |  tag:         thead1
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 00:00:04 1970 +0000
  | |  summary:     r4
  | |
  o |  changeset:   3:46148e496a8a
  | |  branch:      name1
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 00:00:03 1970 +0000
  | |  summary:     r3
  | |
  o |  changeset:   2:29863c4219cd
  |/   branch:      name1
  |    user:        debugbuilddag
  |    date:        Thu Jan 01 00:00:02 1970 +0000
  |    summary:     r2
  |
  o  changeset:   1:bf4022f1addd
  |  tag:         tbase
  |  user:        debugbuilddag
  |  date:        Thu Jan 01 00:00:01 1970 +0000
  |  summary:     r1
  |
  o  changeset:   0:ae6ae30a671b
     user:        debugbuilddag
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     r0
  

  $ hg fastexport --export-marks fastexport.marks
  blob
  mark :1
  data 65
  0 r0
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
  21
  22
  23
  
  blob
  mark :2
  data 3
  r0
  
  commit refs/heads/default
  mark :3
  committer "debugbuilddag" <debugbuilddag> 0 +0000
  data 2
  r0
  M 644 :1 mf
  M 644 :2 nf0
  M 644 :2 of
  
  blob
  mark :4
  data 68
  0 r0
  1
  2 r1
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
  21
  22
  23
  
  blob
  mark :5
  data 3
  r1
  
  blob
  mark :6
  data 3
  r1
  
  commit refs/heads/default
  mark :7
  committer "debugbuilddag" <debugbuilddag> 1 +0000
  data 2
  r1
  from :3
  M 644 :4 mf
  M 644 :5 nf1
  M 644 :6 of
  
  blob
  mark :8
  data 71
  0 r0
  1
  2 r1
  3
  4 r2
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
  21
  22
  23
  
  blob
  mark :9
  data 3
  r2
  
  blob
  mark :10
  data 3
  r2
  
  commit refs/heads/name1
  mark :11
  committer "debugbuilddag" <debugbuilddag> 2 +0000
  data 2
  r2
  from :7
  M 644 :8 mf
  M 644 :9 nf2
  M 644 :10 of
  
  blob
  mark :12
  data 74
  0 r0
  1
  2 r1
  3
  4 r2
  5
  6 r3
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
  21
  22
  23
  
  blob
  mark :13
  data 3
  r3
  
  blob
  mark :14
  data 3
  r3
  
  commit refs/heads/name1
  mark :15
  committer "debugbuilddag" <debugbuilddag> 3 +0000
  data 2
  r3
  from :11
  M 644 :12 mf
  M 644 :13 nf3
  M 644 :14 of
  
  blob
  mark :16
  data 77
  0 r0
  1
  2 r1
  3
  4 r2
  5
  6 r3
  7
  8 r4
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
  21
  22
  23
  
  blob
  mark :17
  data 3
  r4
  
  blob
  mark :18
  data 3
  r4
  
  commit refs/heads/name1
  mark :19
  committer "debugbuilddag" <debugbuilddag> 4 +0000
  data 2
  r4
  from :15
  M 644 :16 mf
  M 644 :17 nf4
  M 644 :18 of
  
  blob
  mark :20
  data 71
  0 r0
  1
  2 r1
  3
  4
  5
  6
  7
  8
  9
  10 r5
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
  21
  22
  23
  
  blob
  mark :21
  data 3
  r5
  
  blob
  mark :22
  data 3
  r5
  
  commit refs/heads/name2
  mark :23
  committer "debugbuilddag" <debugbuilddag> 5 +0000
  data 2
  r5
  from :7
  M 644 :20 mf
  M 644 :21 nf5
  M 644 :22 of
  
  blob
  mark :24
  data 74
  0 r0
  1
  2 r1
  3
  4
  5
  6
  7
  8
  9
  10 r5
  11
  12 r6
  13
  14
  15
  16
  17
  18
  19
  20
  21
  22
  23
  
  blob
  mark :25
  data 3
  r6
  
  blob
  mark :26
  data 3
  r6
  
  commit refs/heads/name2
  mark :27
  committer "debugbuilddag" <debugbuilddag> 6 +0000
  data 2
  r6
  from :23
  M 644 :24 mf
  M 644 :25 nf6
  M 644 :26 of
  
  blob
  mark :28
  data 77
  0 r0
  1
  2 r1
  3
  4
  5
  6
  7
  8
  9
  10 r5
  11
  12 r6
  13
  14 r7
  15
  16
  17
  18
  19
  20
  21
  22
  23
  
  blob
  mark :29
  data 3
  r7
  
  blob
  mark :30
  data 3
  r7
  
  commit refs/heads/name2
  mark :31
  committer "debugbuilddag" <debugbuilddag> 7 +0000
  data 2
  r7
  from :27
  M 644 :28 mf
  M 644 :29 nf7
  M 644 :30 of
  
  blob
  mark :32
  data 80
  0 r0
  1
  2 r1
  3
  4
  5
  6
  7
  8
  9
  10 r5
  11
  12 r6
  13
  14 r7
  15
  16 r8
  17
  18
  19
  20
  21
  22
  23
  
  blob
  mark :33
  data 3
  r8
  
  blob
  mark :34
  data 3
  r8
  
  commit refs/heads/name2
  mark :35
  committer "debugbuilddag" <debugbuilddag> 8 +0000
  data 2
  r8
  from :31
  M 644 :32 mf
  M 644 :33 nf8
  M 644 :34 of
  
  blob
  mark :36
  data 92
  0 r0
  1
  2 r1
  3
  4 r2
  5
  6 r3
  7
  8 r4
  9
  10 r5
  11
  12 r6
  13
  14 r7
  15
  16 r8
  17
  18 r9
  19
  20
  21
  22
  23
  
  blob
  mark :37
  data 3
  r9
  
  blob
  mark :38
  data 3
  r9
  
  commit refs/heads/both
  mark :39
  committer "debugbuilddag" <debugbuilddag> 9 +0000
  data 2
  r9
  from :35
  merge :19
  M 644 :36 mf
  M 644 :9 nf2
  M 644 :13 nf3
  M 644 :17 nf4
  M 644 :37 nf9
  M 644 :38 of
  
  blob
  mark :40
  data 96
  0 r0
  1
  2 r1
  3
  4 r2
  5
  6 r3
  7
  8 r4
  9
  10 r5
  11
  12 r6
  13
  14 r7
  15
  16 r8
  17
  18 r9
  19
  20 r10
  21
  22
  23
  
  blob
  mark :41
  data 4
  r10
  
  blob
  mark :42
  data 4
  r10
  
  commit refs/heads/both
  mark :43
  committer "debugbuilddag" <debugbuilddag> 10 +0000
  data 3
  r10
  from :39
  M 644 :40 mf
  M 644 :41 nf10
  M 644 :42 of
  
  blob
  mark :44
  data 100
  0 r0
  1
  2 r1
  3
  4 r2
  5
  6 r3
  7
  8 r4
  9
  10 r5
  11
  12 r6
  13
  14 r7
  15
  16 r8
  17
  18 r9
  19
  20 r10
  21
  22 r11
  23
  
  blob
  mark :45
  data 4
  r11
  
  blob
  mark :46
  data 4
  r11
  
  commit refs/heads/both
  mark :47
  committer "debugbuilddag" <debugbuilddag> 11 +0000
  data 3
  r11
  from :43
  M 644 :44 mf
  M 644 :45 nf11
  M 644 :46 of
  
  commit refs/heads/both
  mark :48
  committer "debugbuilddag" <debugbuilddag> 12 +0230
  data 3
  r12
  from :43
  D nf10
  
  commit refs/heads/both
  mark :49
  committer "test" <test> 13 +0000
  data 13
  debugbuilddag
  from :47
  merge :48
  D nf10
  
  $ cat fastexport.marks
  e1767c7564f83127d75331428473dd0512b36cc6
  2c436e3f677d989438ddd9a7e5e4d56e016dfd35
  ae6ae30a671be09096aaaf51217b3691eec0eee0
  016f8fd6128ac4bd19ec5a6ae128dadc3873b13f
  a0e6fc91007068df3bc60f46ce0a893a73189b54
  1a085e1daf625e186ee0064c64ff41731a901f24
  bf4022f1addd28523fb1122ac6166a29da58d34c
  2c45ad1c720111830380baa89a6a16cae1bef688
  180506669a19f4b8317009fc6fa0043966d1ffb4
  1ebc486e6a5c2c8ca7e531cf0b63dfcc071ec324
  29863c4219cd68e0f57aecd5ffc12ba83313f26b
  d20e5eeac6991189eefad45cd8ea0f6a32ce8122
  710c4580a600b8aadc63fa3d7bb0fab71b127c04
  fa27314b56d7b6f90c1caeebb2a74730b3747574
  46148e496a8a75fde9e203b1ded69ec99289af27
  e5548c667d7eeb6c326e723c579888341329c9fe
  3c1407305701051cbed9f9cb9a68bdfb5997c235
  e2ed51893b0a54bd7fef5a406a0c489d668f19c3
  e8bc3a6ab9aef589f5db504f401953449a3c3a10
  558f3a23efc0a1a972e14d5314a65918791b77be
  0dbd89c185f53a1727c54cd1ce256482fa23968e
  f84faeb138605b36d74324c6d0ea76a9099c3567
  4baee2f72e9eeae2aef5b9e1ec416020090672ef
  412c5793886eaaabb31debd36695f6215a719865
  a0eafc60760d32b690564b8588ba042cc63e0c74
  a53842517de32d2f926c38a170c29dc90ae3348a
  94093a13175f1cfcbbfddaa0ceafbd3a89784b91
  d2f0d76af0be0da17ec88190215eadb8706689ab
  639939af794373d6c2ab12c2ef637cd220174389
  cc8921e2b19a88147643ea825459ffa140e3d704
  82c6c8b3ac6873fadd9083323b02cc6a53659130
  c6cc0b14a3e6e61906242d6fce28b9510c9f9208
  093593169cb4716f94e52ed7561bb84b36b7eb9d
  034df75dc138e7507e061d26170b4c44321a5d92
  0d0219415f18c43636163fff4160f41600951a25
  f13693f6e6052eeb189521945fef56892e812fdb
  1239c633b8a7a7283825dba9171bf285e5790852
  34b655bd51e8573b8e85c1c1476a94d8573babef
  0767d147d86e1546593bda50f1e11276c0ac8f1a
  284ca43bbbe82e89c0f1d977e8ac6cfb969c05ec
  15315ab9e272ec81ae8d847996e5bdecd5635b0b
  78c10aaf21f49d518c7ccb8318c29abb5d4e5db7
  9220596cb068dfc73e2f7e695dc8ad0858a936db
  32abd0da49b7c7ee756298fc46a15584d6aedc99
  33fbc651630ffa7ccbebfe4eb91320a873e7291c
  868d828870663d075cdcff502d26cf8445ce068e
  2cbd52c10e88ce604402dc83a869ec4f07765b3d
  66d0c21243be072f82ced64aa730ab0367252451
  5544befcb7ce4a558ed9e19909e16af574a2a3c6

  $ hg fastexport --export-marks fastexport.marks2 -r 0
  blob
  mark :1
  data 65
  0 r0
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
  21
  22
  23
  
  blob
  mark :2
  data 3
  r0
  
  commit refs/heads/default
  mark :3
  committer "debugbuilddag" <debugbuilddag> 0 +0000
  data 2
  r0
  M 644 :1 mf
  M 644 :2 nf0
  M 644 :2 of
  
  $ cat fastexport.marks2
  e1767c7564f83127d75331428473dd0512b36cc6
  2c436e3f677d989438ddd9a7e5e4d56e016dfd35
  ae6ae30a671be09096aaaf51217b3691eec0eee0
  $ hg fastexport --import-marks fastexport.marks2 -r 1
  blob
  mark :4
  data 68
  0 r0
  1
  2 r1
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
  21
  22
  23
  
  blob
  mark :5
  data 3
  r1
  
  blob
  mark :6
  data 3
  r1
  
  commit refs/heads/default
  mark :7
  committer "debugbuilddag" <debugbuilddag> 1 +0000
  data 2
  r1
  from :3
  M 644 :4 mf
  M 644 :5 nf1
  M 644 :6 of
  
  $ echo foo > of
  $ hg commit --user '<badname> <bad email>' --date 'Fri Jan 02 00:00:00 1970 +0000' -m 'Testcommit'
  $ hg fastexport --import-marks fastexport.marks -r tip
  blob
  mark :50
  data 4
  foo
  
  abort: Unable to parse user into person and email for revision 65a3f69b9b519de73d755472c1ab05990ab8a7f7
  [255]

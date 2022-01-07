==========================
Test rebase with obsolete
==========================

Enable obsolete

  $ cat >> $HGRCPATH << EOF
  > [command-templates]
  > log= {rev}:{node|short} {desc|firstline}{if(obsolete,' ({obsfate})')}
  > [experimental]
  > evolution.createmarkers=True
  > evolution.allowunstable=True
  > [phases]
  > publish=False
  > [extensions]
  > rebase=
  > drawdag=$TESTDIR/drawdag.py
  > strip=
  > EOF

Setup rebase canonical repo

  $ hg init base
  $ cd base
  $ hg unbundle "$TESTDIR/bundles/rebase.hg"
  adding changesets
  adding manifests
  adding file changes
  added 8 changesets with 7 changes to 7 files (+2 heads)
  new changesets cd010b8cd998:02de42196ebe (8 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg up tip
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log -G
  @  7:02de42196ebe H
  |
  | o  6:eea13746799a G
  |/|
  o |  5:24b6387c8c8c F
  | |
  | o  4:9520eea781bc E
  |/
  | o  3:32af7686d403 D
  | |
  | o  2:5fddd98957c8 C
  | |
  | o  1:42ccdea3bb16 B
  |/
  o  0:cd010b8cd998 A
  
  $ cd ..

simple rebase
---------------------------------

  $ hg clone base simple
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd simple
  $ hg up 32af7686d403
  3 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg rebase -d eea13746799a
  rebasing 1:42ccdea3bb16 "B"
  rebasing 2:5fddd98957c8 "C"
  rebasing 3:32af7686d403 "D"
  $ hg log -G
  @  10:8eeb3c33ad33 D
  |
  o  9:2327fea05063 C
  |
  o  8:e4e5be0395b2 B
  |
  | o  7:02de42196ebe H
  | |
  o |  6:eea13746799a G
  |\|
  | o  5:24b6387c8c8c F
  | |
  o |  4:9520eea781bc E
  |/
  o  0:cd010b8cd998 A
  
  $ hg log --hidden -G
  @  10:8eeb3c33ad33 D
  |
  o  9:2327fea05063 C
  |
  o  8:e4e5be0395b2 B
  |
  | o  7:02de42196ebe H
  | |
  o |  6:eea13746799a G
  |\|
  | o  5:24b6387c8c8c F
  | |
  o |  4:9520eea781bc E
  |/
  | x  3:32af7686d403 D (rewritten using rebase as 10:8eeb3c33ad33)
  | |
  | x  2:5fddd98957c8 C (rewritten using rebase as 9:2327fea05063)
  | |
  | x  1:42ccdea3bb16 B (rewritten using rebase as 8:e4e5be0395b2)
  |/
  o  0:cd010b8cd998 A
  
  $ hg debugobsolete
  42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 e4e5be0395b2cbd471ed22a26b1b6a1a0658a794 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  5fddd98957c8a54a4d436dfe1da9d87f21a1b97b 2327fea05063f39961b14cb69435a9898dc9a245 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  32af7686d403cf45b5d95f2d70cebea587ac806a 8eeb3c33ad33d452c89e5dcf611c347f978fb42b 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}


  $ cd ..

empty changeset
---------------------------------

  $ hg clone base empty
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd empty
  $ hg up eea13746799a
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved

We make a copy of both the first changeset in the rebased and some other in the
set.

  $ hg graft 42ccdea3bb16 32af7686d403
  grafting 1:42ccdea3bb16 "B"
  grafting 3:32af7686d403 "D"
  $ hg rebase  -s 42ccdea3bb16 -d .
  rebasing 1:42ccdea3bb16 "B"
  note: not rebasing 1:42ccdea3bb16 "B", its destination already has all its changes
  rebasing 2:5fddd98957c8 "C"
  rebasing 3:32af7686d403 "D"
  note: not rebasing 3:32af7686d403 "D", its destination already has all its changes
  $ hg log -G
  o  10:5ae4c968c6ac C
  |
  @  9:08483444fef9 D
  |
  o  8:8877864f1edb B
  |
  | o  7:02de42196ebe H
  | |
  o |  6:eea13746799a G
  |\|
  | o  5:24b6387c8c8c F
  | |
  o |  4:9520eea781bc E
  |/
  o  0:cd010b8cd998 A
  
  $ hg log --hidden -G
  o  10:5ae4c968c6ac C
  |
  @  9:08483444fef9 D
  |
  o  8:8877864f1edb B
  |
  | o  7:02de42196ebe H
  | |
  o |  6:eea13746799a G
  |\|
  | o  5:24b6387c8c8c F
  | |
  o |  4:9520eea781bc E
  |/
  | x  3:32af7686d403 D (pruned using rebase)
  | |
  | x  2:5fddd98957c8 C (rewritten using rebase as 10:5ae4c968c6ac)
  | |
  | x  1:42ccdea3bb16 B (pruned using rebase)
  |/
  o  0:cd010b8cd998 A
  
  $ hg debugobsolete
  42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 0 {cd010b8cd998f3981a5a8115f94f8da4ab506089} (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '0', 'operation': 'rebase', 'user': 'test'}
  5fddd98957c8a54a4d436dfe1da9d87f21a1b97b 5ae4c968c6aca831df823664e706c9d4aa34473d 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  32af7686d403cf45b5d95f2d70cebea587ac806a 0 {5fddd98957c8a54a4d436dfe1da9d87f21a1b97b} (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '0', 'operation': 'rebase', 'user': 'test'}


More complex case where part of the rebase set were already rebased

  $ hg rebase --rev 'desc(D)' --dest 'desc(H)'
  rebasing 9:08483444fef9 "D"
  1 new orphan changesets
  $ hg debugobsolete
  42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 0 {cd010b8cd998f3981a5a8115f94f8da4ab506089} (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '0', 'operation': 'rebase', 'user': 'test'}
  5fddd98957c8a54a4d436dfe1da9d87f21a1b97b 5ae4c968c6aca831df823664e706c9d4aa34473d 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  32af7686d403cf45b5d95f2d70cebea587ac806a 0 {5fddd98957c8a54a4d436dfe1da9d87f21a1b97b} (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '0', 'operation': 'rebase', 'user': 'test'}
  08483444fef91d6224f6655ee586a65d263ad34c 4596109a6a4328c398bde3a4a3b6737cfade3003 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  $ hg log -G
  @  11:4596109a6a43 D
  |
  | *  10:5ae4c968c6ac C
  | |
  | x  9:08483444fef9 D (rewritten using rebase as 11:4596109a6a43)
  | |
  | o  8:8877864f1edb B
  | |
  o |  7:02de42196ebe H
  | |
  | o  6:eea13746799a G
  |/|
  o |  5:24b6387c8c8c F
  | |
  | o  4:9520eea781bc E
  |/
  o  0:cd010b8cd998 A
  
  $ hg rebase --source 'desc(B)' --dest 'tip' --config experimental.rebaseskipobsolete=True
  rebasing 8:8877864f1edb "B"
  note: not rebasing 9:08483444fef9 "D", already in destination as 11:4596109a6a43 tip "D"
  rebasing 10:5ae4c968c6ac "C"
  $ hg debugobsolete
  42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 0 {cd010b8cd998f3981a5a8115f94f8da4ab506089} (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '0', 'operation': 'rebase', 'user': 'test'}
  5fddd98957c8a54a4d436dfe1da9d87f21a1b97b 5ae4c968c6aca831df823664e706c9d4aa34473d 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  32af7686d403cf45b5d95f2d70cebea587ac806a 0 {5fddd98957c8a54a4d436dfe1da9d87f21a1b97b} (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '0', 'operation': 'rebase', 'user': 'test'}
  08483444fef91d6224f6655ee586a65d263ad34c 4596109a6a4328c398bde3a4a3b6737cfade3003 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  8877864f1edb05d0e07dc4ba77b67a80a7b86672 462a34d07e599b87ea08676a449373fe4e2e1347 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  5ae4c968c6aca831df823664e706c9d4aa34473d 98f6af4ee9539e14da4465128f894c274900b6e5 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  $ hg log --rev 'contentdivergent()'
  $ hg log -G
  o  13:98f6af4ee953 C
  |
  o  12:462a34d07e59 B
  |
  @  11:4596109a6a43 D
  |
  o  7:02de42196ebe H
  |
  | o  6:eea13746799a G
  |/|
  o |  5:24b6387c8c8c F
  | |
  | o  4:9520eea781bc E
  |/
  o  0:cd010b8cd998 A
  
  $ hg log --style default --debug -r 4596109a6a4328c398bde3a4a3b6737cfade3003
  changeset:   11:4596109a6a4328c398bde3a4a3b6737cfade3003
  phase:       draft
  parent:      7:02de42196ebee42ef284b6780a87cdc96e8eaab6
  parent:      -1:0000000000000000000000000000000000000000
  manifest:    11:a91006e3a02f1edf631f7018e6e5684cf27dd905
  user:        Nicolas Dumazet <nicdumz.commits@gmail.com>
  date:        Sat Apr 30 15:24:48 2011 +0200
  files+:      D
  extra:       branch=default
  extra:       rebase_source=08483444fef91d6224f6655ee586a65d263ad34c
  extra:       source=32af7686d403cf45b5d95f2d70cebea587ac806a
  description:
  D
  
  
  $ hg up -qr 'desc(G)'
  $ hg graft 4596109a6a4328c398bde3a4a3b6737cfade3003
  grafting 11:4596109a6a43 "D"
  $ hg up -qr 'desc(E)'
  $ hg rebase -s tip -d .
  rebasing 14:9e36056a46e3 tip "D"
  $ hg log --style default --debug -r tip
  changeset:   15:627d4614809036ba22b9e7cb31638ddc06ab99ab
  tag:         tip
  phase:       draft
  parent:      4:9520eea781bcca16c1e15acc0ba14335a0e8e5ba
  parent:      -1:0000000000000000000000000000000000000000
  manifest:    15:648e8ede73ae3e497d093d3a4c8fcc2daa864f42
  user:        Nicolas Dumazet <nicdumz.commits@gmail.com>
  date:        Sat Apr 30 15:24:48 2011 +0200
  files+:      D
  extra:       branch=default
  extra:       intermediate-source=4596109a6a4328c398bde3a4a3b6737cfade3003
  extra:       rebase_source=9e36056a46e37c9776168c7375734eebc70e294f
  extra:       source=32af7686d403cf45b5d95f2d70cebea587ac806a
  description:
  D
  
  
Start rebase from a commit that is obsolete but not hidden only because it's
a working copy parent. We should be moved back to the starting commit as usual
even though it is hidden (until we're moved there).

  $ hg --hidden up -qr 'first(hidden())'
  updated to hidden changeset 42ccdea3bb16
  (hidden revision '42ccdea3bb16' is pruned)
  $ hg rebase --rev 13 --dest 15
  rebasing 13:98f6af4ee953 "C"
  $ hg log -G
  o  16:294a2b93eb4d C
  |
  o  15:627d46148090 D
  |
  | o  12:462a34d07e59 B
  | |
  | o  11:4596109a6a43 D
  | |
  | o  7:02de42196ebe H
  | |
  +---o  6:eea13746799a G
  | |/
  | o  5:24b6387c8c8c F
  | |
  o |  4:9520eea781bc E
  |/
  | @  1:42ccdea3bb16 B (pruned using rebase)
  |/
  o  0:cd010b8cd998 A
  

  $ cd ..

collapse rebase
---------------------------------

  $ hg clone base collapse
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd collapse
  $ hg rebase  -s 42ccdea3bb16 -d eea13746799a --collapse
  rebasing 1:42ccdea3bb16 "B"
  rebasing 2:5fddd98957c8 "C"
  rebasing 3:32af7686d403 "D"
  $ hg log -G
  o  8:4dc2197e807b Collapsed revision
  |
  | @  7:02de42196ebe H
  | |
  o |  6:eea13746799a G
  |\|
  | o  5:24b6387c8c8c F
  | |
  o |  4:9520eea781bc E
  |/
  o  0:cd010b8cd998 A
  
  $ hg log --hidden -G
  o  8:4dc2197e807b Collapsed revision
  |
  | @  7:02de42196ebe H
  | |
  o |  6:eea13746799a G
  |\|
  | o  5:24b6387c8c8c F
  | |
  o |  4:9520eea781bc E
  |/
  | x  3:32af7686d403 D (rewritten using rebase as 8:4dc2197e807b)
  | |
  | x  2:5fddd98957c8 C (rewritten using rebase as 8:4dc2197e807b)
  | |
  | x  1:42ccdea3bb16 B (rewritten using rebase as 8:4dc2197e807b)
  |/
  o  0:cd010b8cd998 A
  
  $ hg id --debug -r tip
  4dc2197e807bae9817f09905b50ab288be2dbbcf tip
  $ hg debugobsolete
  42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 4dc2197e807bae9817f09905b50ab288be2dbbcf 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '13', 'fold-id': '6fb65cdc', 'fold-idx': '1', 'fold-size': '3', 'operation': 'rebase', 'user': 'test'}
  5fddd98957c8a54a4d436dfe1da9d87f21a1b97b 4dc2197e807bae9817f09905b50ab288be2dbbcf 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '13', 'fold-id': '6fb65cdc', 'fold-idx': '2', 'fold-size': '3', 'operation': 'rebase', 'user': 'test'}
  32af7686d403cf45b5d95f2d70cebea587ac806a 4dc2197e807bae9817f09905b50ab288be2dbbcf 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '13', 'fold-id': '6fb65cdc', 'fold-idx': '3', 'fold-size': '3', 'operation': 'rebase', 'user': 'test'}

  $ cd ..

Rebase set has hidden descendants
---------------------------------

We rebase a changeset which has hidden descendants. Hidden changesets must not
be rebased.

  $ hg clone base hidden
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hidden
  $ hg log -G
  @  7:02de42196ebe H
  |
  | o  6:eea13746799a G
  |/|
  o |  5:24b6387c8c8c F
  | |
  | o  4:9520eea781bc E
  |/
  | o  3:32af7686d403 D
  | |
  | o  2:5fddd98957c8 C
  | |
  | o  1:42ccdea3bb16 B
  |/
  o  0:cd010b8cd998 A
  
  $ hg rebase -s 5fddd98957c8 -d eea13746799a
  rebasing 2:5fddd98957c8 "C"
  rebasing 3:32af7686d403 "D"
  $ hg log -G
  o  9:cf44d2f5a9f4 D
  |
  o  8:e273c5e7d2d2 C
  |
  | @  7:02de42196ebe H
  | |
  o |  6:eea13746799a G
  |\|
  | o  5:24b6387c8c8c F
  | |
  o |  4:9520eea781bc E
  |/
  | o  1:42ccdea3bb16 B
  |/
  o  0:cd010b8cd998 A
  
  $ hg rebase -s 42ccdea3bb16 -d 02de42196ebe
  rebasing 1:42ccdea3bb16 "B"
  $ hg log -G
  o  10:7c6027df6a99 B
  |
  | o  9:cf44d2f5a9f4 D
  | |
  | o  8:e273c5e7d2d2 C
  | |
  @ |  7:02de42196ebe H
  | |
  | o  6:eea13746799a G
  |/|
  o |  5:24b6387c8c8c F
  | |
  | o  4:9520eea781bc E
  |/
  o  0:cd010b8cd998 A
  
  $ hg log --hidden -G
  o  10:7c6027df6a99 B
  |
  | o  9:cf44d2f5a9f4 D
  | |
  | o  8:e273c5e7d2d2 C
  | |
  @ |  7:02de42196ebe H
  | |
  | o  6:eea13746799a G
  |/|
  o |  5:24b6387c8c8c F
  | |
  | o  4:9520eea781bc E
  |/
  | x  3:32af7686d403 D (rewritten using rebase as 9:cf44d2f5a9f4)
  | |
  | x  2:5fddd98957c8 C (rewritten using rebase as 8:e273c5e7d2d2)
  | |
  | x  1:42ccdea3bb16 B (rewritten using rebase as 10:7c6027df6a99)
  |/
  o  0:cd010b8cd998 A
  
  $ hg debugobsolete
  5fddd98957c8a54a4d436dfe1da9d87f21a1b97b e273c5e7d2d29df783dce9f9eaa3ac4adc69c15d 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  32af7686d403cf45b5d95f2d70cebea587ac806a cf44d2f5a9f4297a62be94cbdd3dff7c7dc54258 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}
  42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 7c6027df6a99d93f461868e5433f63bde20b6dfb 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}

Test that rewriting leaving instability behind is allowed
---------------------------------------------------------------------

  $ hg log -r 'children(8)'
  9:cf44d2f5a9f4 D (no-eol)
  $ hg rebase -r 8
  rebasing 8:e273c5e7d2d2 "C"
  1 new orphan changesets
  $ hg log -G
  o  11:0d8f238b634c C
  |
  o  10:7c6027df6a99 B
  |
  | *  9:cf44d2f5a9f4 D
  | |
  | x  8:e273c5e7d2d2 C (rewritten using rebase as 11:0d8f238b634c)
  | |
  @ |  7:02de42196ebe H
  | |
  | o  6:eea13746799a G
  |/|
  o |  5:24b6387c8c8c F
  | |
  | o  4:9520eea781bc E
  |/
  o  0:cd010b8cd998 A
  
  $ cd ..
  $ cp -R hidden stabilize
  $ cd stabilize
  $ hg rebase --auto-orphans '0::' -d 10
  abort: cannot specify both --auto-orphans and --dest
  [10]
  $ hg rebase --auto-orphans '0::'
  rebasing 9:cf44d2f5a9f4 "D"
  $ hg log -G
  o  12:7e3935feaa68 D
  |
  o  11:0d8f238b634c C
  |
  o  10:7c6027df6a99 B
  |
  @  7:02de42196ebe H
  |
  | o  6:eea13746799a G
  |/|
  o |  5:24b6387c8c8c F
  | |
  | o  4:9520eea781bc E
  |/
  o  0:cd010b8cd998 A
  

  $ cd ../hidden
  $ rm -r ../stabilize

Test multiple root handling
------------------------------------

  $ hg rebase --dest 4 --rev '7+11+9'
  rebasing 9:cf44d2f5a9f4 "D"
  rebasing 7:02de42196ebe "H"
  rebasing 11:0d8f238b634c tip "C"
  $ hg log -G
  o  14:1e8370e38cca C
  |
  @  13:bfe264faf697 H
  |
  | o  12:102b4c1d889b D
  |/
  | *  10:7c6027df6a99 B
  | |
  | x  7:02de42196ebe H (rewritten using rebase as 13:bfe264faf697)
  | |
  +---o  6:eea13746799a G
  | |/
  | o  5:24b6387c8c8c F
  | |
  o |  4:9520eea781bc E
  |/
  o  0:cd010b8cd998 A
  
  $ cd ..

Detach both parents

  $ hg init double-detach
  $ cd double-detach

  $ hg debugdrawdag <<EOF
  >   F
  >  /|
  > C E
  > | |
  > B D G
  >  \|/
  >   A
  > EOF

  $ hg rebase -d G -r 'B + D + F'
  rebasing 1:112478962961 B "B"
  rebasing 2:b18e25de2cf5 D "D"
  rebasing 6:f15c3adaf214 F tip "F"
  abort: cannot rebase 6:f15c3adaf214 without moving at least one of its parents
  [10]

  $ cd ..

test on rebase dropping a merge

(setup)

  $ hg init dropmerge
  $ cd dropmerge
  $ hg unbundle "$TESTDIR/bundles/rebase.hg"
  adding changesets
  adding manifests
  adding file changes
  added 8 changesets with 7 changes to 7 files (+2 heads)
  new changesets cd010b8cd998:02de42196ebe (8 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg up 3
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 7
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'M'
  $ echo I > I
  $ hg add I
  $ hg ci -m I
  $ hg log -G
  @  9:4bde274eefcf I
  |
  o    8:53a6a128b2b7 M
  |\
  | o  7:02de42196ebe H
  | |
  | | o  6:eea13746799a G
  | |/|
  | o |  5:24b6387c8c8c F
  | | |
  | | o  4:9520eea781bc E
  | |/
  o |  3:32af7686d403 D
  | |
  o |  2:5fddd98957c8 C
  | |
  o |  1:42ccdea3bb16 B
  |/
  o  0:cd010b8cd998 A
  
(actual test)

  $ hg rebase --dest 6 --rev '((desc(H) + desc(D))::) - desc(M)'
  rebasing 3:32af7686d403 "D"
  rebasing 7:02de42196ebe "H"
  rebasing 9:4bde274eefcf tip "I"
  1 new orphan changesets
  $ hg log -G
  @  12:acd174b7ab39 I
  |
  o  11:6c11a6218c97 H
  |
  | o  10:b5313c85b22e D
  |/
  | *    8:53a6a128b2b7 M
  | |\
  | | x  7:02de42196ebe H (rewritten using rebase as 11:6c11a6218c97)
  | | |
  o---+  6:eea13746799a G
  | | |
  | | o  5:24b6387c8c8c F
  | | |
  o---+  4:9520eea781bc E
   / /
  x |  3:32af7686d403 D (rewritten using rebase as 10:b5313c85b22e)
  | |
  o |  2:5fddd98957c8 C
  | |
  o |  1:42ccdea3bb16 B
  |/
  o  0:cd010b8cd998 A
  

Test hidden changesets in the rebase set (issue4504)

  $ hg up --hidden 9
  3 files updated, 0 files merged, 1 files removed, 0 files unresolved
  updated to hidden changeset 4bde274eefcf
  (hidden revision '4bde274eefcf' was rewritten as: acd174b7ab39)
  $ echo J > J
  $ hg add J
  $ hg commit -m J
  1 new orphan changesets
  created new head
  $ hg debugobsolete `hg log --rev . -T '{node}'`
  1 new obsolescence markers
  obsoleted 1 changesets

  $ hg rebase --rev .~1::. --dest 'max(desc(D))' --traceback --config experimental.rebaseskipobsolete=off
  rebasing 9:4bde274eefcf "I"
  rebasing 13:06edfc82198f tip "J"
  2 new content-divergent changesets
  $ hg log -G
  @  15:5ae8a643467b J
  |
  *  14:9ad579b4a5de I
  |
  | *  12:acd174b7ab39 I
  | |
  | o  11:6c11a6218c97 H
  | |
  o |  10:b5313c85b22e D
  |/
  | *    8:53a6a128b2b7 M
  | |\
  | | x  7:02de42196ebe H (rewritten using rebase as 11:6c11a6218c97)
  | | |
  o---+  6:eea13746799a G
  | | |
  | | o  5:24b6387c8c8c F
  | | |
  o---+  4:9520eea781bc E
   / /
  x |  3:32af7686d403 D (rewritten using rebase as 10:b5313c85b22e)
  | |
  o |  2:5fddd98957c8 C
  | |
  o |  1:42ccdea3bb16 B
  |/
  o  0:cd010b8cd998 A
  
  $ hg up 14 -C
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo "K" > K
  $ hg add K
  $ hg commit --amend -m "K"
  1 new orphan changesets
  $ echo "L" > L
  $ hg add L
  $ hg commit -m "L"
  $ hg up '.^'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo "M" > M
  $ hg add M
  $ hg commit --amend -m "M"
  1 new orphan changesets
  $ hg log -G
  @  18:bfaedf8eb73b M
  |
  | *  17:97219452e4bd L
  | |
  | x  16:fc37a630c901 K (rewritten using amend as 18:bfaedf8eb73b)
  |/
  | *  15:5ae8a643467b J
  | |
  | x  14:9ad579b4a5de I (rewritten using amend as 16:fc37a630c901)
  |/
  | *  12:acd174b7ab39 I
  | |
  | o  11:6c11a6218c97 H
  | |
  o |  10:b5313c85b22e D
  |/
  | *    8:53a6a128b2b7 M
  | |\
  | | x  7:02de42196ebe H (rewritten using rebase as 11:6c11a6218c97)
  | | |
  o---+  6:eea13746799a G
  | | |
  | | o  5:24b6387c8c8c F
  | | |
  o---+  4:9520eea781bc E
   / /
  x |  3:32af7686d403 D (rewritten using rebase as 10:b5313c85b22e)
  | |
  o |  2:5fddd98957c8 C
  | |
  o |  1:42ccdea3bb16 B
  |/
  o  0:cd010b8cd998 A
  
  $ hg rebase -s 14 -d 17 --config experimental.rebaseskipobsolete=True
  note: not rebasing 14:9ad579b4a5de "I", already in destination as 16:fc37a630c901 "K"
  rebasing 15:5ae8a643467b "J"
  1 new orphan changesets

  $ cd ..

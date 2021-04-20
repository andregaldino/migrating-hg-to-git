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

Divergence cases due to obsolete changesets
-------------------------------------------

We should ignore branches with unstable changesets when they are based on an
obsolete changeset which successor is in rebase set.

  $ hg init divergence
  $ cd divergence
  $ cat >> .hg/hgrc << EOF
  > [extensions]
  > strip =
  > [alias]
  > strip = strip --no-backup --quiet
  > [templates]
  > instabilities = '{rev}:{node|short} {desc|firstline}{if(instabilities," ({instabilities})")}\n'
  > EOF

  $ hg debugdrawdag <<EOF
  >   e   f
  >   |   |
  >   d'  d # replace: d -> d'
  >    \ /
  >     c
  >     |
  >   x b
  >    \|
  >     a
  > EOF
  1 new orphan changesets
  $ hg log -G -r 'a'::
  *  7:1143e9adc121 f
  |
  | o  6:d60ebfa0f1cb e
  | |
  | o  5:027ad6c5830d d'
  | |
  x |  4:76be324c128b d (rewritten using replace as 5:027ad6c5830d)
  |/
  o  3:a82ac2b38757 c
  |
  | o  2:630d7c95eff7 x
  | |
  o |  1:488e1b7e7341 b
  |/
  o  0:b173517d0057 a
  

Changeset d and its descendants are excluded to avoid divergence of d, which
would occur because the successor of d (d') is also in rebaseset. As a
consequence f (descendant of d) is left behind.

  $ hg rebase -b 'e' -d 'x'
  rebasing 1:488e1b7e7341 b "b"
  rebasing 3:a82ac2b38757 c "c"
  note: not rebasing 4:76be324c128b d "d" and its descendants as this would cause divergence
  rebasing 5:027ad6c5830d d' "d'"
  rebasing 6:d60ebfa0f1cb e "e"
  $ hg log -G -r 'a'::
  o  11:eb6d63fc4ed5 e
  |
  o  10:44d8c724a70c d'
  |
  o  9:d008e6b4d3fd c
  |
  o  8:67e8f4a16c49 b
  |
  | *  7:1143e9adc121 f
  | |
  | | x  6:d60ebfa0f1cb e (rewritten using rebase as 11:eb6d63fc4ed5)
  | | |
  | | x  5:027ad6c5830d d' (rewritten using rebase as 10:44d8c724a70c)
  | | |
  | x |  4:76be324c128b d (rewritten using replace as 5:027ad6c5830d)
  | |/
  | x  3:a82ac2b38757 c (rewritten using rebase as 9:d008e6b4d3fd)
  | |
  o |  2:630d7c95eff7 x
  | |
  | x  1:488e1b7e7341 b (rewritten using rebase as 8:67e8f4a16c49)
  |/
  o  0:b173517d0057 a
  
  $ hg strip -r 8:
  $ hg log -G -r 'a'::
  *  7:1143e9adc121 f
  |
  | o  6:d60ebfa0f1cb e
  | |
  | o  5:027ad6c5830d d'
  | |
  x |  4:76be324c128b d (rewritten using replace as 5:027ad6c5830d)
  |/
  o  3:a82ac2b38757 c
  |
  | o  2:630d7c95eff7 x
  | |
  o |  1:488e1b7e7341 b
  |/
  o  0:b173517d0057 a
  

If the rebase set has an obsolete (d) with a successor (d') outside the rebase
set and none in destination, we still get the divergence warning.
By allowing divergence, we can perform the rebase.

  $ hg rebase -r 'c'::'f' -d 'x'
  abort: this rebase will cause divergences from: 76be324c128b
  (to force the rebase please set experimental.evolution.allowdivergence=True)
  [20]
  $ hg rebase --config experimental.evolution.allowdivergence=true -r 'c'::'f' -d 'x'
  rebasing 3:a82ac2b38757 c "c"
  rebasing 4:76be324c128b d "d"
  rebasing 7:1143e9adc121 f tip "f"
  1 new orphan changesets
  2 new content-divergent changesets
  $ hg log -G -r 'a':: -T instabilities
  o  10:e1744ea07510 f
  |
  *  9:e2b36ea9a0a0 d (content-divergent)
  |
  o  8:6a0376de376e c
  |
  | x  7:1143e9adc121 f
  | |
  | | *  6:d60ebfa0f1cb e (orphan)
  | | |
  | | *  5:027ad6c5830d d' (orphan content-divergent)
  | | |
  | x |  4:76be324c128b d
  | |/
  | x  3:a82ac2b38757 c
  | |
  o |  2:630d7c95eff7 x
  | |
  | o  1:488e1b7e7341 b
  |/
  o  0:b173517d0057 a
  
  $ hg strip -r 8:

(Not skipping obsoletes means that divergence is allowed.)

  $ hg rebase --config experimental.rebaseskipobsolete=false -r 'c'::'f' -d 'x'
  rebasing 3:a82ac2b38757 c "c"
  rebasing 4:76be324c128b d "d"
  rebasing 7:1143e9adc121 f tip "f"
  1 new orphan changesets
  2 new content-divergent changesets

  $ hg strip -r 0:

Similar test on a more complex graph

  $ hg debugdrawdag <<EOF
  >       g
  >       |
  >   f   e
  >   |   |
  >   e'  d # replace: e -> e'
  >    \ /
  >     c
  >     |
  >   x b
  >    \|
  >     a
  > EOF
  1 new orphan changesets
  $ hg log -G -r 'a':
  *  8:2876ce66c6eb g
  |
  | o  7:3ffec603ab53 f
  | |
  x |  6:e36fae928aec e (rewritten using replace as 5:63324dc512ea)
  | |
  | o  5:63324dc512ea e'
  | |
  o |  4:76be324c128b d
  |/
  o  3:a82ac2b38757 c
  |
  | o  2:630d7c95eff7 x
  | |
  o |  1:488e1b7e7341 b
  |/
  o  0:b173517d0057 a
  
  $ hg rebase -b 'f' -d 'x'
  rebasing 1:488e1b7e7341 b "b"
  rebasing 3:a82ac2b38757 c "c"
  rebasing 4:76be324c128b d "d"
  note: not rebasing 6:e36fae928aec e "e" and its descendants as this would cause divergence
  rebasing 5:63324dc512ea e' "e'"
  rebasing 7:3ffec603ab53 f "f"
  $ hg log -G -r 'a':
  o  13:ef6251596616 f
  |
  o  12:b6f172e64af9 e'
  |
  | o  11:a1707a5b7c2c d
  |/
  o  10:d008e6b4d3fd c
  |
  o  9:67e8f4a16c49 b
  |
  | *  8:2876ce66c6eb g
  | |
  | | x  7:3ffec603ab53 f (rewritten using rebase as 13:ef6251596616)
  | | |
  | x |  6:e36fae928aec e (rewritten using replace as 5:63324dc512ea)
  | | |
  | | x  5:63324dc512ea e' (rewritten using rebase as 12:b6f172e64af9)
  | | |
  | x |  4:76be324c128b d (rewritten using rebase as 11:a1707a5b7c2c)
  | |/
  | x  3:a82ac2b38757 c (rewritten using rebase as 10:d008e6b4d3fd)
  | |
  o |  2:630d7c95eff7 x
  | |
  | x  1:488e1b7e7341 b (rewritten using rebase as 9:67e8f4a16c49)
  |/
  o  0:b173517d0057 a
  

issue5782
  $ hg strip -r 0:
  $ hg debugdrawdag <<EOF
  >       d
  >       |
  >   c1  c # replace: c -> c1
  >    \ /
  >     b
  >     |
  >     a
  > EOF
  1 new orphan changesets
  $ hg debugobsolete `hg log -T "{node}" --hidden -r 'desc("c1")'`
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg log -G -r 'a': --hidden
  *  4:76be324c128b d
  |
  | x  3:ef8a456de8fa c1 (pruned)
  | |
  x |  2:a82ac2b38757 c (rewritten using replace as 3:ef8a456de8fa)
  |/
  o  1:488e1b7e7341 b
  |
  o  0:b173517d0057 a
  
  $ hg rebase -d 0 -r 2
  note: not rebasing 2:a82ac2b38757 c "c", it has no successor
  $ hg log -G -r 'a': --hidden
  *  4:76be324c128b d
  |
  | x  3:ef8a456de8fa c1 (pruned)
  | |
  x |  2:a82ac2b38757 c (rewritten using replace as 3:ef8a456de8fa)
  |/
  o  1:488e1b7e7341 b
  |
  o  0:b173517d0057 a
  
  $ cd ..

Start a normal rebase. When it runs into conflicts, rewrite one of the
commits in the rebase set, causing divergence when the rebase continues.

  $ hg init $TESTTMP/new-divergence-after-conflict
  $ cd $TESTTMP/new-divergence-after-conflict
  $ hg debugdrawdag <<'EOS'
  >  C2
  >  | C1
  >  |/
  >  B # B/D=B
  >  | D
  >  |/
  >  A
  > EOS
  $ hg rebase -r B::C1 -d D
  rebasing 1:2ec65233581b B "B"
  merging D
  warning: conflicts while merging D! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg debugobsolete $(hg log -r C1 -T '{node}') $(hg log -r C2 -T '{node}')
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg log -G
  o  4:fdb9df6b130c C2
  |
  | x  3:7e5bfd3c08f0 C1 (rewritten as 4:fdb9df6b130c)
  |/
  | @  2:b18e25de2cf5 D
  | |
  % |  1:2ec65233581b B
  |/
  o  0:426bada5c675 A
  
  $ echo resolved > D
  $ hg resolve -m D
  (no more unresolved files)
  continue: hg rebase --continue
  $ hg rebase -c
  rebasing 1:2ec65233581b B "B"
  note: not rebasing 3:7e5bfd3c08f0 C1 "C1" and its descendants as this would cause divergence
  1 new orphan changesets

Rebase merge where successor of one parent is equal to destination (issue5198)

  $ hg init p1-succ-is-dest
  $ cd p1-succ-is-dest

  $ hg debugdrawdag <<EOF
  >   F
  >  /|
  > E D B # replace: D -> B
  >  \|/
  >   A
  > EOF
  1 new orphan changesets

  $ hg rebase -d B -s D
  note: not rebasing 2:b18e25de2cf5 D "D", already in destination as 1:112478962961 B "B"
  rebasing 4:66f1a38021c9 F tip "F"
  $ hg log -G
  o    5:50e9d60b99c6 F
  |\
  | | x  4:66f1a38021c9 F (rewritten using rebase as 5:50e9d60b99c6)
  | |/|
  | o |  3:7fb047a69f22 E
  | | |
  | | x  2:b18e25de2cf5 D (rewritten using replace as 1:112478962961)
  | |/
  o |  1:112478962961 B
  |/
  o  0:426bada5c675 A
  
  $ cd ..

Rebase merge where successor of other parent is equal to destination

  $ hg init p2-succ-is-dest
  $ cd p2-succ-is-dest

  $ hg debugdrawdag <<EOF
  >   F
  >  /|
  > E D B # replace: E -> B
  >  \|/
  >   A
  > EOF
  1 new orphan changesets

  $ hg rebase -d B -s E
  note: not rebasing 3:7fb047a69f22 E "E", already in destination as 1:112478962961 B "B"
  rebasing 4:66f1a38021c9 F tip "F"
  $ hg log -G
  o    5:aae1787dacee F
  |\
  | | x  4:66f1a38021c9 F (rewritten using rebase as 5:aae1787dacee)
  | |/|
  | | x  3:7fb047a69f22 E (rewritten using replace as 1:112478962961)
  | | |
  | o |  2:b18e25de2cf5 D
  | |/
  o /  1:112478962961 B
  |/
  o  0:426bada5c675 A
  
  $ cd ..

Rebase merge where successor of one parent is ancestor of destination

  $ hg init p1-succ-in-dest
  $ cd p1-succ-in-dest

  $ hg debugdrawdag <<EOF
  >   F C
  >  /| |
  > E D B # replace: D -> B
  >  \|/
  >   A
  > EOF
  1 new orphan changesets

  $ hg rebase -d C -s D
  note: not rebasing 2:b18e25de2cf5 D "D", already in destination as 1:112478962961 B "B"
  rebasing 5:66f1a38021c9 F tip "F"

  $ hg log -G
  o    6:0913febf6439 F
  |\
  +---x  5:66f1a38021c9 F (rewritten using rebase as 6:0913febf6439)
  | | |
  | o |  4:26805aba1e60 C
  | | |
  o | |  3:7fb047a69f22 E
  | | |
  +---x  2:b18e25de2cf5 D (rewritten using replace as 1:112478962961)
  | |
  | o  1:112478962961 B
  |/
  o  0:426bada5c675 A
  
  $ cd ..

Rebase merge where successor of other parent is ancestor of destination

  $ hg init p2-succ-in-dest
  $ cd p2-succ-in-dest

  $ hg debugdrawdag <<EOF
  >   F C
  >  /| |
  > E D B # replace: E -> B
  >  \|/
  >   A
  > EOF
  1 new orphan changesets

  $ hg rebase -d C -s E
  note: not rebasing 3:7fb047a69f22 E "E", already in destination as 1:112478962961 B "B"
  rebasing 5:66f1a38021c9 F tip "F"
  $ hg log -G
  o    6:c6ab0cc6d220 F
  |\
  +---x  5:66f1a38021c9 F (rewritten using rebase as 6:c6ab0cc6d220)
  | | |
  | o |  4:26805aba1e60 C
  | | |
  | | x  3:7fb047a69f22 E (rewritten using replace as 1:112478962961)
  | | |
  o---+  2:b18e25de2cf5 D
   / /
  o /  1:112478962961 B
  |/
  o  0:426bada5c675 A
  
  $ cd ..

Rebase merge where successor of one parent is ancestor of destination

  $ hg init p1-succ-in-dest-b
  $ cd p1-succ-in-dest-b

  $ hg debugdrawdag <<EOF
  >   F C
  >  /| |
  > E D B # replace: E -> B
  >  \|/
  >   A
  > EOF
  1 new orphan changesets

  $ hg rebase -d C -b F
  rebasing 2:b18e25de2cf5 D "D"
  note: not rebasing 3:7fb047a69f22 E "E", already in destination as 1:112478962961 B "B"
  rebasing 5:66f1a38021c9 F tip "F"
  note: not rebasing 5:66f1a38021c9 F tip "F", its destination already has all its changes
  $ hg log -G
  o  6:8f47515dda15 D
  |
  | x    5:66f1a38021c9 F (pruned using rebase)
  | |\
  o | |  4:26805aba1e60 C
  | | |
  | | x  3:7fb047a69f22 E (rewritten using replace as 1:112478962961)
  | | |
  | x |  2:b18e25de2cf5 D (rewritten using rebase as 6:8f47515dda15)
  | |/
  o /  1:112478962961 B
  |/
  o  0:426bada5c675 A
  
  $ cd ..

Rebase merge where successor of other parent is ancestor of destination

  $ hg init p2-succ-in-dest-b
  $ cd p2-succ-in-dest-b

  $ hg debugdrawdag <<EOF
  >   F C
  >  /| |
  > E D B # replace: D -> B
  >  \|/
  >   A
  > EOF
  1 new orphan changesets

  $ hg rebase -d C -b F
  note: not rebasing 2:b18e25de2cf5 D "D", already in destination as 1:112478962961 B "B"
  rebasing 3:7fb047a69f22 E "E"
  rebasing 5:66f1a38021c9 F tip "F"
  note: not rebasing 5:66f1a38021c9 F tip "F", its destination already has all its changes

  $ hg log -G
  o  6:533690786a86 E
  |
  | x    5:66f1a38021c9 F (pruned using rebase)
  | |\
  o | |  4:26805aba1e60 C
  | | |
  | | x  3:7fb047a69f22 E (rewritten using rebase as 6:533690786a86)
  | | |
  | x |  2:b18e25de2cf5 D (rewritten using replace as 1:112478962961)
  | |/
  o /  1:112478962961 B
  |/
  o  0:426bada5c675 A
  
  $ cd ..

Rebase merge where extinct node has successor that is not an ancestor of
destination

  $ hg init extinct-with-succ-not-in-dest
  $ cd extinct-with-succ-not-in-dest

  $ hg debugdrawdag <<EOF
  > E C # replace: C -> E
  > | |
  > D B
  > |/
  > A
  > EOF

  $ hg rebase -d D -s B
  rebasing 1:112478962961 B "B"
  note: not rebasing 3:26805aba1e60 C "C" and its descendants as this would cause divergence

  $ cd ..

  $ hg init p2-succ-in-dest-c
  $ cd p2-succ-in-dest-c

The scenario here was that B::D were developed on default.  B was queued on
stable, but amended before being push to hg-committed.  C was queued on default,
along with unrelated J.

  $ hg debugdrawdag <<EOF
  > J
  > |
  > F
  > |
  > E
  > | D
  > | |
  > | C      # replace: C -> F
  > | |  H I # replace: B -> H -> I
  > | B  |/
  > |/   G
  > A
  > EOF
  1 new orphan changesets

This strip seems to be the key to avoid an early divergence warning.
  $ hg --config extensions.strip= --hidden strip -qr H
  1 new orphan changesets

  $ hg rebase -b 'desc("D")' -d 'desc("J")'
  abort: this rebase will cause divergences from: 112478962961
  (to force the rebase please set experimental.evolution.allowdivergence=True)
  [20]

Rebase merge where both parents have successors in destination

  $ hg init p12-succ-in-dest
  $ cd p12-succ-in-dest
  $ hg debugdrawdag <<'EOS'
  >   E   F
  >  /|  /|  # replace: A -> C
  > A B C D  # replace: B -> D
  > | |
  > X Y
  > EOS
  1 new orphan changesets
  $ hg rebase -r A+B+E -d F
  note: not rebasing 4:a3d17304151f A "A", already in destination as 0:96cc3511f894 C "C"
  note: not rebasing 5:b23a2cc00842 B "B", already in destination as 1:058c1e1fb10a D "D"
  rebasing 7:dac5d11c5a7d E tip "E"
  abort: rebasing 7:dac5d11c5a7d will include unwanted changes from 3:59c792af609c, 5:b23a2cc00842 or 2:ba2b7fa7166d, 4:a3d17304151f
  [10]
  $ cd ..

Rebase a non-clean merge. One parent has successor in destination, the other
parent moves as requested.

  $ hg init p1-succ-p2-move
  $ cd p1-succ-p2-move
  $ hg debugdrawdag <<'EOS'
  >   D Z
  >  /| | # replace: A -> C
  > A B C # D/D = D
  > EOS
  1 new orphan changesets
  $ hg rebase -r A+B+D -d Z
  note: not rebasing 0:426bada5c675 A "A", already in destination as 2:96cc3511f894 C "C"
  rebasing 1:fc2b737bb2e5 B "B"
  rebasing 3:b8ed089c80ad D "D"

  $ rm .hg/localtags
  $ hg log -G
  o  6:e4f78693cc88 D
  |
  o  5:76840d832e98 B
  |
  o  4:50e41c1f3950 Z
  |
  o  2:96cc3511f894 C
  
  $ hg files -r tip
  B
  C
  D
  Z

  $ cd ..

  $ hg init p1-move-p2-succ
  $ cd p1-move-p2-succ
  $ hg debugdrawdag <<'EOS'
  >   D Z
  >  /| |  # replace: B -> C
  > A B C  # D/D = D
  > EOS
  1 new orphan changesets
  $ hg rebase -r B+A+D -d Z
  rebasing 0:426bada5c675 A "A"
  note: not rebasing 1:fc2b737bb2e5 B "B", already in destination as 2:96cc3511f894 C "C"
  rebasing 3:b8ed089c80ad D "D"

  $ rm .hg/localtags
  $ hg log -G
  o  6:1b355ed94d82 D
  |
  o  5:a81a74d764a6 A
  |
  o  4:50e41c1f3950 Z
  |
  o  2:96cc3511f894 C
  
  $ hg files -r tip
  A
  C
  D
  Z

  $ cd ..

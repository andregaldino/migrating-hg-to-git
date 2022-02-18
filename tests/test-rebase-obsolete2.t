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

Skip obsolete changeset even with multiple hops
-----------------------------------------------

setup

  $ hg init obsskip
  $ cd obsskip
  $ cat << EOF >> .hg/hgrc
  > [experimental]
  > rebaseskipobsolete = True
  > [extensions]
  > strip =
  > EOF
  $ echo A > A
  $ hg add A
  $ hg commit -m A
  $ echo B > B
  $ hg add B
  $ hg commit -m B0
  $ hg commit --amend -m B1
  $ hg commit --amend -m B2
  $ hg up --hidden 'desc(B0)'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  updated to hidden changeset a8b11f55fb19
  (hidden revision 'a8b11f55fb19' was rewritten as: 261e70097290)
  $ echo C > C
  $ hg add C
  $ hg commit -m C
  1 new orphan changesets
  created new head
  $ hg log -G
  @  4:212cb178bcbb C
  |
  | o  3:261e70097290 B2
  | |
  x |  1:a8b11f55fb19 B0 (rewritten using amend as 3:261e70097290)
  |/
  o  0:4a2df7238c3b A
  

Rebase finds its way in a chain of marker

  $ hg rebase -d 'desc(B2)'
  note: not rebasing 1:a8b11f55fb19 "B0", already in destination as 3:261e70097290 "B2"
  rebasing 4:212cb178bcbb tip "C"

Even when the chain include missing node

  $ hg up --hidden 'desc(B0)'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  updated to hidden changeset a8b11f55fb19
  (hidden revision 'a8b11f55fb19' was rewritten as: 261e70097290)
  $ echo D > D
  $ hg add D
  $ hg commit -m D
  1 new orphan changesets
  created new head
  $ hg --hidden strip -r 'desc(B1)'
  saved backup bundle to $TESTTMP/obsskip/.hg/strip-backup/86f6414ccda7-b1c452ee-backup.hg
  1 new orphan changesets
  $ hg log -G
  @  5:1a79b7535141 D
  |
  | o  4:ff2c4d47b71d C
  | |
  | o  2:261e70097290 B2
  | |
  x |  1:a8b11f55fb19 B0 (rewritten using amend as 2:261e70097290)
  |/
  o  0:4a2df7238c3b A
  

  $ hg rebase -d 'desc(B2)'
  note: not rebasing 1:a8b11f55fb19 "B0", already in destination as 2:261e70097290 "B2"
  rebasing 5:1a79b7535141 tip "D"
  $ hg up 4
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo "O" > O
  $ hg add O
  $ hg commit -m O
  $ echo "P" > P
  $ hg add P
  $ hg commit -m P
  $ hg log -G
  @  8:8d47583e023f P
  |
  o  7:360bbaa7d3ce O
  |
  | o  6:9c48361117de D
  | |
  o |  4:ff2c4d47b71d C
  |/
  o  2:261e70097290 B2
  |
  o  0:4a2df7238c3b A
  
  $ hg debugobsolete `hg log -r 7 -T '{node}\n'` --config experimental.evolution=true
  1 new obsolescence markers
  obsoleted 1 changesets
  1 new orphan changesets
  $ hg rebase -d 6 -r "4::"
  rebasing 4:ff2c4d47b71d "C"
  note: not rebasing 7:360bbaa7d3ce "O", it has no successor
  rebasing 8:8d47583e023f tip "P"

If all the changeset to be rebased are obsolete and present in the destination, we
should display a friendly error message

  $ hg log -G
  @  10:121d9e3bc4c6 P
  |
  o  9:4be60e099a77 C
  |
  o  6:9c48361117de D
  |
  o  2:261e70097290 B2
  |
  o  0:4a2df7238c3b A
  

  $ hg up 9
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo "non-relevant change" > nonrelevant
  $ hg add nonrelevant
  $ hg commit -m nonrelevant
  created new head
  $ hg debugobsolete `hg log -r 11 -T '{node}\n'` --config experimental.evolution=true
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg log -G
  @  11:f44da1f4954c nonrelevant (pruned)
  |
  | o  10:121d9e3bc4c6 P
  |/
  o  9:4be60e099a77 C
  |
  o  6:9c48361117de D
  |
  o  2:261e70097290 B2
  |
  o  0:4a2df7238c3b A
  
  $ hg rebase -r . -d 10
  note: not rebasing 11:f44da1f4954c tip "nonrelevant", it has no successor

If a rebase is going to create divergence, it should abort

  $ hg log -G
  @  10:121d9e3bc4c6 P
  |
  o  9:4be60e099a77 C
  |
  o  6:9c48361117de D
  |
  o  2:261e70097290 B2
  |
  o  0:4a2df7238c3b A
  

  $ hg up 9
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo "john" > doe
  $ hg add doe
  $ hg commit -m "john doe"
  created new head
  $ hg up 10
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo "foo" > bar
  $ hg add bar
  $ hg commit --amend -m "10'"
  $ hg up 10 --hidden
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  updated to hidden changeset 121d9e3bc4c6
  (hidden revision '121d9e3bc4c6' was rewritten as: 77d874d096a2)
  $ echo "bar" > foo
  $ hg add foo
  $ hg commit -m "bar foo"
  1 new orphan changesets
  created new head
  $ hg log -G
  @  14:73568ab6879d bar foo
  |
  | o  13:77d874d096a2 10'
  | |
  | | o  12:3eb461388009 john doe
  | |/
  x |  10:121d9e3bc4c6 P (rewritten using amend as 13:77d874d096a2)
  |/
  o  9:4be60e099a77 C
  |
  o  6:9c48361117de D
  |
  o  2:261e70097290 B2
  |
  o  0:4a2df7238c3b A
  
  $ hg summary
  parent: 14:73568ab6879d tip (orphan)
   bar foo
  branch: default
  commit: (clean)
  update: 2 new changesets, 3 branch heads (merge)
  phases: 8 draft
  orphan: 1 changesets
  $ hg rebase -s 10 -d 12
  abort: this rebase will cause divergences from: 121d9e3bc4c6
  (to force the rebase please set experimental.evolution.allowdivergence=True)
  [20]
  $ hg log -G
  @  14:73568ab6879d bar foo
  |
  | o  13:77d874d096a2 10'
  | |
  | | o  12:3eb461388009 john doe
  | |/
  x |  10:121d9e3bc4c6 P (rewritten using amend as 13:77d874d096a2)
  |/
  o  9:4be60e099a77 C
  |
  o  6:9c48361117de D
  |
  o  2:261e70097290 B2
  |
  o  0:4a2df7238c3b A
  
With experimental.evolution.allowdivergence=True, rebase can create divergence

  $ hg rebase -s 10 -d 12 --config experimental.evolution.allowdivergence=True
  rebasing 10:121d9e3bc4c6 "P"
  rebasing 14:73568ab6879d tip "bar foo"
  2 new content-divergent changesets
  $ hg summary
  parent: 16:61bd55f69bc4 tip
   bar foo
  branch: default
  commit: (clean)
  update: 1 new changesets, 2 branch heads (merge)
  phases: 8 draft
  content-divergent: 2 changesets

rebase --continue + skipped rev because their successors are in destination
we make a change in trunk and work on conflicting changes to make rebase abort.

  $ hg log -G -r 16::
  @  16:61bd55f69bc4 bar foo
  |
  ~

Create the two changes in trunk
  $ printf "a" > willconflict
  $ hg add willconflict
  $ hg commit -m "willconflict first version"

  $ printf "dummy" > C
  $ hg commit -m "dummy change successor"

Create the changes that we will rebase
  $ hg update -C 16 -q
  $ printf "b" > willconflict
  $ hg add willconflict
  $ hg commit -m "willconflict second version"
  created new head
  $ printf "dummy" > K
  $ hg add K
  $ hg commit -m "dummy change"
  $ printf "dummy" > L
  $ hg add L
  $ hg commit -m "dummy change"
  $ hg debugobsolete `hg log -r ".^" -T '{node}'` `hg log -r 18 -T '{node}'` --config experimental.evolution=true
  1 new obsolescence markers
  obsoleted 1 changesets
  1 new orphan changesets

  $ hg log -G -r 16::
  @  21:7bdc8a87673d dummy change
  |
  x  20:8b31da3c4919 dummy change (rewritten as 18:601db7a18f51)
  |
  o  19:b82fb57ea638 willconflict second version
  |
  | o  18:601db7a18f51 dummy change successor
  | |
  | o  17:357ddf1602d5 willconflict first version
  |/
  o  16:61bd55f69bc4 bar foo
  |
  ~
  $ hg rebase -r ".^^ + .^ + ." -d 18
  rebasing 19:b82fb57ea638 "willconflict second version"
  merging willconflict
  warning: conflicts while merging willconflict! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg resolve --mark willconflict
  (no more unresolved files)
  continue: hg rebase --continue
  $ hg rebase --continue
  rebasing 19:b82fb57ea638 "willconflict second version"
  note: not rebasing 20:8b31da3c4919 "dummy change", already in destination as 18:601db7a18f51 "dummy change successor"
  rebasing 21:7bdc8a87673d tip "dummy change"
  $ cd ..

Can rebase pruned and rewritten commits with --keep

  $ hg init keep
  $ cd keep
  $ hg debugdrawdag <<'EOS'
  >   D
  >   |
  >   C
  >   |
  > F B E  # prune: B
  >  \|/   # rebase: C -> E
  >   A
  > EOS
  1 new orphan changesets

  $ hg rebase -b D -d F --keep
  rebasing 1:112478962961 B "B"
  rebasing 4:26805aba1e60 C "C"
  rebasing 5:f585351a92f8 D tip "D"

  $ cd ..

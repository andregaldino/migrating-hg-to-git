  $ cat >> $HGRCPATH<<EOF
  > [extensions]
  > rebase=
  > drawdag=$TESTDIR/drawdag.py
  > EOF

  $ hg init non-merge
  $ cd non-merge
  $ hg debugdrawdag<<'EOS'
  >   F
  >   |
  >   E
  >   |
  >   D
  >   |
  > B C
  > |/
  > A
  > EOS

  $ for i in C D E F; do
  >   hg bookmark -r $i -i BOOK-$i
  > done

  $ hg debugdrawdag<<'EOS'
  > E
  > |
  > D
  > |
  > B
  > EOS

  $ hg log -G -T '{rev} {desc} {bookmarks}'
  o  7 E
  |
  o  6 D
  |
  | o  5 F BOOK-F
  | |
  | o  4 E BOOK-E
  | |
  | o  3 D BOOK-D
  | |
  | o  2 C BOOK-C
  | |
  o |  1 B
  |/
  o  0 A
  
With --keep, bookmark should move

  $ hg rebase -r 3+4 -d E --keep
  rebasing 3:e7b3f00ed42e BOOK-D "D"
  note: not rebasing 3:e7b3f00ed42e BOOK-D "D", its destination already has all its changes
  rebasing 4:69a34c08022a BOOK-E "E"
  note: not rebasing 4:69a34c08022a BOOK-E "E", its destination already has all its changes
  $ hg log -G -T '{rev} {desc} {bookmarks}'
  o  7 E BOOK-D BOOK-E
  |
  o  6 D
  |
  | o  5 F BOOK-F
  | |
  | o  4 E
  | |
  | o  3 D
  | |
  | o  2 C BOOK-C
  | |
  o |  1 B
  |/
  o  0 A
  
Move D and E back for the next test

  $ hg bookmark BOOK-D -fqir 3
  $ hg bookmark BOOK-E -fqir 4

Bookmark is usually an indication of a head. For changes that are introduced by
an ancestor of bookmark B, after moving B to B-NEW, the changes are ideally
still introduced by an ancestor of changeset on B-NEW. In the below case,
"BOOK-D", and "BOOK-E" include changes introduced by "C".

  $ hg rebase -s 2 -d E
  rebasing 2:dc0947a82db8 BOOK-C C "C"
  rebasing 3:e7b3f00ed42e BOOK-D "D"
  note: not rebasing 3:e7b3f00ed42e BOOK-D "D", its destination already has all its changes
  rebasing 4:69a34c08022a BOOK-E "E"
  note: not rebasing 4:69a34c08022a BOOK-E "E", its destination already has all its changes
  rebasing 5:6b2aeab91270 BOOK-F F "F"
  saved backup bundle to $TESTTMP/non-merge/.hg/strip-backup/dc0947a82db8-52bb4973-rebase.hg
  $ hg log -G -T '{rev} {desc} {bookmarks}'
  o  5 F BOOK-F
  |
  o  4 C BOOK-C BOOK-D BOOK-E
  |
  o  3 E
  |
  o  2 D
  |
  o  1 B
  |
  o  0 A
  
Merge and its ancestors all become empty

  $ hg init $TESTTMP/merge1
  $ cd $TESTTMP/merge1

  $ hg debugdrawdag<<'EOS'
  >     E
  >    /|
  > B C D
  >  \|/
  >   A
  > EOS

  $ for i in C D E; do
  >   hg bookmark -r $i -i BOOK-$i
  > done

  $ hg debugdrawdag<<'EOS'
  > H
  > |
  > D
  > |
  > C
  > |
  > B
  > EOS

Previously, there was a bug where the empty commit check compared the parent
branch name with the wdir branch name instead of the actual branch name (which
should stay unchanged if --keepbranches is passed), and erroneously assumed
that an otherwise empty changeset should be created because of the incorrectly
assumed branch name change.

  $ hg update H -q
  $ hg branch foo -q

  $ hg rebase -r '(A::)-(B::)-A' -d H --keepbranches
  rebasing 2:dc0947a82db8 BOOK-C "C"
  note: not rebasing 2:dc0947a82db8 BOOK-C "C", its destination already has all its changes
  rebasing 3:b18e25de2cf5 BOOK-D "D"
  note: not rebasing 3:b18e25de2cf5 BOOK-D "D", its destination already has all its changes
  rebasing 4:86a1f6686812 BOOK-E E "E"
  note: not rebasing 4:86a1f6686812 BOOK-E E "E", its destination already has all its changes
  saved backup bundle to $TESTTMP/merge1/.hg/strip-backup/b18e25de2cf5-1fd0a4ba-rebase.hg
  $ hg update null -q

  $ hg log -G -T '{rev} {desc} {bookmarks}'
  o  4 H BOOK-C BOOK-D BOOK-E
  |
  o  3 D
  |
  o  2 C
  |
  o  1 B
  |
  o  0 A
  
Part of ancestors of a merge become empty

  $ hg init $TESTTMP/merge2
  $ cd $TESTTMP/merge2

  $ hg debugdrawdag<<'EOS'
  >     G
  >    /|
  >   E F
  >   | |
  > B C D
  >  \|/
  >   A
  > EOS

  $ for i in C D E F G; do
  >   hg bookmark -r $i -i BOOK-$i
  > done

  $ hg debugdrawdag<<'EOS'
  > H
  > |
  > F
  > |
  > C
  > |
  > B
  > EOS

  $ hg rebase -r '(A::)-(B::)-A' -d H
  rebasing 2:dc0947a82db8 BOOK-C "C"
  note: not rebasing 2:dc0947a82db8 BOOK-C "C", its destination already has all its changes
  rebasing 3:b18e25de2cf5 BOOK-D D "D"
  rebasing 4:03ca77807e91 BOOK-E E "E"
  rebasing 5:ad6717a6a58e BOOK-F "F"
  note: not rebasing 5:ad6717a6a58e BOOK-F "F", its destination already has all its changes
  rebasing 6:c58e8bdac1f4 BOOK-G G "G"
  saved backup bundle to $TESTTMP/merge2/.hg/strip-backup/b18e25de2cf5-2d487005-rebase.hg

  $ hg log -G -T '{rev} {desc} {bookmarks}'
  o    7 G BOOK-G
  |\
  | o  6 E BOOK-E
  | |
  o |  5 D BOOK-D BOOK-F
  |/
  o  4 H BOOK-C
  |
  o  3 F
  |
  o  2 C
  |
  o  1 B
  |
  o  0 A
  

#testcases filelog compatibility sidedata

=====================================================
Test Copy tracing for chain of copies involving merge
=====================================================

This test files covers copies/rename case for a chains of commit where merges
are involved. It cheks we do not have unwanted update of behavior and that the
different options to retrieve copies behave correctly.


Setup
=====

use git diff to see rename

  $ cat << EOF >> $HGRCPATH
  > [diff]
  > git=yes
  > [ui]
  > logtemplate={rev} {desc}\n
  > EOF

#if compatibility
  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > copies.read-from = compatibility
  > EOF
#endif

#if sidedata
  $ cat >> $HGRCPATH << EOF
  > [format]
  > exp-use-side-data = yes
  > exp-use-copies-side-data-changeset = yes
  > EOF
#endif


  $ hg init repo-chain
  $ cd repo-chain

Add some linear rename initialy

  $ touch a b h
  $ hg ci -Am 'i-0 initial commit: a b h'
  adding a
  adding b
  adding h
  $ hg mv a c
  $ hg ci -Am 'i-1: a -move-> c'
  $ hg mv c d
  $ hg ci -Am 'i-2: c -move-> d'
  $ hg log -G
  @  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

And having another branch with renames on the other side

  $ hg mv d e
  $ hg ci -Am 'a-1: d -move-> e'
  $ hg mv e f
  $ hg ci -Am 'a-2: e -move-> f'
  $ hg log -G --rev '::.'
  @  4 a-2: e -move-> f
  |
  o  3 a-1: d -move-> e
  |
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

Have a branching with nothing on one side

  $ hg up 'desc("i-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo foo > b
  $ hg ci -m 'b-1: b update'
  created new head
  $ hg log -G --rev '::.'
  @  5 b-1: b update
  |
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

Create a branch that delete a file previous renamed

  $ hg up 'desc("i-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg rm d
  $ hg ci -m 'c-1 delete d'
  created new head
  $ hg log -G --rev '::.'
  @  6 c-1 delete d
  |
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

Create a branch that delete a file previous renamed and recreate it

  $ hg up 'desc("i-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg rm d
  $ hg ci -m 'd-1 delete d'
  created new head
  $ echo bar > d
  $ hg add d
  $ hg ci -m 'd-2 re-add d'
  $ hg log -G --rev '::.'
  @  8 d-2 re-add d
  |
  o  7 d-1 delete d
  |
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

Having another branch renaming a different file to the same filename as another

  $ hg up 'desc("i-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg mv b g
  $ hg ci -m 'e-1 b -move-> g'
  created new head
  $ hg mv g f
  $ hg ci -m 'e-2 g -move-> f'
  $ hg log -G --rev '::.'
  @  10 e-2 g -move-> f
  |
  o  9 e-1 b -move-> g
  |
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

merging with unrelated change does not interfere with the renames
---------------------------------------------------------------

- rename on one side
- unrelated change on the other side

  $ hg up 'desc("b-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("a-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mBAm-0 simple merge - one way'
  $ hg up 'desc("a-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mABm-0 simple merge - the other way'
  created new head
  $ hg log -G --rev '::(desc("mABm")+desc("mBAm"))'
  @    12 mABm-0 simple merge - the other way
  |\
  +---o  11 mBAm-0 simple merge - one way
  | |/
  | o  5 b-1: b update
  | |
  o |  4 a-2: e -move-> f
  | |
  o |  3 a-1: d -move-> e
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mABm")'
  A f
    d
  R d
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mBAm")'
  A f
    d
  R d
  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mABm")'
  M b
  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mBAm")'
  M b
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mABm")'
  M b
  A f
    d
  R d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mBAm")'
  M b
  A f
    d
  R d
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mABm")'
  M b
  A f
    a
  R a
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBAm")'
  M b
  A f
    a
  R a

merging with the side having a delete
-------------------------------------

case summary:
- one with change to an unrelated file
- one deleting the change
and recreate an unrelated file after the merge

  $ hg up 'desc("b-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("c-1")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mBCm-0 simple merge - one way'
  $ echo bar > d
  $ hg add d
  $ hg ci -m 'mBCm-1 re-add d'
  $ hg up 'desc("c-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mCBm-0 simple merge - the other way'
  created new head
  $ echo bar > d
  $ hg add d
  $ hg ci -m 'mCBm-1 re-add d'
  $ hg log -G --rev '::(desc("mCBm")+desc("mBCm"))'
  @  16 mCBm-1 re-add d
  |
  o    15 mCBm-0 simple merge - the other way
  |\
  | | o  14 mBCm-1 re-add d
  | | |
  +---o  13 mBCm-0 simple merge - one way
  | |/
  | o  6 c-1 delete d
  | |
  o |  5 b-1: b update
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  
- comparing from the merge

  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mBCm-0")'
  R d
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mCBm-0")'
  R d
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mBCm-0")'
  M b
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mCBm-0")'
  M b
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mBCm-0")'
  M b
  R d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mCBm-0")'
  M b
  R d
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBCm-0")'
  M b
  R a
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCBm-0")'
  M b
  R a

- comparing with the merge children re-adding the file

  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mBCm-1")'
  M d
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mCBm-1")'
  M d
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mBCm-1")'
  M b
  A d
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mCBm-1")'
  M b
  A d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mBCm-1")'
  M b
  M d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mCBm-1")'
  M b
  M d
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBCm-1")'
  M b
  A d
  R a
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCBm-1")'
  M b
  A d
  R a

Comparing with a merge re-adding the file afterward
---------------------------------------------------

Merge:
- one with change to an unrelated file
- one deleting and recreating the change

Note:
| In this case, one of the merge wrongly record a merge while there is none.
| This lead to bad copy tracing information to be dug up.

  $ hg up 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("d-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mBDm-0 simple merge - one way'
  $ hg up 'desc("d-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mDBm-0 simple merge - the other way'
  created new head
  $ hg log -G --rev '::(desc("mDBm")+desc("mBDm"))'
  @    18 mDBm-0 simple merge - the other way
  |\
  +---o  17 mBDm-0 simple merge - one way
  | |/
  | o  8 d-2 re-add d
  | |
  | o  7 d-1 delete d
  | |
  o |  5 b-1: b update
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mBDm-0")'
  M d
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mDBm-0")'
  M d
  $ hg status --copies --rev 'desc("d-2")' --rev 'desc("mBDm-0")'
  M b
  $ hg status --copies --rev 'desc("d-2")' --rev 'desc("mDBm-0")'
  M b
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mBDm-0")'
  M b
  M d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mDBm-0")'
  M b
  M d

The bugs makes recorded copy is different depending of where we started the merge from since

  $ hg manifest --debug --rev 'desc("mBDm-0")' | grep '644   d'
  b004912a8510032a0350a74daa2803dadfb00e12 644   d
  $ hg manifest --debug --rev 'desc("mDBm-0")' | grep '644   d'
  b004912a8510032a0350a74daa2803dadfb00e12 644   d

The 0bb5445dc4d02f4e0d86cf16f9f3a411d0f17744 entry is wrong, since the file was
deleted on one side (then recreate) and untouched on the other side, no "merge"
has happened. The resulting `d` file is the untouched version from branch `D`,
not a merge.

  $ hg manifest --debug --rev 'desc("d-2")' | grep '644   d'
  b004912a8510032a0350a74daa2803dadfb00e12 644   d
  $ hg manifest --debug --rev 'desc("b-1")' | grep '644   d'
  01c2f5eabdc4ce2bdee42b5f86311955e6c8f573 644   d
  $ hg debugindex d
     rev linkrev nodeid       p1           p2
       0       2 01c2f5eabdc4 000000000000 000000000000
       1       8 b004912a8510 000000000000 000000000000

(This `hg log` output if wrong, since no merge actually happened).

  $ hg log -Gfr 'desc("mBDm-0")' d
  o  8 d-2 re-add d
  |
  ~

This `hg log` output is correct

  $ hg log -Gfr 'desc("mDBm-0")' d
  o  8 d-2 re-add d
  |
  ~

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBDm-0")'
  M b
  A d
  R a
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mDBm-0")'
  M b
  A d
  R a


Comparing with a merge with colliding rename
--------------------------------------------

- the "e-" branch renaming b to f (through 'g')
- the "a-" branch renaming d to f (through e)

  $ hg up 'desc("a-2")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("e-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mAEm-0 simple merge - one way'
  $ hg up 'desc("e-2")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("a-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mEAm-0 simple merge - the other way'
  created new head
  $ hg log -G --rev '::(desc("mAEm")+desc("mEAm"))'
  @    20 mEAm-0 simple merge - the other way
  |\
  +---o  19 mAEm-0 simple merge - one way
  | |/
  | o  10 e-2 g -move-> f
  | |
  | o  9 e-1 b -move-> g
  | |
  o |  4 a-2: e -move-> f
  | |
  o |  3 a-1: d -move-> e
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  
  $ hg manifest --debug --rev 'desc("mAEm-0")' | grep '644   f'
  eb806e34ef6be4c264effd5933d31004ad15a793 644   f
  $ hg manifest --debug --rev 'desc("mEAm-0")' | grep '644   f'
  eb806e34ef6be4c264effd5933d31004ad15a793 644   f
  $ hg manifest --debug --rev 'desc("a-2")' | grep '644   f'
  0dd616bc7ab1a111921d95d76f69cda5c2ac539c 644   f
  $ hg manifest --debug --rev 'desc("e-2")' | grep '644   f'
  6da5a2eecb9c833f830b67a4972366d49a9a142c 644   f
  $ hg debugindex f
     rev linkrev nodeid       p1           p2
       0       4 0dd616bc7ab1 000000000000 000000000000
       1      10 6da5a2eecb9c 000000000000 000000000000
       2      19 eb806e34ef6b 0dd616bc7ab1 6da5a2eecb9c

# Here the filelog based implementation is not looking at the rename
# information (because the file exist on both side). However the changelog
# based on works fine. We have different output.

  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mAEm-0")'
  M f
    b (no-filelog !)
  R b
  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mEAm-0")'
  M f
    b (no-filelog !)
  R b
  $ hg status --copies --rev 'desc("e-2")' --rev 'desc("mAEm-0")'
  M f
    d (no-filelog !)
  R d
  $ hg status --copies --rev 'desc("e-2")' --rev 'desc("mEAm-0")'
  M f
    d (no-filelog !)
  R d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("a-2")'
  A f
    d
  R d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("e-2")'
  A f
    b
  R b

# From here, we run status against revision where both source file exists.
#
# The filelog based implementation picks an arbitrary side based on revision
# numbers. So the same side "wins" whatever the parents order is. This is
# sub-optimal because depending on revision numbers means the result can be
# different from one repository to the next.
#
# The changeset based algorithm use the parent order to break tie on conflicting
# information and will have a different order depending on who is p1 and p2.
# That order is stable accross repositories. (data from p1 prevails)

  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mAEm-0")'
  A f
    d
  R b
  R d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mEAm-0")'
  A f
    d (filelog !)
    b (no-filelog !)
  R b
  R d
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mAEm-0")'
  A f
    a
  R a
  R b
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mEAm-0")'
  A f
    a (filelog !)
    b (no-filelog !)
  R a
  R b


Note:
| In this case, one of the merge wrongly record a merge while there is none.
| This lead to bad copy tracing information to be dug up.


Merge:
- one with change to an unrelated file (b)
- one overwriting a file (d) with a rename (from h to i to d)

  $ hg up 'desc("i-2")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg mv h i
  $ hg commit -m "f-1: rename h -> i"
  created new head
  $ hg mv --force i d
  $ hg commit -m "f-2: rename i -> d"
  $ hg debugindex d
     rev linkrev nodeid       p1           p2
       0       2 01c2f5eabdc4 000000000000 000000000000
       1       8 b004912a8510 000000000000 000000000000
       2      22 c72365ee036f 000000000000 000000000000
  $ hg up 'desc("b-1")'
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("f-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mBFm-0 simple merge - one way'
  $ hg up 'desc("f-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mFBm-0 simple merge - the other way'
  created new head
  $ hg log -G --rev '::(desc("mBFm")+desc("mFBm"))'
  @    24 mFBm-0 simple merge - the other way
  |\
  +---o  23 mBFm-0 simple merge - one way
  | |/
  | o  22 f-2: rename i -> d
  | |
  | o  21 f-1: rename h -> i
  | |
  o |  5 b-1: b update
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  
The overwriting should take over. However, the behavior is currently buggy

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBFm-0")'
  M b
  A d
    h
    h (false !)
  R a
  R h
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mFBm-0")'
  M b
  A d
    h
  R a
  R h
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mBFm-0")'
  M d
    h (no-filelog !)
  R h
  $ hg status --copies --rev 'desc("f-2")' --rev 'desc("mBFm-0")'
  M b
  $ hg status --copies --rev 'desc("f-1")' --rev 'desc("mBFm-0")'
  M b
  M d
    i (no-filelog !)
  R i
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mFBm-0")'
  M d
    h (no-filelog !)
  R h
  $ hg status --copies --rev 'desc("f-2")' --rev 'desc("mFBm-0")'
  M b
  $ hg status --copies --rev 'desc("f-1")' --rev 'desc("mFBm-0")'
  M b
  M d
    i (no-filelog !)
  R i

The following graphlog is wrong, the "a -> c -> d" chain was overwritten and should not appear.

  $ hg log -Gfr 'desc("mBFm-0")' d
  o  22 f-2: rename i -> d
  |
  o  21 f-1: rename h -> i
  :
  o  0 i-0 initial commit: a b h
  

The following output is correct.

  $ hg log -Gfr 'desc("mFBm-0")' d
  o  22 f-2: rename i -> d
  |
  o  21 f-1: rename h -> i
  :
  o  0 i-0 initial commit: a b h
  


Merge:
- one with change to a file
- one deleting and recreating the file

Unlike in the 'BD/DB' cases, an actual merge happened here. So we should
consider history and rename on both branch of the merge.

  $ hg up 'desc("i-2")'
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo "some update" >> d
  $ hg commit -m "g-1: update d"
  created new head
  $ hg up 'desc("d-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("g-1")' --tool :union
  merging d
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mDGm-0 simple merge - one way'
  $ hg up 'desc("g-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("d-2")' --tool :union
  merging d
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mGDm-0 simple merge - the other way'
  created new head
  $ hg log -G --rev '::(desc("mDGm")+desc("mGDm"))'
  @    27 mGDm-0 simple merge - the other way
  |\
  +---o  26 mDGm-0 simple merge - one way
  | |/
  | o  25 g-1: update d
  | |
  o |  8 d-2 re-add d
  | |
  o |  7 d-1 delete d
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  
One side of the merge have a long history with rename. The other side of the
merge point to a new file with a smaller history. Each side is "valid".

(and again the filelog based algorithm only explore one, with a pick based on
revision numbers)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mDGm-0")'
  A d
    a (filelog !)
  R a
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mGDm-0")'
  A d
    a
  R a
  $ hg status --copies --rev 'desc("d-2")' --rev 'desc("mDGm-0")'
  M d
  $ hg status --copies --rev 'desc("d-2")' --rev 'desc("mGDm-0")'
  M d
  $ hg status --copies --rev 'desc("g-1")' --rev 'desc("mDGm-0")'
  M d
  $ hg status --copies --rev 'desc("g-1")' --rev 'desc("mGDm-0")'
  M d

  $ hg log -Gfr 'desc("mDGm-0")' d
  o    26 mDGm-0 simple merge - one way
  |\
  | o  25 g-1: update d
  | |
  o |  8 d-2 re-add d
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  


  $ hg log -Gfr 'desc("mDGm-0")' d
  o    26 mDGm-0 simple merge - one way
  |\
  | o  25 g-1: update d
  | |
  o |  8 d-2 re-add d
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  


Merge:
- one with change to a file (d)
- one overwriting that file with a rename (from h to i, to d)

This case is similar to BF/FB, but an actual merge happens, so both side of the
history are relevant.

Note:
| In this case, the merge get conflicting information since on one side we have
| "a -> c -> d". and one the other one we have "h -> i -> d".
|
| The current code arbitrarily pick one side

  $ hg up 'desc("f-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("g-1")' --tool :union
  merging d
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mFGm-0 simple merge - one way'
  created new head
  $ hg up 'desc("g-1")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("f-2")' --tool :union
  merging d
  0 files updated, 1 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mGFm-0 simple merge - the other way'
  created new head
  $ hg log -G --rev '::(desc("mGFm")+desc("mFGm"))'
  @    29 mGFm-0 simple merge - the other way
  |\
  +---o  28 mFGm-0 simple merge - one way
  | |/
  | o  25 g-1: update d
  | |
  o |  22 f-2: rename i -> d
  | |
  o |  21 f-1: rename h -> i
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mFGm-0")'
  A d
    h (no-filelog !)
    a (filelog !)
  R a
  R h
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mGFm-0")'
  A d
    a
  R a
  R h
  $ hg status --copies --rev 'desc("f-2")' --rev 'desc("mFGm-0")'
  M d
  $ hg status --copies --rev 'desc("f-2")' --rev 'desc("mGFm-0")'
  M d
  $ hg status --copies --rev 'desc("f-1")' --rev 'desc("mFGm-0")'
  M d
    i (no-filelog !)
  R i
  $ hg status --copies --rev 'desc("f-1")' --rev 'desc("mGFm-0")'
  M d
    i (no-filelog !)
  R i
  $ hg status --copies --rev 'desc("g-1")' --rev 'desc("mFGm-0")'
  M d
    h (no-filelog !)
  R h
  $ hg status --copies --rev 'desc("g-1")' --rev 'desc("mGFm-0")'
  M d
    h (no-filelog !)
  R h

  $ hg log -Gfr 'desc("mFGm-0")' d
  o    28 mFGm-0 simple merge - one way
  |\
  | o  25 g-1: update d
  | |
  o |  22 f-2: rename i -> d
  | |
  o |  21 f-1: rename h -> i
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

  $ hg log -Gfr 'desc("mGFm-0")' d
  @    29 mGFm-0 simple merge - the other way
  |\
  | o  25 g-1: update d
  | |
  o |  22 f-2: rename i -> d
  | |
  o |  21 f-1: rename h -> i
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

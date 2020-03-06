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
  > logtemplate={rev} {desc}]\n
  > EOF

  $ hg init repo-chain
  $ cd repo-chain

Add some linear rename initialy

  $ touch a b
  $ hg ci -Am 'i-0 initial commit: a b'
  adding a
  adding b
  $ hg mv a c
  $ hg ci -Am 'i-1: a -move-> c'
  $ hg mv c d
  $ hg ci -Am 'i-2: c -move-> d'
  $ hg log -G
  @  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

And having another branch with renames on the other side

  $ hg mv d e
  $ hg ci -Am 'a-1: d -move-> e'
  $ hg mv e f
  $ hg ci -Am 'a-2: e -move-> f'
  $ hg log -G --rev '::.'
  @  4 a-2: e -move-> f]
  |
  o  3 a-1: d -move-> e]
  |
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

Have a branching with nothing on one side

  $ hg up 'desc("i-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo foo > b
  $ hg ci -m 'b-1: b update'
  created new head
  $ hg log -G --rev '::.'
  @  5 b-1: b update]
  |
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  


Merge the two branches we just defined (in both directions)
- one with change to an unrelated file
- one with renames in them

  $ hg up 'desc("b-1")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
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
  @    7 mABm-0 simple merge - the other way]
  |\
  +---o  6 mBAm-0 simple merge - one way]
  | |/
  | o  5 b-1: b update]
  | |
  o |  4 a-2: e -move-> f]
  | |
  o |  3 a-1: d -move-> e]
  |/
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

Create a branch that delete a file previous renamed

  $ hg up 'desc("i-2")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg rm d
  $ hg ci -m 'c-1 delete d'
  created new head
  $ hg log -G --rev '::.'
  @  8 c-1 delete d]
  |
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

Merge:
- one with change to an unrelated file
- one deleting the change
and recreate an unrelated file after the merge

  $ hg up 'desc("b-1")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
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
  @  12 mCBm-1 re-add d]
  |
  o    11 mCBm-0 simple merge - the other way]
  |\
  | | o  10 mBCm-1 re-add d]
  | | |
  +---o  9 mBCm-0 simple merge - one way]
  | |/
  | o  8 c-1 delete d]
  | |
  o |  5 b-1: b update]
  |/
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

Create a branch that delete a file previous renamed and recreate it

  $ hg up 'desc("i-2")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg rm d
  $ hg ci -m 'd-1 delete d'
  created new head
  $ echo bar > d
  $ hg add d
  $ hg ci -m 'd-2 re-add d'
  $ hg log -G --rev '::.'
  @  14 d-2 re-add d]
  |
  o  13 d-1 delete d]
  |
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

Merge:
- one with change to an unrelated file
- one deleting and recreating the change

Note:
| In this case, the merge get conflicting information since on one side we have
| a "brand new" d. and one the other one we have "d renamed from c (itself
| renamed from c)".
|
| The current code arbitrarily pick one side

  $ hg up 'desc("b-1")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("d-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mBDm-0 simple merge - one way'
  $ hg up 'desc("d-2")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m 'mDBm-0 simple merge - the other way'
  created new head
  $ hg log -G --rev '::(desc("mDBm")+desc("mBDm"))'
  @    16 mDBm-0 simple merge - the other way]
  |\
  +---o  15 mBDm-0 simple merge - one way]
  | |/
  | o  14 d-2 re-add d]
  | |
  | o  13 d-1 delete d]
  | |
  o |  5 b-1: b update]
  |/
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

Having another branch renaming a different file to the same filename as another

  $ hg up 'desc("i-2")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg mv b g
  $ hg ci -m 'e-1 b -move-> g'
  created new head
  $ hg mv g f
  $ hg ci -m 'e-2 g -move-> f'
  $ hg log -G --rev '::.'
  @  18 e-2 g -move-> f]
  |
  o  17 e-1 b -move-> g]
  |
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

Merge:
- one with change to an unrelated file
- one deleting and recreating the change

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
  @    20 mEAm-0 simple merge - the other way]
  |\
  +---o  19 mAEm-0 simple merge - one way]
  | |/
  | o  18 e-2 g -move-> f]
  | |
  | o  17 e-1 b -move-> g]
  | |
  o |  4 a-2: e -move-> f]
  | |
  o |  3 a-1: d -move-> e]
  |/
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

Note:
| In this case, the merge get conflicting information since each side have a
| different way to reach 'f'.

final summary

  $ hg update null --quiet
  $ hg log -G
  o    20 mEAm-0 simple merge - the other way]
  |\
  +---o  19 mAEm-0 simple merge - one way]
  | |/
  | o  18 e-2 g -move-> f]
  | |
  | o  17 e-1 b -move-> g]
  | |
  | | o    16 mDBm-0 simple merge - the other way]
  | | |\
  | | +---o  15 mBDm-0 simple merge - one way]
  | | | |/
  | | | o  14 d-2 re-add d]
  | | | |
  | +---o  13 d-1 delete d]
  | | |
  | | | o  12 mCBm-1 re-add d]
  | | | |
  | | | o  11 mCBm-0 simple merge - the other way]
  | | |/|
  | | | | o  10 mBCm-1 re-add d]
  | | | | |
  | | +---o  9 mBCm-0 simple merge - one way]
  | | | |/
  | +---o  8 c-1 delete d]
  | | |
  +-----o  7 mABm-0 simple merge - the other way]
  | | |/
  +-----o  6 mBAm-0 simple merge - one way]
  | | |/
  | | o  5 b-1: b update]
  | |/
  o |  4 a-2: e -move-> f]
  | |
  o |  3 a-1: d -move-> e]
  |/
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

Check results
=============

merging with unrelated change does not interfer wit the renames
---------------------------------------------------------------

- rename on one side
- unrelated change on the other side

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

checks:
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
| In this case, the merge get conflicting information since on one side we have
| a "brand new" d. and one the other one we have "d renamed from c (itself
| renamed from c)".
|
| The current code arbitrarily pick one side

  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mBDm-0")'
  M d
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mDBm-0")'
  M d
  $ hg status --copies --rev 'desc("d-2")' --rev 'desc("mBDm-0")'
  M b
  M d
  $ hg status --copies --rev 'desc("d-2")' --rev 'desc("mDBm-0")'
  M b
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mBDm-0")'
  M b
  M d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mDBm-0")'
  M b
  M d

The recorded copy is different depending of where we started the merge from since

  $ hg manifest --debug --rev 'desc("mBDm-0")' | grep '644   d'
  0bb5445dc4d02f4e0d86cf16f9f3a411d0f17744 644   d
  $ hg manifest --debug --rev 'desc("mDBm-0")' | grep '644   d'
  b004912a8510032a0350a74daa2803dadfb00e12 644   d

This second b004912a8510032a0350a74daa2803dadfb00e12 seems wrong. We should record the merge
  $ hg manifest --debug --rev 'desc("d-2")' | grep '644   d'
  b004912a8510032a0350a74daa2803dadfb00e12 644   d
  $ hg manifest --debug --rev 'desc("b-1")' | grep '644   d'
  01c2f5eabdc4ce2bdee42b5f86311955e6c8f573 644   d
  $ hg debugindex d
     rev linkrev nodeid       p1           p2
       0       2 01c2f5eabdc4 000000000000 000000000000
       1      10 b004912a8510 000000000000 000000000000
       2      15 0bb5445dc4d0 01c2f5eabdc4 b004912a8510

  $ hg log -Gfr 'desc("mBDm-0")' d
  o    15 mBDm-0 simple merge - one way]
  |\
  o :  14 d-2 re-add d]
  :/
  o  2 i-2: c -move-> d]
  |
  o  1 i-1: a -move-> c]
  |
  o  0 i-0 initial commit: a b]
  

(That output seems wrong, if we had opportunity to record the merge, we should
probably have recorded the merge).

  $ hg log -Gfr 'desc("mDBm-0")' d
  o  14 d-2 re-add d]
  |
  ~

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBDm-0")'
  M b
  A d
    a
  R a
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mDBm-0")'
  M b
  A d
  R a

Comparing with a merge re-adding the file afterward
---------------------------------------------------

- one with change to an unrelated file
- one deleting and recreating the change

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
       1      18 6da5a2eecb9c 000000000000 000000000000
       2      19 eb806e34ef6b 0dd616bc7ab1 6da5a2eecb9c
  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mAEm-0")'
  M f
  R b
  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mEAm-0")'
  M f
  R b
  $ hg status --copies --rev 'desc("e-2")' --rev 'desc("mAEm-0")'
  M f
  R d
  $ hg status --copies --rev 'desc("e-2")' --rev 'desc("mEAm-0")'
  M f
  R d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("a-2")'
  A f
    d
  R d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("e-2")'
  A f
    b
  R b
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mAEm-0")'
  A f
    d
  R b
  R d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mEAm-0")'
  A f
    d
  R b
  R d
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mAEm-0")'
  A f
    a
  R a
  R b
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mEAm-0")'
  A f
    a
  R a
  R b

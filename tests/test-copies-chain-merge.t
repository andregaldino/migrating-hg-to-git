#testcases filelog compatibility changeset sidedata upgraded

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
  > [command-templates]
  > log={rev} {desc}\n
  > EOF

#if compatibility
  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > copies.read-from = compatibility
  > EOF
#endif

#if changeset
  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > copies.read-from = changeset-only
  > copies.write-to = changeset-only
  > EOF
#endif

#if sidedata
  $ cat >> $HGRCPATH << EOF
  > [format]
  > exp-use-side-data = yes
  > exp-use-copies-side-data-changeset = yes
  > EOF
#endif


  $ cat > same-content.txt << EOF
  > Here is some content that will be the same accros multiple file.
  > 
  > This is done on purpose so that we end up in some merge situation, were the
  > resulting content is the same as in the parent(s), but a new filenodes still
  > need to be created to record some file history information (especially
  > about copies).
  > EOF

  $ hg init repo-chain
  $ cd repo-chain

Add some linear rename initialy

  $ cp ../same-content.txt a
  $ cp ../same-content.txt b
  $ cp ../same-content.txt h
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
  

Setup all merge
===============

This is done beforehand to validate that the upgrade process creates valid copy
information.

merging with unrelated change does not interfere with the renames
---------------------------------------------------------------

- rename on one side
- unrelated change on the other side

  $ case_desc="simple merge - A side: multiple renames, B side: unrelated update"

  $ hg up 'desc("b-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("a-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mBAm-0 $case_desc - one way"
  $ hg up 'desc("a-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mABm-0 $case_desc - the other way"
  created new head
  $ hg log -G --rev '::(desc("mABm")+desc("mBAm"))'
  @    12 mABm-0 simple merge - A side: multiple renames, B side: unrelated update - the other way
  |\
  +---o  11 mBAm-0 simple merge - A side: multiple renames, B side: unrelated update - one way
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
  


merging with the side having a delete
-------------------------------------

case summary:
- one with change to an unrelated file
- one deleting the change
and recreate an unrelated file after the merge

  $ case_desc="simple merge - C side: delete a file with copies history , B side: unrelated update"

  $ hg up 'desc("b-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("c-1")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mBCm-0 $case_desc - one way"
  $ echo bar > d
  $ hg add d
  $ hg ci -m 'mBCm-1 re-add d'
  $ hg up 'desc("c-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mCBm-0 $case_desc - the other way"
  created new head
  $ echo bar > d
  $ hg add d
  $ hg ci -m 'mCBm-1 re-add d'
  $ hg log -G --rev '::(desc("mCBm")+desc("mBCm"))'
  @  16 mCBm-1 re-add d
  |
  o    15 mCBm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - the other way
  |\
  | | o  14 mBCm-1 re-add d
  | | |
  +---o  13 mBCm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - one way
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
  

Comparing with a merge re-adding the file afterward
---------------------------------------------------

Merge:
- one with change to an unrelated file
- one deleting and recreating the change

  $ case_desc="simple merge - B side: unrelated update, D side: delete and recreate a file (with different content)"

  $ hg up 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("d-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mBDm-0 $case_desc - one way"
  $ hg up 'desc("d-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mDBm-0 $case_desc - the other way"
  created new head
  $ hg log -G --rev '::(desc("mDBm")+desc("mBDm"))'
  @    18 mDBm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - the other way
  |\
  +---o  17 mBDm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - one way
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
  


Comparing with a merge with colliding rename
--------------------------------------------

- the "e-" branch renaming b to f (through 'g')
- the "a-" branch renaming d to f (through e)

  $ case_desc="simple merge"

  $ hg up 'desc("a-2")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("e-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ hg ci -m "mAEm-0 $case_desc - one way"
  $ hg up 'desc("e-2")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved (no-changeset !)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (changeset !)
  $ hg merge 'desc("a-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ hg ci -m "mEAm-0 $case_desc - the other way"
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
  


Merge:
- one with change to an unrelated file (b)
- one overwriting a file (d) with a rename (from h to i to d)

  $ case_desc="simple merge"

  $ hg up 'desc("i-2")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg mv h i
  $ hg commit -m "f-1: rename h -> i"
  created new head
  $ hg mv --force i d
  $ hg commit -m "f-2: rename i -> d"
  $ hg debugindex d
     rev linkrev nodeid       p1           p2
       0       2 d8252ab2e760 000000000000 000000000000 (no-changeset !)
       0       2 ae258f702dfe 000000000000 000000000000 (changeset !)
       1       8 b004912a8510 000000000000 000000000000
       2      22 7b79e2fe0c89 000000000000 000000000000 (no-changeset !)
  $ hg up 'desc("b-1")'
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved (no-changeset !)
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved (changeset !)
  $ hg merge 'desc("f-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ hg ci -m "mBFm-0 $case_desc - one way"
  $ hg up 'desc("f-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mFBm-0 $case_desc - the other way"
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
  


Merge:
- one with change to a file
- one deleting and recreating the file

Unlike in the 'BD/DB' cases, an actual merge happened here. So we should
consider history and rename on both branch of the merge.

  $ case_desc="simple merge"

  $ hg up 'desc("i-2")'
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved (no-changeset !)
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved (changeset !)
  $ echo "some update" >> d
  $ hg commit -m "g-1: update d"
  created new head
  $ hg up 'desc("d-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("g-1")' --tool :union
  merging d
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mDGm-0 $case_desc - one way"
  $ hg up 'desc("g-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("d-2")' --tool :union
  merging d
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mGDm-0 $case_desc - the other way"
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

  $ case_desc="simple merge"

  $ hg up 'desc("f-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("g-1")' --tool :union
  merging d (no-changeset !)
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved (no-changeset !)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ hg ci -m "mFGm-0 $case_desc - one way"
  created new head
  $ hg up 'desc("g-1")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved (no-changeset !)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (changeset !)
  $ hg merge 'desc("f-2")' --tool :union
  merging d (no-changeset !)
  0 files updated, 1 files merged, 1 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ hg ci -m "mGFm-0 $case_desc - the other way"
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
  


Comparing with merging with a deletion (and keeping the file)
-------------------------------------------------------------

Merge:
- one removing a file (d)
- one updating that file
- the merge keep the modified version of the file (canceling the delete)

In this case, the file keep on living after the merge. So we should not drop its
copy tracing chain.

  $ hg up 'desc("c-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("g-1")'
  file 'd' was deleted in local [working copy] but was modified in other [merge rev].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ hg resolve -t :other d
  (no more unresolved files)
  $ hg ci -m "mCGm-0"
  created new head

  $ hg up 'desc("g-1")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("c-1")'
  file 'd' was deleted in other [merge rev] but was modified in local [working copy].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ hg resolve -t :local d
  (no more unresolved files)
  $ hg ci -m "mGCm-0"
  created new head

  $ hg log -G --rev '::(desc("mCGm")+desc("mGCm"))'
  @    31 mGCm-0
  |\
  +---o  30 mCGm-0
  | |/
  | o  25 g-1: update d
  | |
  o |  6 c-1 delete d
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  



Comparing with merge restoring an untouched deleted file
--------------------------------------------------------

Merge:
- one removing a file (d)
- one leaving the file untouched
- the merge actively restore the file to the same content.

In this case, the file keep on living after the merge. So we should not drop its
copy tracing chain.

  $ hg up 'desc("c-1")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg revert --rev 'desc("b-1")' d
  $ hg ci -m "mCB-revert-m-0"
  created new head

  $ hg up 'desc("b-1")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("c-1")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg revert --rev 'desc("b-1")' d
  $ hg ci -m "mBC-revert-m-0"
  created new head

  $ hg log -G --rev '::(desc("mCB-revert-m")+desc("mBC-revert-m"))'
  @    33 mBC-revert-m-0
  |\
  +---o  32 mCB-revert-m-0
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
  


  $ hg up null --quiet

Merging a branch where a rename was deleted with a branch where the same file was renamed
------------------------------------------------------------------------------------------

Create a "conflicting" merge where `d` get removed on one branch before its
rename information actually conflict with the other branch.

(the copy information from the branch that was not deleted should win).

  $ hg up 'desc("i-0")'
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg mv b d
  $ hg ci -m "h-1: b -(move)-> d"
  created new head

  $ hg up 'desc("c-1")'
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg merge 'desc("h-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mCH-delete-before-conflict-m-0"

  $ hg up 'desc("h-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("c-1")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mHC-delete-before-conflict-m-0"
  created new head
  $ hg log -G --rev '::(desc("mCH-delete-before-conflict-m")+desc("mHC-delete-before-conflict-m"))'
  @    36 mHC-delete-before-conflict-m-0
  |\
  +---o  35 mCH-delete-before-conflict-m-0
  | |/
  | o  34 h-1: b -(move)-> d
  | |
  o |  6 c-1 delete d
  | |
  o |  2 i-2: c -move-> d
  | |
  o |  1 i-1: a -move-> c
  |/
  o  0 i-0 initial commit: a b h
  


Summary of all created cases
----------------------------

  $ hg up --quiet null

(This exists to help keeping a compact list of the various cases we have built)

  $ hg log -T '{desc|firstline}\n'| sort
  a-1: d -move-> e
  a-2: e -move-> f
  b-1: b update
  c-1 delete d
  d-1 delete d
  d-2 re-add d
  e-1 b -move-> g
  e-2 g -move-> f
  f-1: rename h -> i
  f-2: rename i -> d
  g-1: update d
  h-1: b -(move)-> d
  i-0 initial commit: a b h
  i-1: a -move-> c
  i-2: c -move-> d
  mABm-0 simple merge - A side: multiple renames, B side: unrelated update - the other way
  mAEm-0 simple merge - one way
  mBAm-0 simple merge - A side: multiple renames, B side: unrelated update - one way
  mBC-revert-m-0
  mBCm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - one way
  mBCm-1 re-add d
  mBDm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - one way
  mBFm-0 simple merge - one way
  mCB-revert-m-0
  mCBm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - the other way
  mCBm-1 re-add d
  mCGm-0
  mCH-delete-before-conflict-m-0
  mDBm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - the other way
  mDGm-0 simple merge - one way
  mEAm-0 simple merge - the other way
  mFBm-0 simple merge - the other way
  mFGm-0 simple merge - one way
  mGCm-0
  mGDm-0 simple merge - the other way
  mGFm-0 simple merge - the other way
  mHC-delete-before-conflict-m-0


Test that sidedata computations during upgrades are correct
===========================================================

We upgrade a repository that is not using sidedata (the filelog case) and
 check that the same side data have been generated as if they were computed at
 commit time.


#if upgraded
  $ cat >> $HGRCPATH << EOF
  > [format]
  > exp-use-side-data = yes
  > exp-use-copies-side-data-changeset = yes
  > EOF
  $ hg debugformat -v
  format-variant     repo config default
  fncache:            yes    yes     yes
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:          no     no      no
  sparserevlog:       yes    yes     yes
  sidedata:            no    yes      no
  persistent-nodemap:  no     no      no
  copies-sdc:          no    yes      no
  plain-cl-delta:     yes    yes     yes
  compression:        * (glob)
  compression-level:  default default default
  $ hg debugupgraderepo --run --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: * (glob)
     added: exp-copies-sidedata-changeset, exp-sidedata-flag
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
#endif


#if no-compatibility no-filelog no-changeset

  $ hg debugchangedfiles --compute 0
  added      : a, ;
  added      : b, ;
  added      : h, ;

  $ for rev in `hg log --rev 'all()' -T '{rev}\n'`; do
  >     echo "##### revision $rev #####"
  >     hg debugsidedata -c -v -- $rev
  >     hg debugchangedfiles $rev
  > done
  ##### revision 0 #####
  1 sidedata entries
   entry-0014 size 34
    '\x00\x00\x00\x03\x04\x00\x00\x00\x01\x00\x00\x00\x00\x04\x00\x00\x00\x02\x00\x00\x00\x00\x04\x00\x00\x00\x03\x00\x00\x00\x00abh'
  added      : a, ;
  added      : b, ;
  added      : h, ;
  ##### revision 1 #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00ac'
  removed    : a, ;
  added    p1: c, a;
  ##### revision 2 #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00cd'
  removed    : c, ;
  added    p1: d, c;
  ##### revision 3 #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00de'
  removed    : d, ;
  added    p1: e, d;
  ##### revision 4 #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00ef'
  removed    : e, ;
  added    p1: f, e;
  ##### revision 5 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x14\x00\x00\x00\x01\x00\x00\x00\x00b'
  touched    : b, ;
  ##### revision 6 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x0c\x00\x00\x00\x01\x00\x00\x00\x00d'
  removed    : d, ;
  ##### revision 7 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x0c\x00\x00\x00\x01\x00\x00\x00\x00d'
  removed    : d, ;
  ##### revision 8 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x04\x00\x00\x00\x01\x00\x00\x00\x00d'
  added      : d, ;
  ##### revision 9 #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00bg'
  removed    : b, ;
  added    p1: g, b;
  ##### revision 10 #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x06\x00\x00\x00\x01\x00\x00\x00\x01\x0c\x00\x00\x00\x02\x00\x00\x00\x00fg'
  added    p1: f, g;
  removed    : g, ;
  ##### revision 11 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision 12 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision 13 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision 14 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x04\x00\x00\x00\x01\x00\x00\x00\x00d'
  added      : d, ;
  ##### revision 15 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision 16 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x04\x00\x00\x00\x01\x00\x00\x00\x00d'
  added      : d, ;
  ##### revision 17 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision 18 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision 19 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00f'
  merged     : f, ;
  ##### revision 20 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00f'
  merged     : f, ;
  ##### revision 21 #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00hi'
  removed    : h, ;
  added    p1: i, h;
  ##### revision 22 #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x16\x00\x00\x00\x01\x00\x00\x00\x01\x0c\x00\x00\x00\x02\x00\x00\x00\x00di'
  touched  p1: d, i;
  removed    : i, ;
  ##### revision 23 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision 24 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision 25 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x14\x00\x00\x00\x01\x00\x00\x00\x00d'
  touched    : d, ;
  ##### revision 26 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00d'
  merged     : d, ;
  ##### revision 27 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00d'
  merged     : d, ;
  ##### revision 28 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00d'
  merged     : d, ;
  ##### revision 29 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00d'
  merged     : d, ;
  ##### revision 30 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x10\x00\x00\x00\x01\x00\x00\x00\x00d'
  salvaged   : d, ;
  ##### revision 31 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x10\x00\x00\x00\x01\x00\x00\x00\x00d'
  salvaged   : d, ;
  ##### revision 32 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x10\x00\x00\x00\x01\x00\x00\x00\x00d'
  salvaged   : d, ;
  ##### revision 33 #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x10\x00\x00\x00\x01\x00\x00\x00\x00d'
  salvaged   : d, ;
  ##### revision 34 #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00bd'
  removed    : b, ;
  added    p1: d, b;
  ##### revision 35 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision 36 #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'

#endif


Test copy information chaining
==============================

Check that matching only affect the destination and not intermediate path
-------------------------------------------------------------------------

The two status call should give the same value for f

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("a-2")'
  A f
    a
  R a
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("a-2")' f
  A f
    a (no-changeset no-compatibility !)

merging with unrelated change does not interfere with the renames
---------------------------------------------------------------

- rename on one side
- unrelated change on the other side

  $ hg log -G --rev '::(desc("mABm")+desc("mBAm"))'
  o    12 mABm-0 simple merge - A side: multiple renames, B side: unrelated update - the other way
  |\
  +---o  11 mBAm-0 simple merge - A side: multiple renames, B side: unrelated update - one way
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

  $ hg log -G --rev '::(desc("mCBm")+desc("mBCm"))'
  o  16 mCBm-1 re-add d
  |
  o    15 mCBm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - the other way
  |\
  | | o  14 mBCm-1 re-add d
  | | |
  +---o  13 mBCm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - one way
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

  $ hg log -G --rev '::(desc("mDBm")+desc("mBDm"))'
  o    18 mDBm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - the other way
  |\
  +---o  17 mBDm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - one way
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

  $ hg manifest --debug --rev 'desc("d-2")' | grep '644   d'
  b004912a8510032a0350a74daa2803dadfb00e12 644   d
  $ hg manifest --debug --rev 'desc("b-1")' | grep '644   d'
  d8252ab2e760b0d4e5288fd44cbd15a0fa567e16 644   d (no-changeset !)
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   d (changeset !)
  $ hg debugindex d | head -n 4
     rev linkrev nodeid       p1           p2
       0       2 d8252ab2e760 000000000000 000000000000 (no-changeset !)
       0       2 ae258f702dfe 000000000000 000000000000 (changeset !)
       1       8 b004912a8510 000000000000 000000000000
       2      22 7b79e2fe0c89 000000000000 000000000000 (no-changeset !)
       2      25 5cce88bf349f ae258f702dfe 000000000000 (changeset !)

Log output should not include a merge commit as it did not happen

  $ hg log -Gfr 'desc("mBDm-0")' d
  o  8 d-2 re-add d
  |
  ~

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

  $ hg log -G --rev '::(desc("mAEm")+desc("mEAm"))'
  o    20 mEAm-0 simple merge - the other way
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
  
#if no-changeset
  $ hg manifest --debug --rev 'desc("mAEm-0")' | grep '644   f'
  2ff93c643948464ee1f871867910ae43a45b0bea 644   f
  $ hg manifest --debug --rev 'desc("mEAm-0")' | grep '644   f'
  2ff93c643948464ee1f871867910ae43a45b0bea 644   f
  $ hg manifest --debug --rev 'desc("a-2")' | grep '644   f'
  b76eb76580df486c3d51d63c5c210d4dd43a8ac7 644   f
  $ hg manifest --debug --rev 'desc("e-2")' | grep '644   f'
  e8825b386367b29fec957283a80bb47b47483fe1 644   f
  $ hg debugindex f
     rev linkrev nodeid       p1           p2
       0       4 b76eb76580df 000000000000 000000000000
       1      10 e8825b386367 000000000000 000000000000
       2      19 2ff93c643948 b76eb76580df e8825b386367
#else
  $ hg manifest --debug --rev 'desc("mAEm-0")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg manifest --debug --rev 'desc("mEAm-0")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg manifest --debug --rev 'desc("a-2")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg manifest --debug --rev 'desc("e-2")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg debugindex f
     rev linkrev nodeid       p1           p2
       0       4 ae258f702dfe 000000000000 000000000000
#endif

# Here the filelog based implementation is not looking at the rename
# information (because the file exist on both side). However the changelog
# based on works fine. We have different output.

  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mAEm-0")'
  M f (no-changeset !)
    b (no-filelog no-changeset !)
  R b
  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mEAm-0")'
  M f (no-changeset !)
    b (no-filelog no-changeset !)
  R b
  $ hg status --copies --rev 'desc("e-2")' --rev 'desc("mAEm-0")'
  M f (no-changeset !)
    d (no-filelog no-changeset !)
  R d
  $ hg status --copies --rev 'desc("e-2")' --rev 'desc("mEAm-0")'
  M f (no-changeset !)
    d (no-filelog no-changeset !)
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

  $ hg log -G --rev '::(desc("mBFm")+desc("mFBm"))'
  o    24 mFBm-0 simple merge - the other way
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
  
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBFm-0")'
  M b
  A d
    h
  R a
  R h
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mFBm-0")'
  M b
  A d
    h
  R a
  R h
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mBFm-0")'
  M d (no-changeset !)
    h (no-filelog no-changeset !)
  R h
  $ hg status --copies --rev 'desc("f-2")' --rev 'desc("mBFm-0")'
  M b
  $ hg status --copies --rev 'desc("f-1")' --rev 'desc("mBFm-0")'
  M b
  M d (no-changeset !)
    i (no-filelog no-changeset !)
  R i
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mFBm-0")'
  M d (no-changeset !)
    h (no-filelog no-changeset !)
  R h
  $ hg status --copies --rev 'desc("f-2")' --rev 'desc("mFBm-0")'
  M b
  $ hg status --copies --rev 'desc("f-1")' --rev 'desc("mFBm-0")'
  M b
  M d (no-changeset !)
    i (no-filelog no-changeset !)
  R i

#if no-changeset
  $ hg log -Gfr 'desc("mBFm-0")' d
  o  22 f-2: rename i -> d
  |
  o  21 f-1: rename h -> i
  :
  o  0 i-0 initial commit: a b h
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mBFm-0")' d
  o  2 i-2: c -move-> d
  |
  ~
#endif

#if no-changeset
  $ hg log -Gfr 'desc("mFBm-0")' d
  o  22 f-2: rename i -> d
  |
  o  21 f-1: rename h -> i
  :
  o  0 i-0 initial commit: a b h
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mFBm-0")' d
  o  2 i-2: c -move-> d
  |
  ~
#endif


Merge:
- one with change to a file
- one deleting and recreating the file

Unlike in the 'BD/DB' cases, an actual merge happened here. So we should
consider history and rename on both branch of the merge.

  $ hg log -G --rev '::(desc("mDGm")+desc("mGDm"))'
  o    27 mGDm-0 simple merge - the other way
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

#if no-changeset
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
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mDGm-0")' d
  o    26 mDGm-0 simple merge - one way
  |\
  | o  25 g-1: update d
  | |
  o |  8 d-2 re-add d
  |/
  o  2 i-2: c -move-> d
  |
  ~
#endif


#if no-changeset
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
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mDGm-0")' d
  o    26 mDGm-0 simple merge - one way
  |\
  | o  25 g-1: update d
  | |
  o |  8 d-2 re-add d
  |/
  o  2 i-2: c -move-> d
  |
  ~
#endif


Merge:
- one with change to a file (d)
- one overwriting that file with a rename (from h to i, to d)

This case is similar to BF/FB, but an actual merge happens, so both side of the
history are relevant.


  $ hg log -G --rev '::(desc("mGFm")+desc("mFGm"))'
  o    29 mGFm-0 simple merge - the other way
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
  

Note:
| In this case, the merge get conflicting information since on one side we have
| "a -> c -> d". and one the other one we have "h -> i -> d".
|
| The current code arbitrarily pick one side depending the ordering of the merged hash:

In this case, the file hash from "f-2" is lower, so it will be `p1` of the resulting filenode its copy tracing information will win (and trace back to "h"):

Details on this hash ordering pick:

  $ hg manifest --debug 'desc("g-1")' | egrep 'd$'
  17ec97e605773eb44a117d1136b3849bcdc1924f 644   d (no-changeset !)
  5cce88bf349f7c742bb440f2c53f81db9c294279 644   d (changeset !)
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("g-1")' d
  A d
    a (no-changeset no-compatibility !)

  $ hg manifest --debug 'desc("f-2")' | egrep 'd$'
  7b79e2fe0c8924e0e598a82f048a7b024afa4d96 644   d (no-changeset !)
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   d (changeset !)
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("f-2")' d
  A d
    h (no-changeset no-compatibility !)

Copy tracing data on the resulting merge:

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mFGm-0")'
  A d
    h (no-filelog !)
    a (filelog !)
  R a
  R h
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mGFm-0")'
  A d
    a (no-changeset !)
    h (changeset !)
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
  M d (no-changeset !)
    h (no-filelog no-changeset !)
  R h
  $ hg status --copies --rev 'desc("g-1")' --rev 'desc("mGFm-0")'
  M d (no-changeset !)
    h (no-filelog no-changeset !)
  R h

#if no-changeset
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
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mFGm-0")' d
  o  25 g-1: update d
  |
  o  2 i-2: c -move-> d
  |
  ~
#endif

#if no-changeset
  $ hg log -Gfr 'desc("mGFm-0")' d
  o    29 mGFm-0 simple merge - the other way
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
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mGFm-0")' d
  o  25 g-1: update d
  |
  o  2 i-2: c -move-> d
  |
  ~
#endif


Comparing with merging with a deletion (and keeping the file)
-------------------------------------------------------------

Merge:
- one removing a file (d)
- one updating that file
- the merge keep the modified version of the file (canceling the delete)

In this case, the file keep on living after the merge. So we should not drop its
copy tracing chain.

  $ hg log -G --rev '::(desc("mCGm")+desc("mGCm"))'
  o    31 mGCm-0
  |\
  +---o  30 mCGm-0
  | |/
  | o  25 g-1: update d
  | |
  o |  6 c-1 delete d
  |/
  o  2 i-2: c -move-> d
  |
  o  1 i-1: a -move-> c
  |
  o  0 i-0 initial commit: a b h
  

'a' is the copy source of 'd'

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCGm-0")'
  A d
    a (no-compatibility no-changeset !)
  R a
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mGCm-0")'
  A d
    a (no-compatibility no-changeset !)
  R a
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mCGm-0")'
  A d
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mGCm-0")'
  A d
  $ hg status --copies --rev 'desc("g-1")' --rev 'desc("mCGm-0")'
  $ hg status --copies --rev 'desc("g-1")' --rev 'desc("mGCm-0")'


Comparing with merge restoring an untouched deleted file
--------------------------------------------------------

Merge:
- one removing a file (d)
- one leaving the file untouched
- the merge actively restore the file to the same content.

In this case, the file keep on living after the merge. So we should not drop its
copy tracing chain.

  $ hg log -G --rev '::(desc("mCB-revert-m")+desc("mBC-revert-m"))'
  o    33 mBC-revert-m-0
  |\
  +---o  32 mCB-revert-m-0
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
  

'a' is the the copy source of 'd'

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCB-revert-m-0")'
  M b
  A d
    a (no-compatibility no-changeset !)
  R a
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBC-revert-m-0")'
  M b
  A d
    a (no-compatibility no-changeset !)
  R a
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mCB-revert-m-0")'
  M b
  A d
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mBC-revert-m-0")'
  M b
  A d
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mCB-revert-m-0")'
  $ hg status --copies --rev 'desc("b-1")' --rev 'desc("mBC-revert-m-0")'


Merging a branch where a rename was deleted with a branch where the same file was renamed
------------------------------------------------------------------------------------------

Create a "conflicting" merge where `d` get removed on one branch before its
rename information actually conflict with the other branch.

(the copy information from the branch that was not deleted should win).

  $ hg log -G --rev '::(desc("mCH-delete-before-conflict-m")+desc("mHC-delete-before-conflict-m"))'
  o    36 mHC-delete-before-conflict-m-0
  |\
  +---o  35 mCH-delete-before-conflict-m-0
  | |/
  | o  34 h-1: b -(move)-> d
  | |
  o |  6 c-1 delete d
  | |
  o |  2 i-2: c -move-> d
  | |
  o |  1 i-1: a -move-> c
  |/
  o  0 i-0 initial commit: a b h
  

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCH-delete-before-conflict-m")'
  A d
    b (no-compatibility no-changeset !)
  R a
  R b
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mHC-delete-before-conflict-m")'
  A d
    b
  R a
  R b
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mCH-delete-before-conflict-m")'
  A d
    b
  R b
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mHC-delete-before-conflict-m")'
  A d
    b
  R b
  $ hg status --copies --rev 'desc("h-1")' --rev 'desc("mCH-delete-before-conflict-m")'
  R a
  $ hg status --copies --rev 'desc("h-1")' --rev 'desc("mHC-delete-before-conflict-m")'
  R a

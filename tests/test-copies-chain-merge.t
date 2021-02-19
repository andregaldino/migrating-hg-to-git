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

  $ cat << EOF >> ./no-linkrev
  > #!$PYTHON
  > # filter out linkrev part of the debugindex command
  > import sys
  > for line in sys.stdin:
  >     if " linkrev " in line:
  >         print(line.rstrip())
  >     else:
  >         l = "%s       *%s" % (line[:6], line[14:].rstrip())
  >         print(l)
  > EOF
  $ chmod +x no-linkrev

  $ cat << EOF >> $HGRCPATH
  > [diff]
  > git=yes
  > [command-templates]
  > log={desc}\n
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
  $ echo "original content for P" > p
  $ echo "original content for Q" > q
  $ echo "original content for R" > r
  $ hg ci -Am 'i-0 initial commit: a b h'
  adding a
  adding b
  adding h
  adding p
  adding q
  adding r
  $ hg mv a c
  $ hg mv p s
  $ hg ci -Am 'i-1: a -move-> c, p -move-> s'
  $ hg mv c d
  $ hg mv s t
  $ hg ci -Am 'i-2: c -move-> d, s -move-> t'
  $ hg log -G
  @  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

And having another branch with renames on the other side

  $ hg mv d e
  $ hg ci -Am 'a-1: d -move-> e'
  $ hg mv e f
  $ hg ci -Am 'a-2: e -move-> f'
  $ hg log -G --rev '::.'
  @  a-2: e -move-> f
  |
  o  a-1: d -move-> e
  |
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

Have a branching with nothing on one side

  $ hg up 'desc("i-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo foo > b
  $ hg ci -m 'b-1: b update'
  created new head
  $ hg log -G --rev '::.'
  @  b-1: b update
  |
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

Create a branch that delete a file previous renamed

  $ hg up 'desc("i-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg rm d
  $ hg ci -m 'c-1 delete d'
  created new head
  $ hg log -G --rev '::.'
  @  c-1 delete d
  |
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

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
  @  d-2 re-add d
  |
  o  d-1 delete d
  |
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

Having another branch renaming a different file to the same filename as another

  $ hg up 'desc("i-2")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg mv b g
  $ hg ci -m 'e-1 b -move-> g'
  created new head
  $ hg mv g f
  $ hg ci -m 'e-2 g -move-> f'
  $ hg log -G --rev '::.'
  @  e-2 g -move-> f
  |
  o  e-1 b -move-> g
  |
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

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
  @    mABm-0 simple merge - A side: multiple renames, B side: unrelated update - the other way
  |\
  +---o  mBAm-0 simple merge - A side: multiple renames, B side: unrelated update - one way
  | |/
  | o  b-1: b update
  | |
  o |  a-2: e -move-> f
  | |
  o |  a-1: d -move-> e
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  


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
  @  mCBm-1 re-add d
  |
  o    mCBm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - the other way
  |\
  | | o  mBCm-1 re-add d
  | | |
  +---o  mBCm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - one way
  | |/
  | o  c-1 delete d
  | |
  o |  b-1: b update
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

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
  @    mDBm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - the other way
  |\
  +---o  mBDm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - one way
  | |/
  | o  d-2 re-add d
  | |
  | o  d-1 delete d
  | |
  o |  b-1: b update
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  


Comparing with a merge with colliding rename
--------------------------------------------

Subcase: new copy information on both side
``````````````````````````````````````````

- the "e-" branch renaming b to f (through 'g')
- the "a-" branch renaming d to f (through e)

  $ case_desc="merge with copies info on both side - A side: rename d to f, E side: b to f, (same content for f)"

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
  @    mEAm-0 merge with copies info on both side - A side: rename d to f, E side: b to f, (same content for f) - the other way
  |\
  +---o  mAEm-0 merge with copies info on both side - A side: rename d to f, E side: b to f, (same content for f) - one way
  | |/
  | o  e-2 g -move-> f
  | |
  | o  e-1 b -move-> g
  | |
  o |  a-2: e -move-> f
  | |
  o |  a-1: d -move-> e
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

Subcase: existing copy information overwritten on one branch
````````````````````````````````````````````````````````````

Merge:
- one with change to an unrelated file (b)
- one overwriting a file (d) with a rename (from h to i to d)

  $ case_desc="simple merge - B side: unrelated change, F side: overwrite d with a copy (from h->i->d)"

  $ hg up 'desc("i-2")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg mv h i
  $ hg commit -m "f-1: rename h -> i"
  created new head
  $ hg mv --force i d
  $ hg commit -m "f-2: rename i -> d"
  $ hg debugindex d | ../no-linkrev
     rev linkrev nodeid       p1           p2
       0       * d8252ab2e760 000000000000 000000000000 (no-changeset !)
       0       * ae258f702dfe 000000000000 000000000000 (changeset !)
       1       * b004912a8510 000000000000 000000000000
       2       * 7b79e2fe0c89 000000000000 000000000000 (no-changeset !)
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
  @    mFBm-0 simple merge - B side: unrelated change, F side: overwrite d with a copy (from h->i->d) - the other way
  |\
  +---o  mBFm-0 simple merge - B side: unrelated change, F side: overwrite d with a copy (from h->i->d) - one way
  | |/
  | o  f-2: rename i -> d
  | |
  | o  f-1: rename h -> i
  | |
  o |  b-1: b update
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  


Subcase: reset of the copy history on one side
``````````````````````````````````````````````

Merge:
- one with change to a file
- one deleting and recreating the file

Unlike in the 'BD/DB' cases, an actual merge happened here. So we should
consider history and rename on both branch of the merge.

  $ case_desc="actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content"

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
  @    mGDm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - the other way
  |\
  +---o  mDGm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - one way
  | |/
  | o  g-1: update d
  | |
  o |  d-2 re-add d
  | |
  o |  d-1 delete d
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

Subcase: merging a change to a file with a "copy overwrite" to that file from another branch
````````````````````````````````````````````````````````````````````````````````````````````

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

  $ case_desc="merge - G side: content change, F side: copy overwrite, no content change"

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
  @    mGFm-0 merge - G side: content change, F side: copy overwrite, no content change - the other way
  |\
  +---o  mFGm-0 merge - G side: content change, F side: copy overwrite, no content change - one way
  | |/
  | o  g-1: update d
  | |
  o |  f-2: rename i -> d
  | |
  o |  f-1: rename h -> i
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  


Comparing with merging with a deletion (and keeping the file)
-------------------------------------------------------------

Merge:
- one removing a file (d)
- one updating that file
- the merge keep the modified version of the file (canceling the delete)

In this case, the file keep on living after the merge. So we should not drop its
copy tracing chain.

  $ case_desc="merge updated/deleted - revive the file (updated content)"

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
  $ hg ci -m "mCGm-0 $case_desc - one way"
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
  $ hg ci -m "mGCm-0 $case_desc - the other way"
  created new head

  $ hg log -G --rev '::(desc("mCGm")+desc("mGCm"))'
  @    mGCm-0 merge updated/deleted - revive the file (updated content) - the other way
  |\
  +---o  mCGm-0 merge updated/deleted - revive the file (updated content) - one way
  | |/
  | o  g-1: update d
  | |
  o |  c-1 delete d
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  



Comparing with merge restoring an untouched deleted file
--------------------------------------------------------

Merge:
- one removing a file (d)
- one leaving the file untouched
- the merge actively restore the file to the same content.

In this case, the file keep on living after the merge. So we should not drop its
copy tracing chain.

  $ case_desc="merge explicitely revive deleted file - B side: unrelated change, C side: delete d (restored by merge)"

  $ hg up 'desc("c-1")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("b-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg revert --rev 'desc("b-1")' d
  $ hg ci -m "mCB-revert-m-0 $case_desc - one way"
  created new head

  $ hg up 'desc("b-1")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("c-1")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg revert --rev 'desc("b-1")' d
  $ hg ci -m "mBC-revert-m-0 $case_desc - the other way"
  created new head

  $ hg log -G --rev '::(desc("mCB-revert-m")+desc("mBC-revert-m"))'
  @    mBC-revert-m-0 merge explicitely revive deleted file - B side: unrelated change, C side: delete d (restored by merge) - the other way
  |\
  +---o  mCB-revert-m-0 merge explicitely revive deleted file - B side: unrelated change, C side: delete d (restored by merge) - one way
  | |/
  | o  c-1 delete d
  | |
  o |  b-1: b update
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  


  $ hg up null --quiet

Merging a branch where a rename was deleted with a branch where the same file was renamed
------------------------------------------------------------------------------------------

Create a "conflicting" merge where `d` get removed on one branch before its
rename information actually conflict with the other branch.

(the copy information from the branch that was not deleted should win).

  $ case_desc="simple merge - C side: d is the results of renames then deleted, H side: d is result of another rename (same content as the other branch)"

  $ hg up 'desc("i-0")'
  6 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg mv b d
  $ hg ci -m "h-1: b -(move)-> d"
  created new head

  $ hg up 'desc("c-1")'
  2 files updated, 0 files merged, 3 files removed, 0 files unresolved
  $ hg merge 'desc("h-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mCH-delete-before-conflict-m-0 $case_desc - one way"

  $ hg up 'desc("h-1")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("c-1")'
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mHC-delete-before-conflict-m-0 $case_desc - the other way"
  created new head
  $ hg log -G --rev '::(desc("mCH-delete-before-conflict-m")+desc("mHC-delete-before-conflict-m"))'
  @    mHC-delete-before-conflict-m-0 simple merge - C side: d is the results of renames then deleted, H side: d is result of another rename (same content as the other branch) - the other way
  |\
  +---o  mCH-delete-before-conflict-m-0 simple merge - C side: d is the results of renames then deleted, H side: d is result of another rename (same content as the other branch) - one way
  | |/
  | o  h-1: b -(move)-> d
  | |
  o |  c-1 delete d
  | |
  o |  i-2: c -move-> d, s -move-> t
  | |
  o |  i-1: a -move-> c, p -move-> s
  |/
  o  i-0 initial commit: a b h
  

Variant of previous with extra changes introduced by the merge
--------------------------------------------------------------

Multiple cases above explicitely test cases where content are the same on both side during merge. In this section we will introduce variants for theses cases where new change are introduced to these file content during the merges.


Subcase: merge has same initial content on both side, but merge introduced a change
```````````````````````````````````````````````````````````````````````````````````

Same as `mAEm` and `mEAm` but with extra change to the file before commiting

- the "e-" branch renaming b to f (through 'g')
- the "a-" branch renaming d to f (through e)

  $ case_desc="merge with file update and copies info on both side - A side: rename d to f, E side: b to f, (same content for f in parent)"

  $ hg up 'desc("a-2")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("e-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ echo "content change for mAE-change-m" > f
  $ hg ci -m "mAE-change-m-0 $case_desc - one way"
  created new head
  $ hg up 'desc("e-2")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("a-2")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ echo "content change for mEA-change-m" > f
  $ hg ci -m "mEA-change-m-0 $case_desc - the other way"
  created new head
  $ hg log -G --rev '::(desc("mAE-change-m")+desc("mEA-change-m"))'
  @    mEA-change-m-0 merge with file update and copies info on both side - A side: rename d to f, E side: b to f, (same content for f in parent) - the other way
  |\
  +---o  mAE-change-m-0 merge with file update and copies info on both side - A side: rename d to f, E side: b to f, (same content for f in parent) - one way
  | |/
  | o  e-2 g -move-> f
  | |
  | o  e-1 b -move-> g
  | |
  o |  a-2: e -move-> f
  | |
  o |  a-1: d -move-> e
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

Decision from previous merge are properly chained with later merge
------------------------------------------------------------------

Subcase: chaining conflicting rename resolution
```````````````````````````````````````````````

The "mAEm" and "mEAm" case create a rename tracking conflict on file 'f'. We
add more change on the respective branch and merge again. These second merge
does not involve the file 'f' and the arbitration done within "mAEm" and "mEA"
about that file should stay unchanged.

  $ case_desc="chained merges (conflict -> simple) - same content everywhere"

(extra unrelated changes)

  $ hg up 'desc("a-2")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo j > unrelated-j
  $ hg add unrelated-j
  $ hg ci -m 'j-1: unrelated changes (based on the "a" series of changes)'
  created new head

  $ hg up 'desc("e-2")'
  2 files updated, 0 files merged, 2 files removed, 0 files unresolved (no-changeset !)
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved (changeset !)
  $ echo k > unrelated-k
  $ hg add unrelated-k
  $ hg ci -m 'k-1: unrelated changes (based on "e" changes)'
  created new head

(merge variant 1)

  $ hg up 'desc("mAEm")'
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved (changeset !)
  $ hg merge 'desc("k-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mAE,Km: $case_desc"

(merge variant 2)

  $ hg up 'desc("k-1")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved (no-changeset !)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (changeset !)

  $ hg merge 'desc("mAEm")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ hg ci -m "mK,AEm: $case_desc"
  created new head

(merge variant 3)

  $ hg up 'desc("mEAm")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("j-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mEA,Jm: $case_desc"

(merge variant 4)

  $ hg up 'desc("j-1")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved (no-changeset !)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (changeset !)
  $ hg merge 'desc("mEAm")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ hg ci -m "mJ,EAm: $case_desc"
  created new head


  $ hg log -G --rev '::(desc("mAE,Km") + desc("mK,AEm") + desc("mEA,Jm") + desc("mJ,EAm"))'
  @    mJ,EAm: chained merges (conflict -> simple) - same content everywhere
  |\
  +---o  mEA,Jm: chained merges (conflict -> simple) - same content everywhere
  | |/
  | | o    mK,AEm: chained merges (conflict -> simple) - same content everywhere
  | | |\
  | | +---o  mAE,Km: chained merges (conflict -> simple) - same content everywhere
  | | | |/
  | | | o  k-1: unrelated changes (based on "e" changes)
  | | | |
  | o | |  j-1: unrelated changes (based on the "a" series of changes)
  | | | |
  o-----+  mEAm-0 merge with copies info on both side - A side: rename d to f, E side: b to f, (same content for f) - the other way
  |/ / /
  | o /  mAEm-0 merge with copies info on both side - A side: rename d to f, E side: b to f, (same content for f) - one way
  |/|/
  | o  e-2 g -move-> f
  | |
  | o  e-1 b -move-> g
  | |
  o |  a-2: e -move-> f
  | |
  o |  a-1: d -move-> e
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

Subcase: chaining salvage information during a merge
````````````````````````````````````````````````````

We add more change on the branch were the file was deleted. merging again
should preserve the fact eh file was salvaged.

  $ case_desc="chained merges (salvaged -> simple) - same content (when the file exists)"

(creating the change)

  $ hg up 'desc("c-1")'
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ echo l > unrelated-l
  $ hg add unrelated-l
  $ hg ci -m 'l-1: unrelated changes (based on "c" changes)'
  created new head

(Merge variant 1)

  $ hg up 'desc("mBC-revert-m")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("l-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mBC+revert,Lm: $case_desc"

(Merge variant 2)

  $ hg up 'desc("mCB-revert-m")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("l-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mCB+revert,Lm: $case_desc"

(Merge variant 3)

  $ hg up 'desc("l-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved

  $ hg merge 'desc("mBC-revert-m")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mL,BC+revertm: $case_desc"
  created new head

(Merge variant 4)

  $ hg up 'desc("l-1")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved

  $ hg merge 'desc("mCB-revert-m")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mL,CB+revertm: $case_desc"
  created new head

  $ hg log -G --rev '::(desc("mBC+revert,Lm") + desc("mCB+revert,Lm") + desc("mL,BC+revertm") + desc("mL,CB+revertm"))'
  @    mL,CB+revertm: chained merges (salvaged -> simple) - same content (when the file exists)
  |\
  | | o  mL,BC+revertm: chained merges (salvaged -> simple) - same content (when the file exists)
  | |/|
  +-+---o  mCB+revert,Lm: chained merges (salvaged -> simple) - same content (when the file exists)
  | | |
  | +---o  mBC+revert,Lm: chained merges (salvaged -> simple) - same content (when the file exists)
  | | |/
  | o |  l-1: unrelated changes (based on "c" changes)
  | | |
  | | o  mBC-revert-m-0 merge explicitely revive deleted file - B side: unrelated change, C side: delete d (restored by merge) - the other way
  | |/|
  o---+  mCB-revert-m-0 merge explicitely revive deleted file - B side: unrelated change, C side: delete d (restored by merge) - one way
  |/ /
  o |  c-1 delete d
  | |
  | o  b-1: b update
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  


Subcase: chaining "merged" information during a merge
``````````````````````````````````````````````````````

When a non-rename change are merged with a copy overwrite, the merge pick the copy source from (p1) as the reference. We should preserve this information in subsequent merges.

  $ case_desc="chained merges (copy-overwrite -> simple) - same content"

(extra unrelated changes)

  $ hg up 'desc("f-2")'
  2 files updated, 0 files merged, 2 files removed, 0 files unresolved (no-changeset !)
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved (changeset !)
  $ echo n > unrelated-n
  $ hg add unrelated-n
  $ hg ci -m 'n-1: unrelated changes (based on the "f" series of changes)'
  created new head

  $ hg up 'desc("g-1")'
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo o > unrelated-o
  $ hg add unrelated-o
  $ hg ci -m 'o-1: unrelated changes (based on "g" changes)'
  created new head

(merge variant 1)

  $ hg up 'desc("mFGm")'
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved (changeset !)
  $ hg merge 'desc("o-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mFG,Om: $case_desc"

(merge variant 2)

  $ hg up 'desc("o-1")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved (no-changeset !)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (changeset !)
  $ hg merge 'desc("FGm")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved (no-changeset !)
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (changeset !)
  (branch merge, don't forget to commit)
  $ hg ci -m "mO,FGm: $case_desc"
  created new head

(merge variant 3)

  $ hg up 'desc("mGFm")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("n-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mGF,Nm: $case_desc"

(merge variant 4)

  $ hg up 'desc("n-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("mGFm")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mN,GFm: $case_desc"
  created new head

  $ hg log -G --rev '::(desc("mFG,Om") + desc("mO,FGm") + desc("mGF,Nm") + desc("mN,GFm"))'
  @    mN,GFm: chained merges (copy-overwrite -> simple) - same content
  |\
  +---o  mGF,Nm: chained merges (copy-overwrite -> simple) - same content
  | |/
  | | o    mO,FGm: chained merges (copy-overwrite -> simple) - same content
  | | |\
  | | +---o  mFG,Om: chained merges (copy-overwrite -> simple) - same content
  | | | |/
  | | | o  o-1: unrelated changes (based on "g" changes)
  | | | |
  | o | |  n-1: unrelated changes (based on the "f" series of changes)
  | | | |
  o-----+  mGFm-0 merge - G side: content change, F side: copy overwrite, no content change - the other way
  |/ / /
  | o /  mFGm-0 merge - G side: content change, F side: copy overwrite, no content change - one way
  |/|/
  | o  g-1: update d
  | |
  o |  f-2: rename i -> d
  | |
  o |  f-1: rename h -> i
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

Subcase: chaining conflicting rename resolution, with extra change during the merge
```````````````````````````````````````````````````````````````````````````````````

The "mEA-change-m-0" and "mAE-change-m-0" case create a rename tracking conflict on file 'f'. We
add more change on the respective branch and merge again. These second merge
does not involve the file 'f' and the arbitration done within "mAEm" and "mEA"
about that file should stay unchanged.

  $ case_desc="chained merges (conflict+change -> simple) - same content on both branch in the initial merge"


(merge variant 1)

  $ hg up 'desc("mAE-change-m")'
  2 files updated, 0 files merged, 3 files removed, 0 files unresolved
  $ hg merge 'desc("k-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mAE-change,Km: $case_desc"

(merge variant 2)

  $ hg up 'desc("k-1")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ hg merge 'desc("mAE-change-m")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mK,AE-change-m: $case_desc"
  created new head

(merge variant 3)

  $ hg up 'desc("mEA-change-m")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge 'desc("j-1")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mEA-change,Jm: $case_desc"

(merge variant 4)

  $ hg up 'desc("j-1")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("mEA-change-m")'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "mJ,EA-change-m: $case_desc"
  created new head


  $ hg log -G --rev '::(desc("mAE-change,Km") + desc("mK,AE-change-m") + desc("mEA-change,Jm") + desc("mJ,EA-change-m"))'
  @    mJ,EA-change-m: chained merges (conflict+change -> simple) - same content on both branch in the initial merge
  |\
  +---o  mEA-change,Jm: chained merges (conflict+change -> simple) - same content on both branch in the initial merge
  | |/
  | | o    mK,AE-change-m: chained merges (conflict+change -> simple) - same content on both branch in the initial merge
  | | |\
  | | +---o  mAE-change,Km: chained merges (conflict+change -> simple) - same content on both branch in the initial merge
  | | | |/
  | | | o  k-1: unrelated changes (based on "e" changes)
  | | | |
  | o | |  j-1: unrelated changes (based on the "a" series of changes)
  | | | |
  o-----+  mEA-change-m-0 merge with file update and copies info on both side - A side: rename d to f, E side: b to f, (same content for f in parent) - the other way
  |/ / /
  | o /  mAE-change-m-0 merge with file update and copies info on both side - A side: rename d to f, E side: b to f, (same content for f in parent) - one way
  |/|/
  | o  e-2 g -move-> f
  | |
  | o  e-1 b -move-> g
  | |
  o |  a-2: e -move-> f
  | |
  o |  a-1: d -move-> e
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

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
  i-1: a -move-> c, p -move-> s
  i-2: c -move-> d, s -move-> t
  j-1: unrelated changes (based on the "a" series of changes)
  k-1: unrelated changes (based on "e" changes)
  l-1: unrelated changes (based on "c" changes)
  mABm-0 simple merge - A side: multiple renames, B side: unrelated update - the other way
  mAE,Km: chained merges (conflict -> simple) - same content everywhere
  mAE-change,Km: chained merges (conflict+change -> simple) - same content on both branch in the initial merge
  mAE-change-m-0 merge with file update and copies info on both side - A side: rename d to f, E side: b to f, (same content for f in parent) - one way
  mAEm-0 merge with copies info on both side - A side: rename d to f, E side: b to f, (same content for f) - one way
  mBAm-0 simple merge - A side: multiple renames, B side: unrelated update - one way
  mBC+revert,Lm: chained merges (salvaged -> simple) - same content (when the file exists)
  mBC-revert-m-0 merge explicitely revive deleted file - B side: unrelated change, C side: delete d (restored by merge) - the other way
  mBCm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - one way
  mBCm-1 re-add d
  mBDm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - one way
  mBFm-0 simple merge - B side: unrelated change, F side: overwrite d with a copy (from h->i->d) - one way
  mCB+revert,Lm: chained merges (salvaged -> simple) - same content (when the file exists)
  mCB-revert-m-0 merge explicitely revive deleted file - B side: unrelated change, C side: delete d (restored by merge) - one way
  mCBm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - the other way
  mCBm-1 re-add d
  mCGm-0 merge updated/deleted - revive the file (updated content) - one way
  mCH-delete-before-conflict-m-0 simple merge - C side: d is the results of renames then deleted, H side: d is result of another rename (same content as the other branch) - one way
  mDBm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - the other way
  mDGm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - one way
  mEA,Jm: chained merges (conflict -> simple) - same content everywhere
  mEA-change,Jm: chained merges (conflict+change -> simple) - same content on both branch in the initial merge
  mEA-change-m-0 merge with file update and copies info on both side - A side: rename d to f, E side: b to f, (same content for f in parent) - the other way
  mEAm-0 merge with copies info on both side - A side: rename d to f, E side: b to f, (same content for f) - the other way
  mFBm-0 simple merge - B side: unrelated change, F side: overwrite d with a copy (from h->i->d) - the other way
  mFG,Om: chained merges (copy-overwrite -> simple) - same content
  mFGm-0 merge - G side: content change, F side: copy overwrite, no content change - one way
  mGCm-0 merge updated/deleted - revive the file (updated content) - the other way
  mGDm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - the other way
  mGF,Nm: chained merges (copy-overwrite -> simple) - same content
  mGFm-0 merge - G side: content change, F side: copy overwrite, no content change - the other way
  mHC-delete-before-conflict-m-0 simple merge - C side: d is the results of renames then deleted, H side: d is result of another rename (same content as the other branch) - the other way
  mJ,EA-change-m: chained merges (conflict+change -> simple) - same content on both branch in the initial merge
  mJ,EAm: chained merges (conflict -> simple) - same content everywhere
  mK,AE-change-m: chained merges (conflict+change -> simple) - same content on both branch in the initial merge
  mK,AEm: chained merges (conflict -> simple) - same content everywhere
  mL,BC+revertm: chained merges (salvaged -> simple) - same content (when the file exists)
  mL,CB+revertm: chained merges (salvaged -> simple) - same content (when the file exists)
  mN,GFm: chained merges (copy-overwrite -> simple) - same content
  mO,FGm: chained merges (copy-overwrite -> simple) - same content
  n-1: unrelated changes (based on the "f" series of changes)
  o-1: unrelated changes (based on "g" changes)


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
  added      : p, ;
  added      : q, ;
  added      : r, ;

  $ for rev in `hg log --rev 'all()' -T '{rev}\n'`; do
  >     case_id=`hg log -r $rev -T '{word(0, desc, ":")}\n'`
  >     echo "##### revision \"$case_id\" #####"
  >     hg debugsidedata -c -v -- $rev
  >     hg debugchangedfiles $rev
  > done
  ##### revision "i-0 initial commit" #####
  1 sidedata entries
   entry-0014 size 64
    '\x00\x00\x00\x06\x04\x00\x00\x00\x01\x00\x00\x00\x00\x04\x00\x00\x00\x02\x00\x00\x00\x00\x04\x00\x00\x00\x03\x00\x00\x00\x00\x04\x00\x00\x00\x04\x00\x00\x00\x00\x04\x00\x00\x00\x05\x00\x00\x00\x00\x04\x00\x00\x00\x06\x00\x00\x00\x00abhpqr'
  added      : a, ;
  added      : b, ;
  added      : h, ;
  added      : p, ;
  added      : q, ;
  added      : r, ;
  ##### revision "i-1" #####
  1 sidedata entries
   entry-0014 size 44
    '\x00\x00\x00\x04\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00\x0c\x00\x00\x00\x03\x00\x00\x00\x00\x06\x00\x00\x00\x04\x00\x00\x00\x02acps'
  removed    : a, ;
  added    p1: c, a;
  removed    : p, ;
  added    p1: s, p;
  ##### revision "i-2" #####
  1 sidedata entries
   entry-0014 size 44
    '\x00\x00\x00\x04\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00\x0c\x00\x00\x00\x03\x00\x00\x00\x00\x06\x00\x00\x00\x04\x00\x00\x00\x02cdst'
  removed    : c, ;
  added    p1: d, c;
  removed    : s, ;
  added    p1: t, s;
  ##### revision "a-1" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00de'
  removed    : d, ;
  added    p1: e, d;
  ##### revision "a-2" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00ef'
  removed    : e, ;
  added    p1: f, e;
  ##### revision "b-1" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x14\x00\x00\x00\x01\x00\x00\x00\x00b'
  touched    : b, ;
  ##### revision "c-1 delete d" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x0c\x00\x00\x00\x01\x00\x00\x00\x00d'
  removed    : d, ;
  ##### revision "d-1 delete d" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x0c\x00\x00\x00\x01\x00\x00\x00\x00d'
  removed    : d, ;
  ##### revision "d-2 re-add d" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x04\x00\x00\x00\x01\x00\x00\x00\x00d'
  added      : d, ;
  ##### revision "e-1 b -move-> g" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00bg'
  removed    : b, ;
  added    p1: g, b;
  ##### revision "e-2 g -move-> f" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x06\x00\x00\x00\x01\x00\x00\x00\x01\x0c\x00\x00\x00\x02\x00\x00\x00\x00fg'
  added    p1: f, g;
  removed    : g, ;
  ##### revision "mBAm-0 simple merge - A side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mABm-0 simple merge - A side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mBCm-0 simple merge - C side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mBCm-1 re-add d" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x04\x00\x00\x00\x01\x00\x00\x00\x00d'
  added      : d, ;
  ##### revision "mCBm-0 simple merge - C side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mCBm-1 re-add d" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x04\x00\x00\x00\x01\x00\x00\x00\x00d'
  added      : d, ;
  ##### revision "mBDm-0 simple merge - B side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mDBm-0 simple merge - B side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mAEm-0 merge with copies info on both side - A side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00f'
  merged     : f, ;
  ##### revision "mEAm-0 merge with copies info on both side - A side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00f'
  merged     : f, ;
  ##### revision "f-1" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00hi'
  removed    : h, ;
  added    p1: i, h;
  ##### revision "f-2" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x16\x00\x00\x00\x01\x00\x00\x00\x01\x0c\x00\x00\x00\x02\x00\x00\x00\x00di'
  touched  p1: d, i;
  removed    : i, ;
  ##### revision "mBFm-0 simple merge - B side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mFBm-0 simple merge - B side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "g-1" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x14\x00\x00\x00\x01\x00\x00\x00\x00d'
  touched    : d, ;
  ##### revision "mDGm-0 actual content merge, copies on one side - D side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00d'
  merged     : d, ;
  ##### revision "mGDm-0 actual content merge, copies on one side - D side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00d'
  merged     : d, ;
  ##### revision "mFGm-0 merge - G side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00d'
  merged     : d, ;
  ##### revision "mGFm-0 merge - G side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00d'
  merged     : d, ;
  ##### revision "mCGm-0 merge updated/deleted - revive the file (updated content) - one way" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x10\x00\x00\x00\x01\x00\x00\x00\x00d'
  salvaged   : d, ;
  ##### revision "mGCm-0 merge updated/deleted - revive the file (updated content) - the other way" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x10\x00\x00\x00\x01\x00\x00\x00\x00d'
  salvaged   : d, ;
  ##### revision "mCB-revert-m-0 merge explicitely revive deleted file - B side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x10\x00\x00\x00\x01\x00\x00\x00\x00d'
  salvaged   : d, ;
  ##### revision "mBC-revert-m-0 merge explicitely revive deleted file - B side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x10\x00\x00\x00\x01\x00\x00\x00\x00d'
  salvaged   : d, ;
  ##### revision "h-1" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00bd'
  removed    : b, ;
  added    p1: d, b;
  ##### revision "mCH-delete-before-conflict-m-0 simple merge - C side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mHC-delete-before-conflict-m-0 simple merge - C side" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mAE-change-m-0 merge with file update and copies info on both side - A side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00f'
  merged     : f, ;
  ##### revision "mEA-change-m-0 merge with file update and copies info on both side - A side" #####
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x08\x00\x00\x00\x01\x00\x00\x00\x00f'
  merged     : f, ;
  ##### revision "j-1" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x01\x04\x00\x00\x00\x0b\x00\x00\x00\x00unrelated-j'
  added      : unrelated-j, ;
  ##### revision "k-1" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x01\x04\x00\x00\x00\x0b\x00\x00\x00\x00unrelated-k'
  added      : unrelated-k, ;
  ##### revision "mAE,Km" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mK,AEm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mEA,Jm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mJ,EAm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "l-1" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x01\x04\x00\x00\x00\x0b\x00\x00\x00\x00unrelated-l'
  added      : unrelated-l, ;
  ##### revision "mBC+revert,Lm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mCB+revert,Lm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mL,BC+revertm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mL,CB+revertm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "n-1" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x01\x04\x00\x00\x00\x0b\x00\x00\x00\x00unrelated-n'
  added      : unrelated-n, ;
  ##### revision "o-1" #####
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x01\x04\x00\x00\x00\x0b\x00\x00\x00\x00unrelated-o'
  added      : unrelated-o, ;
  ##### revision "mFG,Om" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mO,FGm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mGF,Nm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mN,GFm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mAE-change,Km" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mK,AE-change-m" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mEA-change,Jm" #####
  1 sidedata entries
   entry-0014 size 4
    '\x00\x00\x00\x00'
  ##### revision "mJ,EA-change-m" #####
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
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("a-2")' f
  A f
    a (no-changeset no-compatibility !)

merging with unrelated change does not interfere with the renames
---------------------------------------------------------------

- rename on one side
- unrelated change on the other side

  $ hg log -G --rev '::(desc("mABm")+desc("mBAm"))'
  o    mABm-0 simple merge - A side: multiple renames, B side: unrelated update - the other way
  |\
  +---o  mBAm-0 simple merge - A side: multiple renames, B side: unrelated update - one way
  | |/
  | o  b-1: b update
  | |
  o |  a-2: e -move-> f
  | |
  o |  a-1: d -move-> e
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

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
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBAm")'
  M b
  A f
    a
  A t
    p
  R a
  R p

merging with the side having a delete
-------------------------------------

case summary:
- one with change to an unrelated file
- one deleting the change
and recreate an unrelated file after the merge

  $ hg log -G --rev '::(desc("mCBm")+desc("mBCm"))'
  o  mCBm-1 re-add d
  |
  o    mCBm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - the other way
  |\
  | | o  mBCm-1 re-add d
  | | |
  +---o  mBCm-0 simple merge - C side: delete a file with copies history , B side: unrelated update - one way
  | |/
  | o  c-1 delete d
  | |
  o |  b-1: b update
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
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
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCBm-0")'
  M b
  A t
    p
  R a
  R p

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
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCBm-1")'
  M b
  A d
  A t
    p
  R a
  R p

Comparing with a merge re-adding the file afterward
---------------------------------------------------

Merge:
- one with change to an unrelated file
- one deleting and recreating the change

  $ hg log -G --rev '::(desc("mDBm")+desc("mBDm"))'
  o    mDBm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - the other way
  |\
  +---o  mBDm-0 simple merge - B side: unrelated update, D side: delete and recreate a file (with different content) - one way
  | |/
  | o  d-2 re-add d
  | |
  | o  d-1 delete d
  | |
  o |  b-1: b update
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
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
  $ hg debugindex d | head -n 4 | ../no-linkrev
     rev linkrev nodeid       p1           p2
       0       * d8252ab2e760 000000000000 000000000000 (no-changeset !)
       0       * ae258f702dfe 000000000000 000000000000 (changeset !)
       1       * b004912a8510 000000000000 000000000000
       2       * 7b79e2fe0c89 000000000000 000000000000 (no-changeset !)
       2       * 5cce88bf349f ae258f702dfe 000000000000 (changeset !)

Log output should not include a merge commit as it did not happen

  $ hg log -Gfr 'desc("mBDm-0")' d
  o  d-2 re-add d
  |
  ~

  $ hg log -Gfr 'desc("mDBm-0")' d
  o  d-2 re-add d
  |
  ~

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBDm-0")'
  M b
  A d
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mDBm-0")'
  M b
  A d
  A t
    p
  R a
  R p


Comparing with a merge with colliding rename
--------------------------------------------

Subcase: new copy information on both side
``````````````````````````````````````````

- the "e-" branch renaming b to f (through 'g')
- the "a-" branch renaming d to f (through e)

  $ hg log -G --rev '::(desc("mAEm")+desc("mEAm"))'
  o    mEAm-0 merge with copies info on both side - A side: rename d to f, E side: b to f, (same content for f) - the other way
  |\
  +---o  mAEm-0 merge with copies info on both side - A side: rename d to f, E side: b to f, (same content for f) - one way
  | |/
  | o  e-2 g -move-> f
  | |
  | o  e-1 b -move-> g
  | |
  o |  a-2: e -move-> f
  | |
  o |  a-1: d -move-> e
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
#if no-changeset
  $ hg manifest --debug --rev 'desc("mAEm-0")' | grep '644   f'
  2ff93c643948464ee1f871867910ae43a45b0bea 644   f
  $ hg manifest --debug --rev 'desc("mEAm-0")' | grep '644   f'
  2ff93c643948464ee1f871867910ae43a45b0bea 644   f
  $ hg manifest --debug --rev 'desc("a-2")' | grep '644   f'
  b76eb76580df486c3d51d63c5c210d4dd43a8ac7 644   f
  $ hg manifest --debug --rev 'desc("e-2")' | grep '644   f'
  e8825b386367b29fec957283a80bb47b47483fe1 644   f
  $ hg debugindex f | ../no-linkrev
     rev linkrev nodeid       p1           p2
       0       * b76eb76580df 000000000000 000000000000
       1       * e8825b386367 000000000000 000000000000
       2       * 2ff93c643948 b76eb76580df e8825b386367
       3       * 2f649fba7eb2 b76eb76580df e8825b386367
       4       * 774e7c1637d5 e8825b386367 b76eb76580df
#else
  $ hg manifest --debug --rev 'desc("mAEm-0")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg manifest --debug --rev 'desc("mEAm-0")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg manifest --debug --rev 'desc("a-2")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg manifest --debug --rev 'desc("e-2")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg debugindex f | ../no-linkrev
     rev linkrev nodeid       p1           p2
       0       * ae258f702dfe 000000000000 000000000000
       1       * d3613c1ec831 ae258f702dfe 000000000000
       2       * 05e03c868bbc ae258f702dfe 000000000000
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
  A t
    p
  R a
  R b
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mEAm-0")'
  A f
    a (filelog !)
    b (no-filelog !)
  A t
    p
  R a
  R b
  R p


Subcase: existing copy information overwritten on one branch
````````````````````````````````````````````````````````````

Note:
| In this case, one of the merge wrongly record a merge while there is none.
| This lead to bad copy tracing information to be dug up.


Merge:
- one with change to an unrelated file (b)
- one overwriting a file (d) with a rename (from h to i to d)

  $ hg log -G --rev '::(desc("mBFm")+desc("mFBm"))'
  o    mFBm-0 simple merge - B side: unrelated change, F side: overwrite d with a copy (from h->i->d) - the other way
  |\
  +---o  mBFm-0 simple merge - B side: unrelated change, F side: overwrite d with a copy (from h->i->d) - one way
  | |/
  | o  f-2: rename i -> d
  | |
  | o  f-1: rename h -> i
  | |
  o |  b-1: b update
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBFm-0")'
  M b
  A d
    h
  A t
    p
  R a
  R h
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mFBm-0")'
  M b
  A d
    h
  A t
    p
  R a
  R h
  R p
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
  o  f-2: rename i -> d
  |
  o  f-1: rename h -> i
  :
  o  i-0 initial commit: a b h
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mBFm-0")' d
  o  i-2: c -move-> d, s -move-> t
  |
  ~
#endif

#if no-changeset
  $ hg log -Gfr 'desc("mFBm-0")' d
  o  f-2: rename i -> d
  |
  o  f-1: rename h -> i
  :
  o  i-0 initial commit: a b h
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mFBm-0")' d
  o  i-2: c -move-> d, s -move-> t
  |
  ~
#endif

Subcase: reset of the copy history on one side
``````````````````````````````````````````````

Merge:
- one with change to a file
- one deleting and recreating the file

Unlike in the 'BD/DB' cases, an actual merge happened here. So we should
consider history and rename on both branch of the merge.

  $ hg log -G --rev '::(desc("mDGm")+desc("mGDm"))'
  o    mGDm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - the other way
  |\
  +---o  mDGm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - one way
  | |/
  | o  g-1: update d
  | |
  o |  d-2 re-add d
  | |
  o |  d-1 delete d
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
One side of the merge have a long history with rename. The other side of the
merge point to a new file with a smaller history. Each side is "valid".

(and again the filelog based algorithm only explore one, with a pick based on
revision numbers)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mDGm-0")'
  A d
    a (filelog !)
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mGDm-0")'
  A d
    a
  A t
    p
  R a
  R p
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
  o    mDGm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - one way
  |\
  | o  g-1: update d
  | |
  o |  d-2 re-add d
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mDGm-0")' d
  o    mDGm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - one way
  |\
  | o  g-1: update d
  | |
  o |  d-2 re-add d
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  ~
#endif


#if no-changeset
  $ hg log -Gfr 'desc("mDGm-0")' d
  o    mDGm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - one way
  |\
  | o  g-1: update d
  | |
  o |  d-2 re-add d
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mDGm-0")' d
  o    mDGm-0 actual content merge, copies on one side - D side: delete and re-add (different content), G side: update content - one way
  |\
  | o  g-1: update d
  | |
  o |  d-2 re-add d
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  ~
#endif

Subcase: merging a change to a file with a "copy overwrite" to that file from another branch
````````````````````````````````````````````````````````````````````````````````````````````

Merge:
- one with change to a file (d)
- one overwriting that file with a rename (from h to i, to d)

This case is similar to BF/FB, but an actual merge happens, so both side of the
history are relevant.


  $ hg log -G --rev '::(desc("mGFm")+desc("mFGm"))'
  o    mGFm-0 merge - G side: content change, F side: copy overwrite, no content change - the other way
  |\
  +---o  mFGm-0 merge - G side: content change, F side: copy overwrite, no content change - one way
  | |/
  | o  g-1: update d
  | |
  o |  f-2: rename i -> d
  | |
  o |  f-1: rename h -> i
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

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
  A t
    p
  R a
  R h
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mGFm-0")'
  A d
    a (no-changeset !)
    h (changeset !)
  A t
    p
  R a
  R h
  R p
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
  o    mFGm-0 merge - G side: content change, F side: copy overwrite, no content change - one way
  |\
  | o  g-1: update d
  | |
  o |  f-2: rename i -> d
  | |
  o |  f-1: rename h -> i
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mFGm-0")' d
  o  g-1: update d
  |
  o  i-2: c -move-> d, s -move-> t
  |
  ~
#endif

#if no-changeset
  $ hg log -Gfr 'desc("mGFm-0")' d
  o    mGFm-0 merge - G side: content change, F side: copy overwrite, no content change - the other way
  |\
  | o  g-1: update d
  | |
  o |  f-2: rename i -> d
  | |
  o |  f-1: rename h -> i
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
#else
BROKEN: `hg log --follow <file>` relies on filelog metadata to work
  $ hg log -Gfr 'desc("mGFm-0")' d
  o  g-1: update d
  |
  o  i-2: c -move-> d, s -move-> t
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
  o    mGCm-0 merge updated/deleted - revive the file (updated content) - the other way
  |\
  +---o  mCGm-0 merge updated/deleted - revive the file (updated content) - one way
  | |/
  | o  g-1: update d
  | |
  o |  c-1 delete d
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

'a' is the copy source of 'd'

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCGm-0")'
  A d
    a (no-compatibility no-changeset !)
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mGCm-0")'
  A d
    a (no-compatibility no-changeset !)
  A t
    p
  R a
  R p
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
  o    mBC-revert-m-0 merge explicitely revive deleted file - B side: unrelated change, C side: delete d (restored by merge) - the other way
  |\
  +---o  mCB-revert-m-0 merge explicitely revive deleted file - B side: unrelated change, C side: delete d (restored by merge) - one way
  | |/
  | o  c-1 delete d
  | |
  o |  b-1: b update
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  

'a' is the the copy source of 'd'

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCB-revert-m-0")'
  M b
  A d
    a (no-compatibility no-changeset !)
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBC-revert-m-0")'
  M b
  A d
    a (no-compatibility no-changeset !)
  A t
    p
  R a
  R p
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
  o    mHC-delete-before-conflict-m-0 simple merge - C side: d is the results of renames then deleted, H side: d is result of another rename (same content as the other branch) - the other way
  |\
  +---o  mCH-delete-before-conflict-m-0 simple merge - C side: d is the results of renames then deleted, H side: d is result of another rename (same content as the other branch) - one way
  | |/
  | o  h-1: b -(move)-> d
  | |
  o |  c-1 delete d
  | |
  o |  i-2: c -move-> d, s -move-> t
  | |
  o |  i-1: a -move-> c, p -move-> s
  |/
  o  i-0 initial commit: a b h
  

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCH-delete-before-conflict-m")'
  A d
    b (no-compatibility no-changeset !)
  A t
    p
  R a
  R b
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mHC-delete-before-conflict-m")'
  A d
    b
  A t
    p
  R a
  R b
  R p
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mCH-delete-before-conflict-m")'
  A d
    b
  R b
  $ hg status --copies --rev 'desc("c-1")' --rev 'desc("mHC-delete-before-conflict-m")'
  A d
    b
  R b
  $ hg status --copies --rev 'desc("h-1")' --rev 'desc("mCH-delete-before-conflict-m")'
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("h-1")' --rev 'desc("mHC-delete-before-conflict-m")'
  A t
    p
  R a
  R p

Variant of previous with extra changes introduced by the merge
--------------------------------------------------------------

(see case declaration for details)

Subcase: merge has same initial content on both side, but merge introduced a change
```````````````````````````````````````````````````````````````````````````````````

- the "e-" branch renaming b to f (through 'g')
- the "a-" branch renaming d to f (through e)
- the merge add new change to b

  $ hg log -G --rev '::(desc("mAE-change-m")+desc("mEA-change-m"))'
  o    mEA-change-m-0 merge with file update and copies info on both side - A side: rename d to f, E side: b to f, (same content for f in parent) - the other way
  |\
  +---o  mAE-change-m-0 merge with file update and copies info on both side - A side: rename d to f, E side: b to f, (same content for f in parent) - one way
  | |/
  | o  e-2 g -move-> f
  | |
  | o  e-1 b -move-> g
  | |
  o |  a-2: e -move-> f
  | |
  o |  a-1: d -move-> e
  |/
  o  i-2: c -move-> d, s -move-> t
  |
  o  i-1: a -move-> c, p -move-> s
  |
  o  i-0 initial commit: a b h
  
#if no-changeset
  $ hg manifest --debug --rev 'desc("mAE-change-m-0")' | grep '644   f'
  2f649fba7eb284e720d02b61f0546fcef694c045 644   f
  $ hg manifest --debug --rev 'desc("mEA-change-m-0")' | grep '644   f'
  774e7c1637d536b99e2d8ef16fd731f87a82bd09 644   f
  $ hg manifest --debug --rev 'desc("a-2")' | grep '644   f'
  b76eb76580df486c3d51d63c5c210d4dd43a8ac7 644   f
  $ hg manifest --debug --rev 'desc("e-2")' | grep '644   f'
  e8825b386367b29fec957283a80bb47b47483fe1 644   f
  $ hg debugindex f | ../no-linkrev
     rev linkrev nodeid       p1           p2
       0       * b76eb76580df 000000000000 000000000000
       1       * e8825b386367 000000000000 000000000000
       2       * 2ff93c643948 b76eb76580df e8825b386367
       3       * 2f649fba7eb2 b76eb76580df e8825b386367
       4       * 774e7c1637d5 e8825b386367 b76eb76580df
#else
  $ hg manifest --debug --rev 'desc("mAE-change-m-0")' | grep '644   f'
  d3613c1ec8310a812ac4268fd853ac576b6caea5 644   f
  $ hg manifest --debug --rev 'desc("mEA-change-m-0")' | grep '644   f'
  05e03c868bbcab4a649cb33a238d7aa07398a469 644   f
  $ hg manifest --debug --rev 'desc("a-2")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg manifest --debug --rev 'desc("e-2")' | grep '644   f'
  ae258f702dfeca05bf9b6a22a97a4b5645570f11 644   f
  $ hg debugindex f | ../no-linkrev
     rev linkrev nodeid       p1           p2
       0       * ae258f702dfe 000000000000 000000000000
       1       * d3613c1ec831 ae258f702dfe 000000000000
       2       * 05e03c868bbc ae258f702dfe 000000000000
#endif

# Here the filelog based implementation is not looking at the rename
# information (because the file exist on both side). However the changelog
# based on works fine. We have different output.

  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mAE-change-m-0")'
  M f
    b (no-filelog !)
  R b
  $ hg status --copies --rev 'desc("a-2")' --rev 'desc("mEA-change-m-0")'
  M f
    b (no-filelog !)
  R b
  $ hg status --copies --rev 'desc("e-2")' --rev 'desc("mAE-change-m-0")'
  M f
    d (no-filelog !)
  R d
  $ hg status --copies --rev 'desc("e-2")' --rev 'desc("mEA-change-m-0")'
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

  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mAE-change-m-0")'
  A f
    d
  R b
  R d
  $ hg status --copies --rev 'desc("i-2")' --rev 'desc("mEA-change-m-0")'
  A f
    d (filelog !)
    b (no-filelog !)
  R b
  R d
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mAE-change-m-0")'
  A f
    a
  A t
    p
  R a
  R b
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mEA-change-m-0")'
  A f
    a (filelog !)
    b (no-filelog !)
  A t
    p
  R a
  R b
  R p


Decision from previous merge are properly chained with later merge
------------------------------------------------------------------


Subcase: chaining conflicting rename resolution
```````````````````````````````````````````````

The "mAEm" and "mEAm" case create a rename tracking conflict on file 'f'. We
add more change on the respective branch and merge again. These second merge
does not involve the file 'f' and the arbitration done within "mAEm" and "mEA"
about that file should stay unchanged.

The result from mAEm is the same for the subsequent merge:

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mAEm")' f
  A f
    a (filelog !)
    a (sidedata !)
    a (upgraded !)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mAE,Km")' f
  A f
    a (filelog !)
    a (sidedata !)
    a (upgraded !)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mK,AEm")' f
  A f
    a (filelog !)
    a (missing-correct-output sidedata !)
    a (missing-correct-output upgraded !)
    b (known-bad-output sidedata !)
    b (known-bad-output upgraded !)


The result from mEAm is the same for the subsequent merge:

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mEAm")' f
  A f
    a (filelog !)
    b (sidedata !)
    b (upgraded !)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mEA,Jm")' f
  A f
    a (filelog !)
    b (sidedata !)
    b (upgraded !)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mJ,EAm")' f
  A f
    a (filelog !)
    b (missing-correct-output sidedata !)
    b (missing-correct-output upgraded !)
    a (known-bad-output sidedata !)
    a (known-bad-output upgraded !)


Subcase: chaining salvage information during a merge
````````````````````````````````````````````````````

We add more change on the branch were the file was deleted. merging again
should preserve the fact eh file was salvaged.

reference output:

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCB-revert-m-0")'
  M b
  A d
    a (filelog !)
    a (sidedata !)
    a (upgraded !)
  A t
    p
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBC-revert-m-0")'
  M b
  A d
    a (filelog !)
    a (sidedata !)
    a (upgraded !)
  A t
    p
  R a
  R p

chained output

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mBC+revert,Lm")'
  M b
  A d
    a (filelog !)
    a (missing-correct-output sidedata !)
    a (missing-correct-output upgraded !)
  A t
    p
  A unrelated-l
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mCB+revert,Lm")'
  M b
  A d
    a (filelog !)
    a (missing-correct-output sidedata !)
    a (missing-correct-output upgraded !)
  A t
    p
  A unrelated-l
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mL,BC+revertm")'
  M b
  A d
    a (filelog !)
    a (missing-correct-output sidedata !)
    a (missing-correct-output upgraded !)
  A t
    p
  A unrelated-l
  R a
  R p
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mL,CB+revertm")'
  M b
  A d
    a (filelog !)
    a (missing-correct-output sidedata !)
    a (missing-correct-output upgraded !)
  A t
    p
  A unrelated-l
  R a
  R p

Subcase: chaining "merged" information during a merge
``````````````````````````````````````````````````````

When a non-rename change are merged with a copy overwrite, the merge pick the copy source from (p1) as the reference. We should preserve this information in subsequent merges.


reference output:

 (for details about the filelog pick, check the mFGm/mGFm case)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mFGm")' d
  A d
    a (filelog !)
    h (sidedata !)
    h (upgraded !)
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mGFm")' d
  A d
    a (filelog !)
    a (sidedata !)
    a (upgraded !)

Chained output

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mO,FGm")' d
  A d
    a (filelog !)
    h (sidedata !)
    h (upgraded !)
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mFG,Om")' d
  A d
    a (filelog !)
    h (sidedata !)
    h (upgraded !)


  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mGF,Nm")' d
  A d
    a (filelog !)
    a (missing-correct-output sidedata !)
    a (missing-correct-output upgraded !)
    h (known-bad-output sidedata !)
    h (known-bad-output upgraded !)
  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mN,GFm")' d
  A d
    a (filelog !)
    a (missing-correct-output sidedata !)
    a (missing-correct-output upgraded !)
    h (known-bad-output sidedata !)
    h (known-bad-output upgraded !)


Subcase: chaining conflicting rename resolution, with extra change during the merge
```````````````````````````````````````````````````````````````````````````````````

The "mAEm" and "mEAm" case create a rename tracking conflict on file 'f'. We
add more change on the respective branch and merge again. These second merge
does not involve the file 'f' and the arbitration done within "mAEm" and "mEA"
about that file should stay unchanged.

The result from mAEm is the same for the subsequent merge:

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mAE-change-m")' f
  A f
    a (filelog !)
    a (sidedata !)
    a (upgraded !)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mAE-change,Km")' f
  A f
    a (filelog !)
    a (sidedata !)
    a (upgraded !)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mK,AE-change-m")' f
  A f
    a (filelog !)
    a (missing-correct-output sidedata !)
    a (missing-correct-output upgraded !)
    b (known-bad-output sidedata !)
    b (known-bad-output upgraded !)


The result from mEAm is the same for the subsequent merge:

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mEA-change-m")' f
  A f
    a (filelog !)
    b (sidedata !)
    b (upgraded !)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mEA-change,Jm")' f
  A f
    a (filelog !)
    b (sidedata !)
    b (upgraded !)

  $ hg status --copies --rev 'desc("i-0")' --rev 'desc("mJ,EA-change-m")' f
  A f
    a (filelog !)
    b (missing-correct-output sidedata !)
    b (missing-correct-output upgraded !)
    a (known-bad-output sidedata !)
    a (known-bad-output upgraded !)

===============================================
Testing merge involving change to the exec flag
===============================================

#require execbit


Initial setup
==============


  $ hg init base-repo
  $ cd base-repo
  $ cat << EOF > a
  > 1
  > 2
  > 3
  > 4
  > 5
  > 6
  > 7
  > 8
  > 9
  > EOF
  $ touch b
  $ hg add a b
  $ hg commit -m "initial commit"
  $ cd ..

Testing merging mode change
===========================

setup

Change on one side, executable bit on the other

  $ hg clone base-repo simple-merge-repo
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd simple-merge-repo
  $ chmod +x a
  $ hg ci -m "make a executable, no change"
  $ [ -x a ] || echo "executable bit not recorded"
  $ hg up ".^"
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cat << EOF > a
  > 1
  > 2
  > 3
  > 4
  > 5
  > 6
  > 7
  > x
  > 9
  > EOF
  $ hg commit -m "edit end of file"
  created new head

merge them (from the update side)

  $ hg merge 'desc("make a executable, no change")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg st
  M a
  $ [ -x a ] || echo "executable bit lost"

merge them (from the chmod side)

  $ hg up -C 'desc("make a executable, no change")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("edit end of file")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg st
  M a
  $ [ -x a ] || echo "executable bit lost"


  $ cd ..


  $ hg init

  $ echo "[merge]" >> .hg/hgrc
  $ echo "followcopies = 1" >> .hg/hgrc

  $ echo foo > a
  $ echo foo > a2
  $ hg add a a2
  $ hg ci -m "start"

  $ hg mv a b
  $ hg mv a2 b2
  $ hg ci -m "rename"

  $ hg co 0
  2 files updated, 0 files merged, 2 files removed, 0 files unresolved

  $ echo blahblah > a
  $ echo blahblah > a2
  $ hg mv a2 c2
  $ hg ci -m "modify"
  created new head

  $ hg merge -y --debug
    unmatched files in local:
     c2
    unmatched files in other:
     b
     b2
    all copies found (* = to merge, ! = divergent, % = renamed and deleted):
     on local side:
      src: 'a2' -> dst: 'c2' !
     on remote side:
      src: 'a' -> dst: 'b' *
      src: 'a2' -> dst: 'b2' !
    checking for directory renames
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: af1939970a1c, local: 044f8520aeeb+, remote: 85c198ef2f6c
  note: possible conflict - a2 was renamed multiple times to:
   b2
   c2
   preserving a for resolve of b
  removing a
   b2: remote created -> g
  getting b2
   b: remote moved from a -> m (premerge)
  picked tool ':merge' for b (binary False symlink False changedelete False)
  merging a and b to b
  my b@044f8520aeeb+ other b@85c198ef2f6c ancestor a@af1939970a1c
   premerge successful
  1 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg status -AC
  M b
    a
  M b2
  R a
  C c2

  $ cat b
  blahblah

  $ hg ci -m "merge"

  $ hg debugindex b
     rev linkrev nodeid       p1           p2
       0       1 57eacc201a7f 000000000000 000000000000
       1       3 4727ba907962 000000000000 57eacc201a7f

  $ hg debugrename b
  b renamed from a:dd03b83622e78778b403775d0d074b9ac7387a66

This used to trigger a "divergent renames" warning, despite no renames

  $ hg cp b b3
  $ hg cp b b4
  $ hg ci -A -m 'copy b twice'
  $ hg up '.^'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg up
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg rm b3 b4
  $ hg ci -m 'clean up a bit of our mess'

We'd rather not warn on divergent renames done in the same changeset (issue2113)

  $ hg cp b b3
  $ hg mv b b4
  $ hg ci -A -m 'divergent renames in same changeset'
  $ hg up '.^'
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg up
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved

Check for issue2642

  $ hg init t
  $ cd t

  $ echo c0 > f1
  $ hg ci -Aqm0

  $ hg up null -q
  $ echo c1 > f1 # backport
  $ hg ci -Aqm1
  $ hg mv f1 f2
  $ hg ci -qm2

  $ hg up 0 -q
  $ hg merge 1 -q --tool internal:local
  $ hg ci -qm3

  $ hg merge 2
  merging f1 and f2 to f2
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ cat f2
  c0

  $ cd ..

Check for issue2089

  $ hg init repo2089
  $ cd repo2089

  $ echo c0 > f1
  $ hg ci -Aqm0

  $ hg up null -q
  $ echo c1 > f1
  $ hg ci -Aqm1

  $ hg up 0 -q
  $ hg merge 1 -q --tool internal:local
  $ echo c2 > f1
  $ hg ci -qm2

  $ hg up 1 -q
  $ hg mv f1 f2
  $ hg ci -Aqm3

  $ hg up 2 -q
  $ hg merge 3
  merging f1 and f2 to f2
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ cat f2
  c2

  $ cd ..

Check for issue3074

  $ hg init repo3074
  $ cd repo3074
  $ echo foo > file
  $ hg add file
  $ hg commit -m "added file"
  $ hg mv file newfile
  $ hg commit -m "renamed file"
  $ hg update 0
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg rm file
  $ hg commit -m "deleted file"
  created new head
  $ hg merge --debug
    unmatched files in other:
     newfile
    all copies found (* = to merge, ! = divergent, % = renamed and deleted):
     on remote side:
      src: 'file' -> dst: 'newfile' %
    checking for directory renames
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 19d7f95df299, local: 0084274f6b67+, remote: 5d32493049f0
  note: possible conflict - file was deleted and renamed to:
   newfile
   newfile: remote created -> g
  getting newfile
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg status
  M newfile
  $ cd ..

Create x and y, then modify y and rename x to z on one side of merge, and
modify x and rename y to z on the other side.
  $ hg init conflicting-target
  $ cd conflicting-target
  $ echo x > x
  $ echo y > y
  $ hg ci -Aqm 'add x and y'
  $ hg mv x z
  $ echo foo >> y
  $ hg ci -qm 'modify y, rename x to z'
  $ hg co -q 0
  $ hg mv y z
  $ echo foo >> x
  $ hg ci -qm 'modify x, rename y to z'
# We should probably tell the user about the conflicting rename sources.
# Depending on which side they pick, we should take that rename and get
# the changes to the source from the other side. The unchanged file should
# remain.
  $ hg merge --debug 1 -t :merge3
    all copies found (* = to merge, ! = divergent, % = renamed and deleted):
     on local side:
      src: 'y' -> dst: 'z' *
     on remote side:
      src: 'x' -> dst: 'z' *
    checking for directory renames
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 5151c134577e, local: 07fcbc9a74ed+, remote: f21419739508
   preserving z for resolve of z
  starting 4 threads for background file closing (?)
   z: both renamed from y -> m (premerge)
  picked tool ':merge3' for z (binary False symlink False changedelete False)
  merging z
  my z@07fcbc9a74ed+ other z@f21419739508 ancestor y@5151c134577e
   premerge successful
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ ls
  x
  z
  $ cat x
  x
  foo
# 'z' should have had the added 'foo' line
  $ cat z
  x

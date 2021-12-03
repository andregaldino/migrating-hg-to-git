Test for the full copytracing algorithm
=======================================


Initial Setup
=============

use git diff to see rename

  $ cat << EOF >> $HGRCPATH
  > [diff]
  > git=yes
  > EOF

Setup an history where one side copy and rename a file (and update it) while the other side update it.

  $ hg init t
  $ cd t

  $ echo 1 > a
  $ hg ci -qAm "first"

  $ hg cp a b
  $ hg mv a c
  $ echo 2 >> b
  $ echo 2 >> c

  $ hg ci -qAm "second"

  $ hg co -C 0
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved

  $ echo 0 > a
  $ echo 1 >> a

  $ hg ci -qAm "other"

  $ hg log -G --patch
  @  changeset:   2:add3f11052fa
  |  tag:         tip
  |  parent:      0:b8bf91eeebbc
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     other
  |
  |  diff --git a/a b/a
  |  --- a/a
  |  +++ b/a
  |  @@ -1,1 +1,2 @@
  |  +0
  |   1
  |
  | o  changeset:   1:17c05bb7fcb6
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     second
  |
  |    diff --git a/a b/b
  |    rename from a
  |    rename to b
  |    --- a/a
  |    +++ b/b
  |    @@ -1,1 +1,2 @@
  |     1
  |    +2
  |    diff --git a/a b/c
  |    copy from a
  |    copy to c
  |    --- a/a
  |    +++ b/c
  |    @@ -1,1 +1,2 @@
  |     1
  |    +2
  |
  o  changeset:   0:b8bf91eeebbc
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     first
  
     diff --git a/a b/a
     new file mode 100644
     --- /dev/null
     +++ b/a
     @@ -0,0 +1,1 @@
     +1
  

Test Simple Merge
=================

  $ hg merge --debug
    unmatched files in other:
     b
     c
    all copies found (* = to merge, ! = divergent, % = renamed and deleted):
     on remote side:
      src: 'a' -> dst: 'b' *
      src: 'a' -> dst: 'c' *
    checking for directory renames
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: b8bf91eeebbc, local: add3f11052fa+, remote: 17c05bb7fcb6
  starting 4 threads for background file closing (?)
   preserving a for resolve of b
   preserving a for resolve of c
  removing a
   b: remote moved from a -> m
  picked tool ':merge' for b (binary False symlink False changedelete False)
  merging a and b to b
  my b@add3f11052fa+ other b@17c05bb7fcb6 ancestor a@b8bf91eeebbc
   premerge successful
   c: remote moved from a -> m
  picked tool ':merge' for c (binary False symlink False changedelete False)
  merging a and c to c
  my c@add3f11052fa+ other c@17c05bb7fcb6 ancestor a@b8bf91eeebbc
   premerge successful
  0 files updated, 2 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

file b
  $ cat b
  0
  1
  2

file c
  $ cat c
  0
  1
  2

Test disabling copy tracing
===========================

first verify copy metadata was kept
-----------------------------------

  $ hg up -qC 2
  $ hg rebase --keep -d 1 -b 2 --config extensions.rebase=
  rebasing 2:add3f11052fa tip "other"
  merging b and a to b
  merging c and a to c

  $ cat b
  0
  1
  2

 next verify copy metadata is lost when disabled
------------------------------------------------

  $ hg strip -r . --config extensions.strip=
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  saved backup bundle to $TESTTMP/t/.hg/strip-backup/550bd84c0cd3-fc575957-backup.hg
  $ hg up -qC 2
  $ hg rebase --keep -d 1 -b 2 --config extensions.rebase= --config experimental.copytrace=off --config ui.interactive=True << EOF
  > c
  > EOF
  rebasing 2:add3f11052fa tip "other"
  file 'a' was deleted in local [dest] but was modified in other [source].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? c

  $ cat b
  1
  2

  $ cd ..

Verify disabling copy tracing still keeps copies from rebase source
-------------------------------------------------------------------

  $ hg init copydisable
  $ cd copydisable
  $ touch a
  $ hg ci -Aqm 'add a'
  $ touch b
  $ hg ci -Aqm 'add b, c'
  $ hg cp b x
  $ echo x >> x
  $ hg ci -qm 'copy b->x'
  $ hg up -q 1
  $ touch z
  $ hg ci -Aqm 'add z'
  $ hg log -G -T '{rev} {desc}\n'
  @  3 add z
  |
  | o  2 copy b->x
  |/
  o  1 add b, c
  |
  o  0 add a
  
  $ hg rebase -d . -b 2 --config extensions.rebase= --config experimental.copytrace=off
  rebasing 2:6adcf8c12e7d "copy b->x"
  saved backup bundle to $TESTTMP/copydisable/.hg/strip-backup/6adcf8c12e7d-ce4b3e75-rebase.hg
  $ hg up -q 3
  $ hg log -f x -T '{rev} {desc}\n'
  3 copy b->x
  1 add b, c

  $ cd ../


test storage preservation
-------------------------

Verify rebase do not discard recorded copies data when copy tracing usage is
disabled.

Setup

  $ hg init copydisable3
  $ cd copydisable3
  $ touch a
  $ hg ci -Aqm 'add a'
  $ hg cp a b
  $ hg ci -Aqm 'copy a->b'
  $ hg mv b c
  $ hg ci -Aqm 'move b->c'
  $ hg up -q 0
  $ hg cp a b
  $ echo b >> b
  $ hg ci -Aqm 'copy a->b (2)'
  $ hg log -G -T '{rev} {desc}\n'
  @  3 copy a->b (2)
  |
  | o  2 move b->c
  | |
  | o  1 copy a->b
  |/
  o  0 add a
  

Actual Test

A file is copied on one side and has been moved twice on the other side. the
file is copied from `0:a`, so the file history of the `3:b` should trace directly to `0:a`.

  $ hg rebase -d 2 -s 3 --config extensions.rebase= --config experimental.copytrace=off
  rebasing 3:47e1a9e6273b tip "copy a->b (2)"
  saved backup bundle to $TESTTMP/copydisable3/.hg/strip-backup/47e1a9e6273b-2d099c59-rebase.hg

  $ hg log -G -f b
  @  changeset:   3:76024fb4b05b
  :  tag:         tip
  :  user:        test
  :  date:        Thu Jan 01 00:00:00 1970 +0000
  :  summary:     copy a->b (2)
  :
  o  changeset:   0:ac82d8b1f7c4
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     add a
  

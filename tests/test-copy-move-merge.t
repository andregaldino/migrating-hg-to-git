
Initial Setup
=============

use git diff to see rename

  $ cat << EOF >> $HGRCPATH
  > [diff]
  > git=yes
  > EOF

Setup an history where one side copy and rename a file (and update it) while the other side update it.

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

===========================
first verify copy metadata was kept
-----------------------------------
 next verify copy metadata is lost when disabled
------------------------------------------------
-------------------------------------------------------------------

test storage preservation
-------------------------

Verify rebase do not discard recorded copies data when copy tracing usage is
disabled.

Setup

Actual Test

A file is copied on one side and has been moved twice on the other side. the
file is copied from `0:a`, so the file history of the `3:b` should trace directly to `0:a`.

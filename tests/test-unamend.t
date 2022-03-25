Test for command `hg unamend` which lives in uncommit extension
===============================================================

  $ cat >> $HGRCPATH << EOF
  > [alias]
  > glog = log -G -T '{rev}:{node|short}  {desc}'
  > [experimental]
  > evolution = createmarkers, allowunstable
  > evolution.allowdivergence = true
  > [extensions]
  > rebase =
  > amend =
  > uncommit =
  > EOF

Repo Setup

  $ hg init repo
  $ cd repo
  $ for ch in a b c d e f g h; do touch $ch; echo "foo" >> $ch; hg ci -Aqm "Added "$ch; done

  $ hg glog
  @  7:ec2426147f0e  Added h
  |
  o  6:87d6d6676308  Added g
  |
  o  5:825660c69f0c  Added f
  |
  o  4:aa98ab95a928  Added e
  |
  o  3:62615734edd5  Added d
  |
  o  2:28ad74487de9  Added c
  |
  o  1:29becc82797a  Added b
  |
  o  0:18d04c59bb5d  Added a
  
Trying to unamend when there was no amend done

  $ hg unamend
  abort: working copy parent was not created by 'hg amend' or 'hg unamend'
  [10]
  $ echo "bar" >> h

Trying to unamend when the obsmarker is missing

  $ hg amend
  $ hg debugobsolete --delete 0
  deleted 1 obsolescence markers
  $ hg unamend
  abort: changeset must have one predecessor, found 0 predecessors
  [10]
  $ hg strip tip --config extensions.strip=
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/c9fa1a715c1b-06e5c233-backup.hg
  $ hg up tip
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

Unamend on clean wdir and tip

  $ echo "bar" >> h
  $ hg amend

  $ hg exp
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID c9fa1a715c1b7661c0fafb362a9f30bd75878d7d
  # Parent  87d6d66763085b629e6d7ed56778c79827273022
  Added h
  
  diff -r 87d6d6676308 -r c9fa1a715c1b h
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/h	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,2 @@
  +foo
  +bar

  $ hg glog --hidden
  @  8:c9fa1a715c1b  Added h
  |
  | x  7:ec2426147f0e  Added h
  |/
  o  6:87d6d6676308  Added g
  |
  o  5:825660c69f0c  Added f
  |
  o  4:aa98ab95a928  Added e
  |
  o  3:62615734edd5  Added d
  |
  o  2:28ad74487de9  Added c
  |
  o  1:29becc82797a  Added b
  |
  o  0:18d04c59bb5d  Added a
  
  $ hg unamend
  $ hg glog --hidden
  @  9:46d02d47eec6  Added h
  |
  | x  8:c9fa1a715c1b  Added h
  |/
  | x  7:ec2426147f0e  Added h
  |/
  o  6:87d6d6676308  Added g
  |
  o  5:825660c69f0c  Added f
  |
  o  4:aa98ab95a928  Added e
  |
  o  3:62615734edd5  Added d
  |
  o  2:28ad74487de9  Added c
  |
  o  1:29becc82797a  Added b
  |
  o  0:18d04c59bb5d  Added a
  
  $ hg diff
  diff -r 46d02d47eec6 h
  --- a/h	Thu Jan 01 00:00:00 1970 +0000
  +++ b/h	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,2 @@
   foo
  +bar

  $ hg exp
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID 46d02d47eec6ca096b8dcab3f8f5579c40c3dd9a
  # Parent  87d6d66763085b629e6d7ed56778c79827273022
  Added h
  
  diff -r 87d6d6676308 -r 46d02d47eec6 h
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/h	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +foo

  $ hg status
  M h

  $ hg log -r . -T '{extras % "{extra}\n"}' --config alias.log=log
  branch=default
  unamend_source=c9fa1a715c1b7661c0fafb362a9f30bd75878d7d

Using unamend to undo an unamed (intentional)

  $ hg unamend
  $ hg exp
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID 850ddfc1bc662997ec6094ada958f01f0cc8070a
  # Parent  87d6d66763085b629e6d7ed56778c79827273022
  Added h
  
  diff -r 87d6d6676308 -r 850ddfc1bc66 h
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/h	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,2 @@
  +foo
  +bar
  $ hg diff

Unamend on a dirty working directory

  $ echo "bar" >> a
  $ hg amend
  $ echo "foobar" >> a
  $ echo "bar" >> b
  $ hg status
  M a
  M b

  $ hg unamend

  $ hg status
  M a
  M b

  $ hg diff
  diff -r ec338db45d51 a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,3 @@
   foo
  +bar
  +foobar
  diff -r ec338db45d51 b
  --- a/b	Thu Jan 01 00:00:00 1970 +0000
  +++ b/b	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,2 @@
   foo
  +bar

Unamending an added file

  $ hg ci -m "Added things to a and b"
  $ echo foo > bar
  $ hg add bar
  $ hg amend

  $ hg unamend
  $ hg status
  A bar

  $ hg revert --all
  forgetting bar

Unamending a removed file

  $ hg remove a
  $ hg amend

  $ hg unamend
  $ hg status
  R a
  ? bar

  $ hg revert --all
  undeleting a

Unamending an added file with dirty wdir status

  $ hg add bar
  $ hg amend
  $ echo bar >> bar
  $ hg status
  M bar

  $ hg unamend
  $ hg status
  A bar
  $ hg diff
  diff -r 7f79409af972 bar
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/bar	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,2 @@
  +foo
  +bar

  $ hg revert --all
  forgetting bar
  $ rm bar

Unamending in middle of a stack

  $ hg glog
  @  19:7f79409af972  Added things to a and b
  |
  o  12:ec338db45d51  Added h
  |
  o  6:87d6d6676308  Added g
  |
  o  5:825660c69f0c  Added f
  |
  o  4:aa98ab95a928  Added e
  |
  o  3:62615734edd5  Added d
  |
  o  2:28ad74487de9  Added c
  |
  o  1:29becc82797a  Added b
  |
  o  0:18d04c59bb5d  Added a
  
  $ hg up 5
  2 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ echo bar >> f
  $ hg amend
  3 new orphan changesets
  $ hg rebase -s 6 -d . -q

  $ hg glog
  o  23:03ddd6fc5af1  Added things to a and b
  |
  o  22:3e7b64ee157b  Added h
  |
  o  21:49635b68477e  Added g
  |
  @  20:93f0e8ffab32  Added f
  |
  o  4:aa98ab95a928  Added e
  |
  o  3:62615734edd5  Added d
  |
  o  2:28ad74487de9  Added c
  |
  o  1:29becc82797a  Added b
  |
  o  0:18d04c59bb5d  Added a
  

  $ hg --config experimental.evolution=createmarkers unamend
  abort: cannot unamend changeset, as that will orphan 3 descendants
  (see 'hg help evolution.instability')
  [10]

  $ hg unamend
  3 new orphan changesets

Trying to unamend a public changeset

  $ hg up -C 23
  5 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg phase -r . -p
  1 new phase-divergent changesets
  $ hg unamend
  abort: cannot unamend public changesets: 03ddd6fc5af1
  (see 'hg help phases' for details)
  [10]

Testing whether unamend retains copies or not

  $ hg status

  $ hg mv a foo

  $ hg ci -m "Moved a to foo"
  $ hg exp --git
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID cfef290346fbee5126313d7e1aab51d877679b09
  # Parent  03ddd6fc5af19e028c44a2fd6d790dd22712f231
  Moved a to foo
  
  diff --git a/a b/foo
  rename from a
  rename to foo

  $ hg mv b foobar
  $ hg diff --git
  diff --git a/b b/foobar
  rename from b
  rename to foobar
  $ hg amend

  $ hg exp --git
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID eca050985275bb271ce3092b54e56ea5c85d29a3
  # Parent  03ddd6fc5af19e028c44a2fd6d790dd22712f231
  Moved a to foo
  
  diff --git a/a b/foo
  rename from a
  rename to foo
  diff --git a/b b/foobar
  rename from b
  rename to foobar

  $ hg mv c wat
  $ hg unamend

  $ hg verify -v
  repository uses revlog format 1
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 28 changesets with 16 changes to 11 files

Retained copies in new prdecessor commit

  $ hg exp --git
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID 552e3af4f01f620f88ca27be1f898316235b736a
  # Parent  03ddd6fc5af19e028c44a2fd6d790dd22712f231
  Moved a to foo
  
  diff --git a/a b/foo
  rename from a
  rename to foo

Retained copies in working directoy

  $ hg diff --git
  diff --git a/b b/foobar
  rename from b
  rename to foobar
  diff --git a/c b/wat
  rename from c
  rename to wat
  $ hg revert -qa
  $ rm foobar wat

Rename a->b, then amend b->c. After unamend, should look like b->c.

  $ hg co -q 0
  $ hg mv a b
  $ hg ci -qm 'move to a b'
  $ hg mv b c
  $ hg amend
  $ hg unamend
  $ hg st --copies --change .
  A b
    a
  R a
  $ hg st --copies
  A c
    b
  R b
  $ hg revert -qa
  $ rm c

Rename a->b, then amend b->c, and working copy change c->d. After unamend, should look like b->d

  $ hg co -q 0
  $ hg mv a b
  $ hg ci -qm 'move to a b'
  warning: commit already existed in the repository!
  $ hg mv b c
  $ hg amend
  warning: commit already existed in the repository!
  $ hg mv c d
  $ hg unamend
  $ hg st --copies --change .
  A b
    a
  R a
  $ hg st --copies
  A d
    b
  R b

Try to unamend a merge

  $ cd ..
  $ hg init merge
  $ cd merge
  $ echo initial > initial
  $ hg ci -Aqm initial
  $ echo left > left
  $ hg ci -Aqm left
  $ hg co -q 0
  $ echo right > right
  $ hg ci -Aqm right
  $ hg merge -q 1
  $ hg ci -m merge
  $ echo accidental > initial
  $ hg st --rev 1 --rev .
  A right
  $ hg st --rev 2 --rev .
  A left
  $ hg amend
  $ hg unamend
  abort: cannot unamend merge changeset
  [10]

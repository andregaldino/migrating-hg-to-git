#require pygit2 no-windows

Setup:
  $ GIT_AUTHOR_NAME='test'; export GIT_AUTHOR_NAME
  > GIT_AUTHOR_EMAIL='test@example.org'; export GIT_AUTHOR_EMAIL
  > GIT_AUTHOR_DATE="2007-01-01 00:00:00 +0000"; export GIT_AUTHOR_DATE
  > GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"; export GIT_COMMITTER_NAME
  > GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"; export GIT_COMMITTER_EMAIL
  > GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"; export GIT_COMMITTER_DATE
  > HGUSER="test <test@example.org>"; export HGUSER
  > count=10
  > gitcommit() {
  >    GIT_AUTHOR_DATE="2007-01-01 00:00:$count +0000";
  >    GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
  >    git commit "$@" >/dev/null 2>/dev/null || echo "git commit error"
  >    count=`expr $count + 1`
  >  }
  $ git config --global init.defaultBranch master


  $ hg version -v --config extensions.git= | grep '^[E ]'
  Enabled extensions:
    git  internal  (pygit2 *) (glob)

Test auto-loading extension works:
  $ mkdir nogit
  $ cd nogit
  $ mkdir .hg
  $ echo git >> .hg/requires
  $ hg status
  abort: repository specified git format in .hg/requires but has no .git directory
  [255]
  $ git config --global init.defaultBranch master
  $ git init
  Initialized empty Git repository in $TESTTMP/nogit/.git/
This status invocation shows some hg gunk because we didn't use
`hg init --git`, which fixes up .git/info/exclude for us.
  $ hg status
  ? .hg/cache/git-commits.sqlite
  ? .hg/cache/git-commits.sqlite-shm
  ? .hg/cache/git-commits.sqlite-wal
  ? .hg/requires
  $ cd ..

Now globally enable extension for the rest of the test:
  $ cat <<EOF >> $HGRCPATH
  > [extensions]
  > git=
  > [git]
  > log-index-cache-miss = yes
  > EOF

Test some edge cases around a commitless repo first
  $ mkdir empty
  $ cd empty
  $ git init
  Initialized empty Git repository in $TESTTMP/empty/.git/
  $ hg init --git
  $ hg heads
  [1]
  $ hg tip
  changeset:   -1:000000000000
  tag:         tip
  user:        
  date:        Thu Jan 01 00:00:00 1970 +0000
  
  $ cd ..

Make a new repo with git:
  $ mkdir foo
  $ cd foo
  $ git init
  Initialized empty Git repository in $TESTTMP/foo/.git/
Ignore the .hg directory within git:
  $ echo .hg >> .git/info/exclude
  $ echo alpha > alpha
  $ git add alpha
  $ gitcommit -am 'Add alpha'
  $ echo beta > beta
  $ git add beta
  $ gitcommit -am 'Add beta'
  $ echo gamma > gamma
  $ git status
  On branch master
  Untracked files:
    (use "git add <file>..." to include in what will be committed)
   (?)
  	gamma
  
  nothing added to commit but untracked files present (use "git add" to track)

Without creating the .hg, hg status fails:
  $ hg status
  abort: no repository found in '$TESTTMP/foo' (.hg not found)
  [10]
But if you run hg init --git, it works:
  $ hg init --git
  $ hg id --traceback
  heads mismatch, rebuilding dagcache
  3d9be8deba43 tip master
  $ hg status
  ? gamma
Log works too:
  $ hg log
  changeset:   1:3d9be8deba43
  bookmark:    master
  tag:         tip
  user:        test <test@example.org>
  date:        Mon Jan 01 00:00:11 2007 +0000
  summary:     Add beta
  
  changeset:   0:c5864c9d16fb
  user:        test <test@example.org>
  date:        Mon Jan 01 00:00:10 2007 +0000
  summary:     Add alpha
  


and bookmarks:
  $ hg bookmarks
   * master                    1:3d9be8deba43

diff even works transparently in both systems:
  $ echo blah >> alpha
  $ git diff
  diff --git a/alpha b/alpha
  index 4a58007..faed1b7 100644
  --- a/alpha
  +++ b/alpha
  @@ -1* +1,2 @@ (glob)
   alpha
  +blah
  $ hg diff --git
  diff --git a/alpha b/alpha
  --- a/alpha
  +++ b/alpha
  @@ -1,1 +1,2 @@
   alpha
  +blah

Remove a file, it shows as such:
  $ rm alpha
  $ hg status
  ! alpha
  ? gamma

Revert works:
  $ hg revert alpha --traceback
  $ hg status
  ? gamma
  $ git status
  On branch master
  Untracked files:
    (use "git add <file>..." to include in what will be committed)
   (?)
  	gamma
  
  nothing added to commit but untracked files present (use "git add" to track)

Add shows sanely in both:
  $ hg add gamma
  $ hg status
  A gamma
  $ hg files
  alpha
  beta
  gamma
  $ git ls-files
  alpha
  beta
  gamma
  $ git status
  On branch master
  Changes to be committed:
    (use "git restore --staged <file>..." to unstage) (?)
    (use "git reset HEAD <file>..." to unstage) (?)
   (?)
  	new file:   gamma
  

forget does what it should as well:
  $ hg forget gamma
  $ hg status
  ? gamma
  $ git status
  On branch master
  Untracked files:
    (use "git add <file>..." to include in what will be committed)
   (?)
  	gamma
  
  nothing added to commit but untracked files present (use "git add" to track)

clean up untracked file
  $ rm gamma

hg log FILE

  $ echo a >> alpha
  $ hg ci -m 'more alpha' --traceback --date '1583558723 18000'
  $ echo b >> beta
  $ hg ci -m 'more beta'
  heads mismatch, rebuilding dagcache
  $ echo a >> alpha
  $ hg ci -m 'even more alpha'
  heads mismatch, rebuilding dagcache
  $ hg log -G alpha
  heads mismatch, rebuilding dagcache
  @  changeset:   4:cf6ddf5d9b8a
  :  bookmark:    master
  :  tag:         tip
  :  user:        test <test@example.org>
  :  date:        Thu Jan 01 00:00:00 1970 +0000
  :  summary:     even more alpha
  :
  o  changeset:   2:5b2c80b027ce
  :  user:        test <test@example.org>
  :  date:        Sat Mar 07 00:25:23 2020 -0500
  :  summary:     more alpha
  :
  o  changeset:   0:c5864c9d16fb
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     Add alpha
  
  $ hg log -G beta
  o  changeset:   3:980d4f79a9c6
  :  user:        test <test@example.org>
  :  date:        Thu Jan 01 00:00:00 1970 +0000
  :  summary:     more beta
  :
  o  changeset:   1:3d9be8deba43
  |  user:        test <test@example.org>
  ~  date:        Mon Jan 01 00:00:11 2007 +0000
     summary:     Add beta
  

  $ hg log -r "children(3d9be8deba43)" -T"{node|short} {children}\n"
  5b2c80b027ce 3:980d4f79a9c6

hg annotate

  $ hg annotate alpha
  0: alpha
  2: a
  4: a
  $ hg annotate beta
  1: beta
  3: b


Files in subdirectories. TODO: case-folding support, make this `A`
instead of `a`.

  $ mkdir a
  $ echo "This is file mu." > a/mu
  $ hg ci -A -m 'Introduce file a/mu'
  adding a/mu

Both hg and git agree a/mu is part of the repo

  $ git ls-files
  a/mu
  alpha
  beta
  $ hg files
  a/mu
  alpha
  beta

hg and git status both clean

  $ git status
  On branch master
  nothing to commit, working tree clean
  $ hg status
  heads mismatch, rebuilding dagcache


node|shortest works correctly
  $ hg log -T '{node}\n' | sort
  3d9be8deba43482be2c81a4cb4be1f10d85fa8bc
  5b2c80b027ce4250f88957326c199a2dc48dad60
  980d4f79a9c617d60d0fe1fb383753c4a61bea8e
  c1a41c49866ecc9c5411be932653e5b430961dd5
  c5864c9d16fb3431fe2c175ff84dc6accdbb2c18
  cf6ddf5d9b8a120bf90020342bcf7a96d0167279
  $ hg log -r c1a41c49866ecc9c5411be932653e5b430961dd5 --template "{shortest(node,1)}\n"
  c1

This covers gitlog._partialmatch()
  $ hg log -r c
  abort: ambiguous revision identifier: c
  [10]
  $ hg log -r c1
  changeset:   5:c1a41c49866e
  bookmark:    master
  tag:         tip
  user:        test <test@example.org>
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     Introduce file a/mu
  
  $ hg log -r dead
  abort: unknown revision 'dead'
  [255]

This coveres changelog.findmissing()
  $ hg merge --preview 3d9be8deba43

This covers manifest.diff()
  $ hg diff -c 3d9be8deba43
  diff -r c5864c9d16fb -r 3d9be8deba43 beta
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/beta	Mon Jan 01 00:00:11 2007 +0000
  @@ -0,0 +1,1 @@
  +beta


Interactive commit should work as expected

  $ echo bar >> alpha
  $ echo bar >> beta
  $ hg commit -m "test interactive commit" -i --config ui.interactive=true --config ui.interface=text << EOF
  > y
  > y
  > n
  > EOF
  diff --git a/alpha b/alpha
  1 hunks, 1 lines changed
  examine changes to 'alpha'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -1,3 +1,4 @@
   alpha
   a
   a
  +bar
  record change 1/2 to 'alpha'?
  (enter ? for help) [Ynesfdaq?] y
  
  diff --git a/beta b/beta
  1 hunks, 1 lines changed
  examine changes to 'beta'?
  (enter ? for help) [Ynesfdaq?] n
  
Status should be consistent for both systems

  $ hg status
  heads mismatch, rebuilding dagcache
  M beta
  $ git status | egrep -v '^$|^  \(use '
  On branch master
  Changes not staged for commit:
  	modified:   beta
  no changes added to commit (use "git add" and/or "git commit -a")

Contents of each commit should be the same

  $ hg ex -r .
  # HG changeset patch
  # User test <test@example.org>
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID 6024eda7986da123aa6797dd4603bd399d49bf5c
  # Parent  c1a41c49866ecc9c5411be932653e5b430961dd5
  test interactive commit
  
  diff -r c1a41c49866e -r 6024eda7986d alpha
  --- a/alpha	Thu Jan 01 00:00:00 1970 +0000
  +++ b/alpha	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,3 +1,4 @@
   alpha
   a
   a
  +bar
  $ git show
  commit 6024eda7986da123aa6797dd4603bd399d49bf5c
  Author: test <test@example.org>
  Date:   Thu Jan 1 00:00:00 1970 +0000
  
      test interactive commit
  
  diff --git a/alpha b/alpha
  index d112a75..d2a2e9a 100644
  --- a/alpha
  +++ b/alpha
  @@ -1,3 +1,4 @@
   alpha
   a
   a
  +bar

Deleting files should also work (this was issue6398)
  $ hg revert -r . --all
  reverting beta
  $ hg rm beta
  $ hg ci -m 'remove beta'

This covers changelog.tiprev() (issue6510)
  $ hg log -r '(.^^):'
  heads mismatch, rebuilding dagcache
  changeset:   5:c1a41c49866e
  user:        test <test@example.org>
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     Introduce file a/mu
  
  changeset:   6:6024eda7986d
  user:        test <test@example.org>
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     test interactive commit
  
  changeset:   7:1a0fee76bfc4
  bookmark:    master
  tag:         tip
  user:        test <test@example.org>
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     remove beta
  
This covers changelog.headrevs() with a non-None arg
  $ hg log -r 'heads(.)' -Tcompact
  7[tip][master]   1a0fee76bfc4   1970-01-01 00:00 +0000   test
    remove beta
  



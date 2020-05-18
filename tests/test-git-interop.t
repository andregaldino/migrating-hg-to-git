#require pygit2

Setup:
  $ GIT_AUTHOR_NAME='test'; export GIT_AUTHOR_NAME
  > GIT_AUTHOR_EMAIL='test@example.org'; export GIT_AUTHOR_EMAIL
  > GIT_AUTHOR_DATE="2007-01-01 00:00:00 +0000"; export GIT_AUTHOR_DATE
  > GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"; export GIT_COMMITTER_NAME
  > GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"; export GIT_COMMITTER_EMAIL
  > GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"; export GIT_COMMITTER_DATE
  > count=10
  > gitcommit() {
  >    GIT_AUTHOR_DATE="2007-01-01 00:00:$count +0000";
  >    GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
  >    git commit "$@" >/dev/null 2>/dev/null || echo "git commit error"
  >    count=`expr $count + 1`
  >  }


Test auto-loading extension works:
  $ mkdir nogit
  $ cd nogit
  $ mkdir .hg
  $ echo git >> .hg/requires
  $ hg status
  abort: repository specified git format in .hg/requires but has no .git directory
  [255]
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
  $ echo "[extensions]" >> $HGRCPATH
  > echo "git=" >> $HGRCPATH

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
  	gamma
  
  nothing added to commit but untracked files present (use "git add" to track)

Without creating the .hg, hg status fails:
  $ hg status
  abort: no repository found in '$TESTTMP/foo' (.hg not found)!
  [255]
But if you run hg init --git, it works:
  $ hg init --git
  $ hg id --traceback
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
    (use "git restore --staged <file>..." to unstage)
  	new file:   gamma
  

forget does what it should as well:
  $ hg forget gamma
  $ hg status
  ? gamma
  $ git status
  On branch master
  Untracked files:
    (use "git add <file>..." to include in what will be committed)
  	gamma
  
  nothing added to commit but untracked files present (use "git add" to track)

clean up untracked file
  $ rm gamma

hg log FILE

  $ echo a >> alpha
  $ hg ci -m 'more alpha' --traceback --date '1583522787 18000'
  $ echo b >> beta
  $ hg ci -m 'more beta'
  $ echo a >> alpha
  $ hg ci -m 'even more alpha'
  $ hg log -G alpha
  @  changeset:   4:6626247b7dc8
  :  bookmark:    master
  :  tag:         tip
  :  user:        test <test>
  :  date:        Thu Jan 01 00:00:00 1970 +0000
  :  summary:     even more alpha
  :
  o  changeset:   2:a1983dd7fb19
  :  user:        test <test>
  :  date:        Fri Mar 06 14:26:27 2020 -0500
  :  summary:     more alpha
  :
  o  changeset:   0:c5864c9d16fb
     user:        test <test@example.org>
     date:        Mon Jan 01 00:00:10 2007 +0000
     summary:     Add alpha
  
  $ hg log -G beta
  o  changeset:   3:d8ee22687733
  :  user:        test <test>
  :  date:        Thu Jan 01 00:00:00 1970 +0000
  :  summary:     more beta
  :
  o  changeset:   1:3d9be8deba43
  |  user:        test <test@example.org>
  ~  date:        Mon Jan 01 00:00:11 2007 +0000
     summary:     Add beta
  

  $ hg log -r "children(3d9be8deba43)" -T"{node|short} {children}\n"
  a1983dd7fb19 3:d8ee22687733

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


node|shortest works correctly
  $ hg log -T '{node}\n' | sort
  3d9be8deba43482be2c81a4cb4be1f10d85fa8bc
  6626247b7dc8f231b183b8a4761c89139baca2ad
  a1983dd7fb19cbd83ad5a1c2fc8bf3d775dea12f
  ae1ab744f95bfd5b07cf573baef98a778058537b
  c5864c9d16fb3431fe2c175ff84dc6accdbb2c18
  d8ee22687733a1991813560b15128cd9734f4b48
  $ hg log -r ae1ab744f95bfd5b07cf573baef98a778058537b --template "{shortest(node,1)}\n"
  ae

This coveres changelog.findmissing()
  $ hg merge --preview 3d9be8deba43

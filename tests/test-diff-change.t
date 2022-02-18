Testing diff --change, --from, --to

  $ hg init a
  $ cd a

  $ echo "first" > file.txt
  $ hg add file.txt
  $ hg commit -m 'first commit' # 0

  $ echo "second" > file.txt
  $ hg commit -m 'second commit' # 1

  $ echo "third" > file.txt
  $ hg commit -m 'third commit' # 2

  $ hg diff --nodates --change 1
  diff -r 4bb65dda5db4 -r e9b286083166 file.txt
  --- a/file.txt
  +++ b/file.txt
  @@ -1,1 +1,1 @@
  -first
  +second

  $ hg diff --change e9b286083166
  diff -r 4bb65dda5db4 -r e9b286083166 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -first
  +second

Test --from and --to

  $ hg diff --from . --rev .
  abort: cannot specify both --from and --rev
  [10]
  $ hg diff --to . --rev .
  abort: cannot specify both --to and --rev
  [10]
  $ hg diff --from . --change .
  abort: cannot specify both --from and --change
  [10]
  $ hg diff --to . --change .
  abort: cannot specify both --to and --change
  [10]
  $ echo dirty > file.txt
  $ hg diff --from .
  diff -r bf5ff72eb7e0 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -third
  +dirty
  $ hg diff --from . --reverse
  diff -r bf5ff72eb7e0 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -dirty
  +third
  $ hg diff --to .
  diff -r bf5ff72eb7e0 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -dirty
  +third
  $ hg diff --from 0 --to 2
  diff -r 4bb65dda5db4 -r bf5ff72eb7e0 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -first
  +third
  $ hg diff --from 2 --to 0
  diff -r bf5ff72eb7e0 -r 4bb65dda5db4 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -third
  +first
  $ hg co -C .
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd ..

Test dumb revspecs: top-level "x:y", "x:", ":y" and ":" ranges should be handled
as pairs even if x == y, but not for "f(x:y)" nor "x::y" (issue3474, issue4774)

  $ hg clone -q a dumbspec
  $ cd dumbspec
  $ echo "wdir" > file.txt

  $ hg diff -r 2:2
  $ hg diff -r 2:.
  $ hg diff -r 2:
  $ hg diff -r :0
  $ hg diff -r '2:first(2:2)'
  $ hg diff -r 'first(2:2)' --nodates
  diff -r bf5ff72eb7e0 file.txt
  --- a/file.txt
  +++ b/file.txt
  @@ -1,1 +1,1 @@
  -third
  +wdir
  $ hg diff -r '(2:2)' --nodates
  diff -r bf5ff72eb7e0 file.txt
  --- a/file.txt
  +++ b/file.txt
  @@ -1,1 +1,1 @@
  -third
  +wdir
  $ hg diff -r 2::2 --nodates
  diff -r bf5ff72eb7e0 file.txt
  --- a/file.txt
  +++ b/file.txt
  @@ -1,1 +1,1 @@
  -third
  +wdir
  $ hg diff -r "2 and 1"
  abort: empty revision range
  [10]

  $ cd ..

  $ hg clone -qr0 a dumbspec-rev0
  $ cd dumbspec-rev0
  $ echo "wdir" > file.txt

  $ hg diff -r :
  $ hg diff -r 'first(:)' --nodates
  diff -r 4bb65dda5db4 file.txt
  --- a/file.txt
  +++ b/file.txt
  @@ -1,1 +1,1 @@
  -first
  +wdir

  $ cd ..

Testing diff --change when merge:

  $ cd a

  $ for i in 1 2 3 4 5 6 7 8 9 10; do
  >    echo $i >> file.txt
  > done
  $ hg commit -m "lots of text" # 3

  $ sed -e 's,^2$,x,' file.txt > file.txt.tmp
  $ mv file.txt.tmp file.txt
  $ hg commit -m "change 2 to x" # 4

  $ hg up -r 3
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ sed -e 's,^8$,y,' file.txt > file.txt.tmp
  $ mv file.txt.tmp file.txt
  $ hg commit -m "change 8 to y"
  created new head

  $ hg up -C -r 4
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge -r 5
  merging file.txt
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg commit -m "merge 8 to y" # 6

  $ hg diff --change 5
  diff -r ae119d680c82 -r 9085c5c02e52 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -6,6 +6,6 @@
   5
   6
   7
  -8
  +y
   9
   10

must be similar to 'hg diff --change 5':

  $ hg diff -c 6
  diff -r 273b50f17c6d -r 979ca961fd2e file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -6,6 +6,6 @@
   5
   6
   7
  -8
  +y
   9
   10

merge diff should show only manual edits to a merge:

  $ hg diff --config diff.merge=yes -c 6
(no diff output is expected here)

Construct an "evil merge" that does something other than just the merge.

  $ hg co ".^"
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge -r 5
  merging file.txt
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ echo 11 >> file.txt
  $ hg ci -m 'merge 8 to y with manual edit of 11' # 7
  created new head
  $ hg diff -c 7
  diff -r 273b50f17c6d -r 8ad85e839ba7 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -6,6 +6,7 @@
   5
   6
   7
  -8
  +y
   9
   10
  +11
Contrast with the `hg diff -c 7` version above: only the manual edit shows
up, making it easy to identify changes someone is otherwise trying to sneak
into a merge.
  $ hg diff --config diff.merge=yes -c 7
  diff -r 8ad85e839ba7 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -9,3 +9,4 @@
   y
   9
   10
  +11

Set up a conflict.
  $ hg co ".^"
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ sed -e 's,^8$,z,' file.txt > file.txt.tmp
  $ mv file.txt.tmp file.txt
  $ hg ci -m 'conflicting edit: 8 to z'
  created new head
  $ echo "this file is new in p1 of the merge" > new-file-p1.txt
  $ hg ci -Am 'new file' new-file-p1.txt
  $ hg log -r . --template 'p1 will be rev {rev}\n'
  p1 will be rev 9
  $ hg co 5
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo "this file is new in p2 of the merge" > new-file-p2.txt
  $ hg ci -Am 'new file' new-file-p2.txt
  created new head
  $ hg log -r . --template 'p2 will be rev {rev}\n'
  p2 will be rev 10
  $ hg co -- 9
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge -r 10
  merging file.txt
  warning: conflicts while merging file.txt! (edit, then use 'hg resolve --mark')
  1 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ hg revert file.txt -r .
  $ hg resolve -ma
  (no more unresolved files)
  $ hg commit -m 'merge conflicted edit'
Without diff.merge, it's a diff against p1
  $ hg diff --config diff.merge=no -c 11
  diff -r fd1f17c90d7c -r 5010caab09f6 new-file-p2.txt
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/new-file-p2.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +this file is new in p2 of the merge
With diff.merge, it's a diff against the conflicted content.
  $ hg diff --config diff.merge=yes -c 11
  diff -r 5010caab09f6 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -6,12 +6,6 @@
   5
   6
   7
  -<<<<<<< local: fd1f17c90d7c - test: new file
   z
  -||||||| base:  ae119d680c82 - test: lots of text
  -8
  -=======
  -y
  ->>>>>>> other: d9e7de69eac3 - test: new file
   9
   10

There must _NOT_ be a .hg/merge directory leftover.
  $ test ! -d .hg/merge
(No output is expected)
  $ cd ..

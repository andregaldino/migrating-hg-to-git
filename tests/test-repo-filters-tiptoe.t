===================================
Test repository filtering avoidance
===================================

This test file is a bit special as he does not check feature, but performance related internal code path.

Right now, filtering a repository comes with a cost that might be significant.
Until this get better, ther are various operation that try hard not to trigger
a filtering computation. This test file make sure we don't reintroduce code that trigger the filtering for these operation:

Setup
-----
  $ hg init test-repo
  $ cd test-repo
  $ echo "some line" > z
  $ echo a > a
  $ hg commit -Am a
  adding a
  adding z
  $ echo "in a" >> z
  $ echo b > b
  $ hg commit -Am b
  adding b
  $ echo "file" >> z
  $ echo c > c
  $ hg commit -Am c
  adding c
  $ hg rm a
  $ echo c1 > c
  $ hg add c
  c already tracked!
  $ echo d > d
  $ hg add d
  $ rm b

  $ cat << EOF >> $HGRCPATH
  > [devel]
  > debug.repo-filters = yes
  > [ui]
  > debug = yes
  > EOF


tests
-----

Getting the node of `null`

  $ hg log -r null -T "{node}\n"
  0000000000000000000000000000000000000000

Getting basic changeset inforation about `null`

  $ hg log -r null -T "{node}\n{date}\n"
  0000000000000000000000000000000000000000
  0.00

Getting status of null

  $ hg status --change null

Getting status of working copy

  $ hg status
  M c
  A d
  R a
  ! b

  $ hg status --copies
  M c
  A d
  R a
  ! b

Getting data about the working copy parent

  $ hg log -r '.' -T "{node}\n{date}\n"
  c2932ca7786be30b67154d541a8764fae5532261
  0.00

Getting working copy diff

  $ hg diff
  diff -r c2932ca7786be30b67154d541a8764fae5532261 a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ /dev/null	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +0,0 @@
  -a
  diff -r c2932ca7786be30b67154d541a8764fae5532261 c
  --- a/c	Thu Jan 01 00:00:00 1970 +0000
  +++ b/c	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -c
  +c1
  diff -r c2932ca7786be30b67154d541a8764fae5532261 d
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/d	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +d
  $ hg diff --change .
  diff -r 05293e5dd8d1ae4f84a8520a11c6f97cad26deca -r c2932ca7786be30b67154d541a8764fae5532261 c
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/c	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +c
  diff -r 05293e5dd8d1ae4f84a8520a11c6f97cad26deca -r c2932ca7786be30b67154d541a8764fae5532261 z
  --- a/z	Thu Jan 01 00:00:00 1970 +0000
  +++ b/z	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,2 +1,3 @@
   some line
   in a
  +file

exporting the current changeset

  $ hg export
  exporting patch:
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID c2932ca7786be30b67154d541a8764fae5532261
  # Parent  05293e5dd8d1ae4f84a8520a11c6f97cad26deca
  c
  
  diff -r 05293e5dd8d1ae4f84a8520a11c6f97cad26deca -r c2932ca7786be30b67154d541a8764fae5532261 c
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/c	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +c
  diff -r 05293e5dd8d1ae4f84a8520a11c6f97cad26deca -r c2932ca7786be30b67154d541a8764fae5532261 z
  --- a/z	Thu Jan 01 00:00:00 1970 +0000
  +++ b/z	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,2 +1,3 @@
   some line
   in a
  +file

using annotate

- file with a single change

  $ hg annotate a
  0: a

- file with multiple change

  $ hg annotate z
  0: some line
  1: in a
  2: file

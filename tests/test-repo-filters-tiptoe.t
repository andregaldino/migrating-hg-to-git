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

  $ hg init test-repo
  $ cd test-repo
  $ hg log -r null -T "{node}\n"
  0000000000000000000000000000000000000000

Getting basic changeset inforation about `null`

  $ hg log -r null -T "{node}\n{date}\n"
  0000000000000000000000000000000000000000
  0.00

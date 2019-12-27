
Graft from behind a move or rename
==================================

NOTE: This is affected by issue5343, and will need updating when it's fixed

Consider this topology for a regular graft:

o c1
|
| o c2
| |
| o ca # stands for "common ancestor"
|/
o cta # stands for "common topological ancestor"

Note that in issue5343, ca==cta.

The following table shows the possible cases. Here, "x->y" and, equivalently,
"y<-x", where x is an ancestor of y, means that some copy happened from x to y.

name | c1<-cta | cta<->ca | ca->c2
A.0  |         |          |
A.1  |    X    |          |
A.2  |         |     X    |
A.3  |         |          |   X
A.4  |    X    |     X    |
A.5  |    X    |          |   X
A.6  |         |     X    |   X
A.7  |    X    |     X    |   X

A.0 is trivial, and doesn't need copy tracking.
For A.1, a forward rename is recorded in the c1 pass, to be followed later.
In A.2, the rename is recorded in the c2 pass and followed backwards.
A.3 is recorded in the c2 pass as a forward rename to be duplicated on target.
In A.4, both passes of checkcopies record incomplete renames, which are
then joined in mergecopies to record a rename to be followed.
In A.5 and A.7, the c1 pass records an incomplete rename, while the c2 pass
records an incomplete divergence. The incomplete rename is then joined to the
appropriate side of the incomplete divergence, and the result is recorded as a
divergence. The code doesn't distinguish at all between these two cases, since
the end result of them is the same: an incomplete divergence joined with an
incomplete rename into a divergence.
Finally, A.6 records a divergence entirely in the c2 pass.

A.4 has a degenerate case a<-b<-a->a, where checkcopies isn't needed at all.
A.5 has a special case a<-b<-b->a, which is treated like a<-b->a in a merge.
A.5 has issue5343 as a special case.
A.6 has a special case a<-a<-b->a. Here, checkcopies will find a spurious
incomplete divergence, which is in fact complete. This is handled later in
mergecopies.
A.7 has 4 special cases: a<-b<-a->b (the "ping-pong" case), a<-b<-c->b,
a<-b<-a->c and a<-b<-c->a. Of these, only the "ping-pong" case is interesting,
the others are fairly trivial (a<-b<-c->b and a<-b<-a->c proceed like the base
case, a<-b<-c->a is treated the same as a<-b<-b->a).

f5a therefore tests the "ping-pong" rename case, where a file is renamed to the
same name on both branches, then the rename is backed out on one branch, and
the backout is grafted to the other branch. This creates a challenging rename
sequence of a<-b<-a->b in the graft target, topological CA, graft CA and graft
source, respectively. Since rename detection will run on the c1 side for such a
sequence (as for technical reasons, we split the c1 and c2 sides not at the
graft CA, but rather at the topological CA), it will pick up a false rename,
and cause a spurious merge conflict. This false rename is always exactly the
reverse of the true rename that would be detected on the c2 side, so we can
correct for it by detecting this condition and reversing as necessary.

First, set up the repository with commits to be grafted

  $ hg init graftmove
  $ cd graftmove
  $ echo c1a > f1a
  $ echo c2a > f2a
  $ echo c3a > f3a
  $ echo c4a > f4a
  $ echo c5a > f5a
  $ hg ci -qAm A0
  $ hg mv f1a f1b
  $ hg mv f3a f3b
  $ hg mv f5a f5b
  $ hg ci -qAm B0
  $ echo c1c > f1b
  $ hg mv f2a f2c
  $ hg mv f5b f5a
  $ echo c5c > f5a
  $ hg ci -qAm C0
  $ hg mv f3b f3d
  $ echo c4d > f4a
  $ hg ci -qAm D0
  $ hg log -G
  @  changeset:   3:b69f5839d2d9
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     D0
  |
  o  changeset:   2:f58c7e2b28fa
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     C0
  |
  o  changeset:   1:3d7bba921b5d
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     B0
  |
  o  changeset:   0:11f7a1b56675
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     A0
  

Test the cases A.2 (f1x), A.3 (f2x) and a special case of A.6 (f5x) where the
two renames actually converge to the same name (thus no actual divergence).

  $ hg up -q 'desc("A0")'
  $ HGEDITOR="echo C1 >" hg graft -r 'desc("C0")' --edit
  grafting 2:f58c7e2b28fa "C0"
  merging f1a and f1b to f1a
  merging f5a
  $ hg status --change .
  M f1a
  M f5a
  A f2c
  R f2a
  $ hg cat f1a
  c1c
  $ hg cat f1b
  f1b: no such file in rev c9763722f9bd
  [1]

Test the cases A.0 (f4x) and A.6 (f3x)

  $ HGEDITOR="echo D1 >" hg graft -r 'desc("D0")' --edit
  grafting 3:b69f5839d2d9 "D0"
  note: possible conflict - f3b was renamed multiple times to:
   f3a
   f3d

Set up the repository for some further tests

  $ hg up -q "min(desc("A0"))"
  $ hg mv f1a f1e
  $ echo c2e > f2a
  $ hg mv f3a f3e
  $ hg mv f4a f4e
  $ hg mv f5a f5b
  $ hg ci -qAm "E0"
  $ hg up -q "min(desc("A0"))"
  $ hg cp f1a f1f
  $ hg ci -qAm "F0"
  $ hg up -q "min(desc("A0"))"
  $ hg cp f1a f1g
  $ echo c1g > f1g
  $ hg ci -qAm "G0"
  $ hg log -G
  @  changeset:   8:ba67f08fb15a
  |  tag:         tip
  |  parent:      0:11f7a1b56675
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     G0
  |
  | o  changeset:   7:d376ab0d7fda
  |/   parent:      0:11f7a1b56675
  |    user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     F0
  |
  | o  changeset:   6:6bd1736cab86
  |/   parent:      0:11f7a1b56675
  |    user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     E0
  |
  | o  changeset:   5:560daee679da
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     D1
  | |
  | o  changeset:   4:c9763722f9bd
  |/   parent:      0:11f7a1b56675
  |    user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     C1
  |
  | o  changeset:   3:b69f5839d2d9
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     D0
  | |
  | o  changeset:   2:f58c7e2b28fa
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     C0
  | |
  | o  changeset:   1:3d7bba921b5d
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     B0
  |
  o  changeset:   0:11f7a1b56675
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     A0
  

Test the cases A.4 (f1x), the "ping-pong" special case of A.7 (f5x),
and A.3 with a local content change to be preserved (f2x).

  $ hg up -q "desc("E0")"
  $ HGEDITOR="echo C2 >" hg graft -r 'desc("C0")' --edit
  grafting 2:f58c7e2b28fa "C0"
  merging f1e and f1b to f1e
  merging f2a and f2c to f2c

Test the cases A.1 (f4x) and A.7 (f3x).

  $ HGEDITOR="echo D2 >" hg graft -r 'desc("D0")' --edit
  grafting 3:b69f5839d2d9 "D0"
  note: possible conflict - f3b was renamed multiple times to:
   f3d
   f3e
  merging f4e and f4a to f4e

  $ hg cat f2c
  c2e

Test the case A.5 (move case, f1x).

  $ hg up -q "desc("C0")"
  $ HGEDITOR="echo E1 >" hg graft -r 'desc("E0")' --edit
  grafting 6:6bd1736cab86 "E0"
  note: possible conflict - f1a was renamed multiple times to:
   f1b
   f1e
  note: possible conflict - f3a was renamed multiple times to:
   f3b
   f3e
  merging f2c and f2a to f2c
  merging f5a and f5b to f5b
  $ cat f1e
  c1a

Test the case A.5 (copy case, f1x).

  $ hg up -q "desc("C0")"
  $ HGEDITOR="echo F1 >" hg graft -r 'desc("F0")' --edit
  grafting 7:d376ab0d7fda "F0"
BROKEN: f1f should be marked a copy from f1b
  $ hg st --copies --change .
  A f1f
BROKEN: f1f should have the new content from f1b (i.e. "c1c")
  $ cat f1f
  c1a

Test the case A.5 (copy+modify case, f1x).

  $ hg up -q "desc("C0")"
BROKEN: We should get a merge conflict from the 3-way merge between f1b in C0
(content "c1c") and f1g in G0 (content "c1g") with f1a in A0 as base (content
"c1a")
  $ HGEDITOR="echo G1 >" hg graft -r 'desc("G0")' --edit
  grafting 8:ba67f08fb15a "G0"

Check the results of the grafts tested

  $ hg log -CGv --patch --git
  @  changeset:   13:ef3adf6c20a4
  |  tag:         tip
  |  parent:      2:f58c7e2b28fa
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  files:       f1g
  |  description:
  |  G1
  |
  |
  |  diff --git a/f1g b/f1g
  |  new file mode 100644
  |  --- /dev/null
  |  +++ b/f1g
  |  @@ -0,0 +1,1 @@
  |  +c1g
  |
  | o  changeset:   12:b5542d755b54
  |/   parent:      2:f58c7e2b28fa
  |    user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    files:       f1f
  |    description:
  |    F1
  |
  |
  |    diff --git a/f1f b/f1f
  |    new file mode 100644
  |    --- /dev/null
  |    +++ b/f1f
  |    @@ -0,0 +1,1 @@
  |    +c1a
  |
  | o  changeset:   11:f8a162271246
  |/   parent:      2:f58c7e2b28fa
  |    user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    files:       f1e f2c f3e f4a f4e f5a f5b
  |    copies:      f4e (f4a) f5b (f5a)
  |    description:
  |    E1
  |
  |
  |    diff --git a/f1e b/f1e
  |    new file mode 100644
  |    --- /dev/null
  |    +++ b/f1e
  |    @@ -0,0 +1,1 @@
  |    +c1a
  |    diff --git a/f2c b/f2c
  |    --- a/f2c
  |    +++ b/f2c
  |    @@ -1,1 +1,1 @@
  |    -c2a
  |    +c2e
  |    diff --git a/f3e b/f3e
  |    new file mode 100644
  |    --- /dev/null
  |    +++ b/f3e
  |    @@ -0,0 +1,1 @@
  |    +c3a
  |    diff --git a/f4a b/f4e
  |    rename from f4a
  |    rename to f4e
  |    diff --git a/f5a b/f5b
  |    rename from f5a
  |    rename to f5b
  |
  | o  changeset:   10:93ee502e8b0a
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  files:       f3d f4e
  | |  description:
  | |  D2
  | |
  | |
  | |  diff --git a/f3d b/f3d
  | |  new file mode 100644
  | |  --- /dev/null
  | |  +++ b/f3d
  | |  @@ -0,0 +1,1 @@
  | |  +c3a
  | |  diff --git a/f4e b/f4e
  | |  --- a/f4e
  | |  +++ b/f4e
  | |  @@ -1,1 +1,1 @@
  | |  -c4a
  | |  +c4d
  | |
  | o  changeset:   9:539cf145f496
  | |  parent:      6:6bd1736cab86
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  files:       f1e f2a f2c f5a f5b
  | |  copies:      f2c (f2a) f5a (f5b)
  | |  description:
  | |  C2
  | |
  | |
  | |  diff --git a/f1e b/f1e
  | |  --- a/f1e
  | |  +++ b/f1e
  | |  @@ -1,1 +1,1 @@
  | |  -c1a
  | |  +c1c
  | |  diff --git a/f2a b/f2c
  | |  rename from f2a
  | |  rename to f2c
  | |  diff --git a/f5b b/f5a
  | |  rename from f5b
  | |  rename to f5a
  | |  --- a/f5b
  | |  +++ b/f5a
  | |  @@ -1,1 +1,1 @@
  | |  -c5a
  | |  +c5c
  | |
  | | o  changeset:   8:ba67f08fb15a
  | | |  parent:      0:11f7a1b56675
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  files:       f1g
  | | |  copies:      f1g (f1a)
  | | |  description:
  | | |  G0
  | | |
  | | |
  | | |  diff --git a/f1a b/f1g
  | | |  copy from f1a
  | | |  copy to f1g
  | | |  --- a/f1a
  | | |  +++ b/f1g
  | | |  @@ -1,1 +1,1 @@
  | | |  -c1a
  | | |  +c1g
  | | |
  | | | o  changeset:   7:d376ab0d7fda
  | | |/   parent:      0:11f7a1b56675
  | | |    user:        test
  | | |    date:        Thu Jan 01 00:00:00 1970 +0000
  | | |    files:       f1f
  | | |    copies:      f1f (f1a)
  | | |    description:
  | | |    F0
  | | |
  | | |
  | | |    diff --git a/f1a b/f1f
  | | |    copy from f1a
  | | |    copy to f1f
  | | |
  | o |  changeset:   6:6bd1736cab86
  | |/   parent:      0:11f7a1b56675
  | |    user:        test
  | |    date:        Thu Jan 01 00:00:00 1970 +0000
  | |    files:       f1a f1e f2a f3a f3e f4a f4e f5a f5b
  | |    copies:      f1e (f1a) f3e (f3a) f4e (f4a) f5b (f5a)
  | |    description:
  | |    E0
  | |
  | |
  | |    diff --git a/f1a b/f1e
  | |    rename from f1a
  | |    rename to f1e
  | |    diff --git a/f2a b/f2a
  | |    --- a/f2a
  | |    +++ b/f2a
  | |    @@ -1,1 +1,1 @@
  | |    -c2a
  | |    +c2e
  | |    diff --git a/f3a b/f3e
  | |    rename from f3a
  | |    rename to f3e
  | |    diff --git a/f4a b/f4e
  | |    rename from f4a
  | |    rename to f4e
  | |    diff --git a/f5a b/f5b
  | |    rename from f5a
  | |    rename to f5b
  | |
  | | o  changeset:   5:560daee679da
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  files:       f3d f4a
  | | |  description:
  | | |  D1
  | | |
  | | |
  | | |  diff --git a/f3d b/f3d
  | | |  new file mode 100644
  | | |  --- /dev/null
  | | |  +++ b/f3d
  | | |  @@ -0,0 +1,1 @@
  | | |  +c3a
  | | |  diff --git a/f4a b/f4a
  | | |  --- a/f4a
  | | |  +++ b/f4a
  | | |  @@ -1,1 +1,1 @@
  | | |  -c4a
  | | |  +c4d
  | | |
  | | o  changeset:   4:c9763722f9bd
  | |/   parent:      0:11f7a1b56675
  | |    user:        test
  | |    date:        Thu Jan 01 00:00:00 1970 +0000
  | |    files:       f1a f2a f2c f5a
  | |    copies:      f2c (f2a)
  | |    description:
  | |    C1
  | |
  | |
  | |    diff --git a/f1a b/f1a
  | |    --- a/f1a
  | |    +++ b/f1a
  | |    @@ -1,1 +1,1 @@
  | |    -c1a
  | |    +c1c
  | |    diff --git a/f2a b/f2c
  | |    rename from f2a
  | |    rename to f2c
  | |    diff --git a/f5a b/f5a
  | |    --- a/f5a
  | |    +++ b/f5a
  | |    @@ -1,1 +1,1 @@
  | |    -c5a
  | |    +c5c
  | |
  +---o  changeset:   3:b69f5839d2d9
  | |    user:        test
  | |    date:        Thu Jan 01 00:00:00 1970 +0000
  | |    files:       f3b f3d f4a
  | |    copies:      f3d (f3b)
  | |    description:
  | |    D0
  | |
  | |
  | |    diff --git a/f3b b/f3d
  | |    rename from f3b
  | |    rename to f3d
  | |    diff --git a/f4a b/f4a
  | |    --- a/f4a
  | |    +++ b/f4a
  | |    @@ -1,1 +1,1 @@
  | |    -c4a
  | |    +c4d
  | |
  o |  changeset:   2:f58c7e2b28fa
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  files:       f1b f2a f2c f5a f5b
  | |  copies:      f2c (f2a) f5a (f5b)
  | |  description:
  | |  C0
  | |
  | |
  | |  diff --git a/f1b b/f1b
  | |  --- a/f1b
  | |  +++ b/f1b
  | |  @@ -1,1 +1,1 @@
  | |  -c1a
  | |  +c1c
  | |  diff --git a/f2a b/f2c
  | |  rename from f2a
  | |  rename to f2c
  | |  diff --git a/f5b b/f5a
  | |  rename from f5b
  | |  rename to f5a
  | |  --- a/f5b
  | |  +++ b/f5a
  | |  @@ -1,1 +1,1 @@
  | |  -c5a
  | |  +c5c
  | |
  o |  changeset:   1:3d7bba921b5d
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    files:       f1a f1b f3a f3b f5a f5b
  |    copies:      f1b (f1a) f3b (f3a) f5b (f5a)
  |    description:
  |    B0
  |
  |
  |    diff --git a/f1a b/f1b
  |    rename from f1a
  |    rename to f1b
  |    diff --git a/f3a b/f3b
  |    rename from f3a
  |    rename to f3b
  |    diff --git a/f5a b/f5b
  |    rename from f5a
  |    rename to f5b
  |
  o  changeset:   0:11f7a1b56675
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     files:       f1a f2a f3a f4a f5a
     description:
     A0
  
  
     diff --git a/f1a b/f1a
     new file mode 100644
     --- /dev/null
     +++ b/f1a
     @@ -0,0 +1,1 @@
     +c1a
     diff --git a/f2a b/f2a
     new file mode 100644
     --- /dev/null
     +++ b/f2a
     @@ -0,0 +1,1 @@
     +c2a
     diff --git a/f3a b/f3a
     new file mode 100644
     --- /dev/null
     +++ b/f3a
     @@ -0,0 +1,1 @@
     +c3a
     diff --git a/f4a b/f4a
     new file mode 100644
     --- /dev/null
     +++ b/f4a
     @@ -0,0 +1,1 @@
     +c4a
     diff --git a/f5a b/f5a
     new file mode 100644
     --- /dev/null
     +++ b/f5a
     @@ -0,0 +1,1 @@
     +c5a
  
Check superfluous filemerge of files renamed in the past but untouched by graft

  $ echo a > a
  $ hg ci -qAma
  $ hg mv a b
  $ echo b > b
  $ hg ci -qAmb
  $ echo c > c
  $ hg ci -qAmc
  $ hg up -q .~2
  $ hg graft tip -qt:fail

  $ cd ..

Graft a change into a new file previously grafted into a renamed directory

  $ hg init dirmovenewfile
  $ cd dirmovenewfile
  $ mkdir a
  $ echo a > a/a
  $ hg ci -qAma
  $ echo x > a/x
  $ hg ci -qAmx
  $ hg up -q 0
  $ hg mv -q a b
  $ hg ci -qAmb
  $ hg graft -q 1 # a/x grafted as b/x, but no copy information recorded
  $ hg up -q 1
  $ echo y > a/x
  $ hg ci -qAmy
  $ hg up -q 3
  $ hg graft -q 4
  $ hg status --change .
  M b/x

Prepare for test of skipped changesets and how merges can influence it:

  $ hg merge -q -r 1 --tool :local
  $ hg ci -m m
  $ echo xx >> b/x
  $ hg ci -m xx

  $ hg log -G -T '{rev} {desc|firstline}'
  @  7 xx
  |
  o    6 m
  |\
  | o  5 y
  | |
  +---o  4 y
  | |
  | o  3 x
  | |
  | o  2 b
  | |
  o |  1 x
  |/
  o  0 a
  
Grafting of plain changes correctly detects that 3 and 5 should be skipped:

  $ hg up -qCr 4
  $ hg graft --tool :local -r 2::5
  skipping already grafted revision 3:ca093ca2f1d9 (was grafted from 1:13ec5badbf2a)
  skipping already grafted revision 5:43e9eb70dab0 (was grafted from 4:6c9a1289e5f1)
  grafting 2:42127f193bcd "b"

Extending the graft range to include a (skipped) merge of 3 will not prevent us from
also detecting that both 3 and 5 should be skipped:

  $ hg up -qCr 4
  $ hg graft --tool :local -r 2::7
  skipping ungraftable merge revision 6
  skipping already grafted revision 3:ca093ca2f1d9 (was grafted from 1:13ec5badbf2a)
  skipping already grafted revision 5:43e9eb70dab0 (was grafted from 4:6c9a1289e5f1)
  grafting 2:42127f193bcd "b"
  grafting 7:d3c3f2b38ecc "xx"
  note: graft of 7:d3c3f2b38ecc created no changes to commit

  $ cd ..

Grafted revision should be warned and skipped only once. (issue6024)

  $ mkdir issue6024
  $ cd issue6024

  $ hg init base
  $ cd base
  $ touch x
  $ hg commit -qAminit
  $ echo a > x
  $ hg commit -mchange
  $ hg update -q 0
  $ hg graft -r 1
  grafting 1:a0b923c546aa "change" (tip)
  $ cd ..

  $ hg clone -qr 2 base clone
  $ cd clone
  $ hg pull -q
  $ hg merge -q 2
  $ hg commit -mmerge
  $ hg update -q 0
  $ hg graft -r 1
  grafting 1:04fc6d444368 "change"
  $ hg update -q 3
  $ hg log -G -T '{rev}:{node|shortest} <- {extras.source|shortest}\n'
  o  4:4e16 <- a0b9
  |
  | @    3:f0ac <-
  | |\
  +---o  2:a0b9 <-
  | |
  | o  1:04fc <- a0b9
  |/
  o  0:7848 <-
  

 the source of rev 4 is an ancestor of the working parent, and was also
 grafted as rev 1. it should be stripped from the target revisions only once.

  $ hg graft -r 4
  skipping already grafted revision 4:4e16bab40c9c (1:04fc6d444368 also has origin 2:a0b923c546aa)
  [255]

  $ cd ../..

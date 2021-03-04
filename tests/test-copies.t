#testcases filelog compatibility changeset sidedata

  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > rebase=
  > [alias]
  > l = log -G -T '{rev} {desc}\n{files}\n'
  > EOF

#if compatibility
  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > copies.read-from = compatibility
  > EOF
#endif

#if changeset
  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > copies.read-from = changeset-only
  > copies.write-to = changeset-only
  > EOF
#endif

#if sidedata
  $ cat >> $HGRCPATH << EOF
  > [format]
  > exp-use-copies-side-data-changeset = yes
  > EOF
#endif

  $ REPONUM=0
  $ newrepo() {
  >     cd $TESTTMP
  >     REPONUM=`expr $REPONUM + 1`
  >     hg init repo-$REPONUM
  >     cd repo-$REPONUM
  > }

Simple rename case
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg mv x y
  $ hg debugp1copies
  x -> y
  $ hg debugp2copies
  $ hg ci -m 'rename x to y'
  $ hg l
  @  1 rename x to y
  |  x y
  o  0 add x
     x
  $ hg debugp1copies -r 1
  x -> y
  $ hg debugpathcopies 0 1
  x -> y
  $ hg debugpathcopies 1 0
  y -> x
Test filtering copies by path. We do filtering by destination.
  $ hg debugpathcopies 0 1 x
  $ hg debugpathcopies 1 0 x
  y -> x
  $ hg debugpathcopies 0 1 y
  x -> y
  $ hg debugpathcopies 1 0 y

Copies not including commit changes
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg mv x y
  $ hg debugpathcopies . .
  $ hg debugpathcopies . 'wdir()'
  x -> y
  $ hg debugpathcopies 'wdir()' .
  y -> x

Copy a file onto another file
  $ newrepo
  $ echo x > x
  $ echo y > y
  $ hg ci -Aqm 'add x and y'
  $ hg cp -f x y
  $ hg debugp1copies
  x -> y
  $ hg debugp2copies
  $ hg ci -m 'copy x onto y'
  $ hg l
  @  1 copy x onto y
  |  y
  o  0 add x and y
     x y
  $ hg debugp1copies -r 1
  x -> y
  $ hg debugpathcopies 0 1
  x -> y (no-filelog !)
  $ hg debugpathcopies 0 1  --config devel.copy-tracing.trace-all-files=yes
  x -> y

Copy a file onto another file with same content. If metadata is stored in changeset, this does not
produce a new filelog entry. The changeset's "files" entry should still list the file.
  $ newrepo
  $ echo x > x
  $ echo x > x2
  $ hg ci -Aqm 'add x and x2 with same content'
  $ hg cp -f x x2
  $ hg ci -m 'copy x onto x2'
  $ hg l
  @  1 copy x onto x2
  |  x2
  o  0 add x and x2 with same content
     x x2
  $ hg debugp1copies -r 1
  x -> x2
  $ hg debugpathcopies 0 1
  x -> x2 (no-filelog !)
  $ hg debugpathcopies 0 1  --config devel.copy-tracing.trace-all-files=yes
  x -> x2

Rename file in a loop: x->y->z->x
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg mv x y
  $ hg debugp1copies
  x -> y
  $ hg debugp2copies
  $ hg ci -m 'rename x to y'
  $ hg mv y z
  $ hg ci -m 'rename y to z'
  $ hg mv z x
  $ hg ci -m 'rename z to x'
  $ hg l
  @  3 rename z to x
  |  x z
  o  2 rename y to z
  |  y z
  o  1 rename x to y
  |  x y
  o  0 add x
     x
  $ hg debugpathcopies 0 3

Copy x to z, then remove z, then copy x2 (same content as x) to z. With copy metadata in the
changeset, the two copies here will have the same filelog entry, so ctx['z'].introrev() might point
to the first commit that added the file. We should still report the copy as being from x2.
  $ newrepo
  $ echo x > x
  $ echo x > x2
  $ hg ci -Aqm 'add x and x2 with same content'
  $ hg cp x z
  $ hg ci -qm 'copy x to z'
  $ hg rm z
  $ hg ci -m 'remove z'
  $ hg cp x2 z
  $ hg ci -m 'copy x2 to z'
  $ hg l
  @  3 copy x2 to z
  |  z
  o  2 remove z
  |  z
  o  1 copy x to z
  |  z
  o  0 add x and x2 with same content
     x x2
  $ hg debugp1copies -r 3
  x2 -> z
  $ hg debugpathcopies 0 3
  x2 -> z

Create x and y, then rename them both to the same name, but on different sides of a fork
  $ newrepo
  $ echo x > x
  $ echo y > y
  $ hg ci -Aqm 'add x and y'
  $ hg mv x z
  $ hg ci -qm 'rename x to z'
  $ hg co -q 0
  $ hg mv y z
  $ hg ci -qm 'rename y to z'
  $ hg l
  @  2 rename y to z
  |  y z
  | o  1 rename x to z
  |/   x z
  o  0 add x and y
     x y
  $ hg debugpathcopies 1 2
  z -> x
  y -> z

Fork renames x to y on one side and removes x on the other
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg mv x y
  $ hg ci -m 'rename x to y'
  $ hg co -q 0
  $ hg rm x
  $ hg ci -m 'remove x'
  created new head
  $ hg l
  @  2 remove x
  |  x
  | o  1 rename x to y
  |/   x y
  o  0 add x
     x
  $ hg debugpathcopies 1 2

Merge rename from other branch
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg mv x y
  $ hg ci -m 'rename x to y'
  $ hg co -q 0
  $ echo z > z
  $ hg ci -Aqm 'add z'
  $ hg merge -q 1
  $ hg debugp1copies
  $ hg debugp2copies
  $ hg ci -m 'merge rename from p2'
  $ hg l
  @    3 merge rename from p2
  |\
  | o  2 add z
  | |  z
  o |  1 rename x to y
  |/   x y
  o  0 add x
     x
Perhaps we should indicate the rename here, but `hg status` is documented to be weird during
merges, so...
  $ hg debugp1copies -r 3
  $ hg debugp2copies -r 3
  $ hg debugpathcopies 0 3
  x -> y
  $ hg debugpathcopies 1 2
  y -> x
  $ hg debugpathcopies 1 3
  $ hg debugpathcopies 2 3
  x -> y

Copy file from either side in a merge
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg co -q null
  $ echo y > y
  $ hg ci -Aqm 'add y'
  $ hg merge -q 0
  $ hg cp y z
  $ hg debugp1copies
  y -> z
  $ hg debugp2copies
  $ hg ci -m 'copy file from p1 in merge'
  $ hg co -q 1
  $ hg merge -q 0
  $ hg cp x z
  $ hg debugp1copies
  $ hg debugp2copies
  x -> z
  $ hg ci -qm 'copy file from p2 in merge'
  $ hg l
  @    3 copy file from p2 in merge
  |\   z
  +---o  2 copy file from p1 in merge
  | |/   z
  | o  1 add y
  |    y
  o  0 add x
     x
  $ hg debugp1copies -r 2
  y -> z
  $ hg debugp2copies -r 2
  $ hg debugpathcopies 1 2
  y -> z
  $ hg debugpathcopies 0 2
  $ hg debugp1copies -r 3
  $ hg debugp2copies -r 3
  x -> z
  $ hg debugpathcopies 1 3
  $ hg debugpathcopies 0 3
  x -> z

Copy file that exists on both sides of the merge, same content on both sides
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x on branch 1'
  $ hg co -q null
  $ echo x > x
  $ hg ci -Aqm 'add x on branch 2'
  $ hg merge -q 0
  $ hg cp x z
  $ hg debugp1copies
  x -> z
  $ hg debugp2copies
  $ hg ci -qm 'merge'
  $ hg l
  @    2 merge
  |\   z
  | o  1 add x on branch 2
  |    x
  o  0 add x on branch 1
     x
  $ hg debugp1copies -r 2
  x -> z
  $ hg debugp2copies -r 2
It's a little weird that it shows up on both sides
  $ hg debugpathcopies 1 2
  x -> z
  $ hg debugpathcopies 0 2
  x -> z (filelog !)

Copy file that exists on both sides of the merge, different content
  $ newrepo
  $ echo branch1 > x
  $ hg ci -Aqm 'add x on branch 1'
  $ hg co -q null
  $ echo branch2 > x
  $ hg ci -Aqm 'add x on branch 2'
  $ hg merge -q 0
  warning: conflicts while merging x! (edit, then use 'hg resolve --mark')
  [1]
  $ echo resolved > x
  $ hg resolve -m x
  (no more unresolved files)
  $ hg cp x z
  $ hg debugp1copies
  x -> z
  $ hg debugp2copies
  $ hg ci -qm 'merge'
  $ hg l
  @    2 merge
  |\   x z
  | o  1 add x on branch 2
  |    x
  o  0 add x on branch 1
     x
  $ hg debugp1copies -r 2
  x -> z (changeset !)
  x -> z (sidedata !)
  $ hg debugp2copies -r 2
  x -> z (no-changeset no-sidedata !)
  $ hg debugpathcopies 1 2
  x -> z (changeset !)
  x -> z (sidedata !)
  $ hg debugpathcopies 0 2
  x -> z (no-changeset no-sidedata !)

Copy x->y on one side of merge and copy x->z on the other side. Pathcopies from one parent
of the merge to the merge should include the copy from the other side.
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg cp x y
  $ hg ci -qm 'copy x to y'
  $ hg co -q 0
  $ hg cp x z
  $ hg ci -qm 'copy x to z'
  $ hg merge -q 1
  $ hg ci -m 'merge copy x->y and copy x->z'
  $ hg l
  @    3 merge copy x->y and copy x->z
  |\
  | o  2 copy x to z
  | |  z
  o |  1 copy x to y
  |/   y
  o  0 add x
     x
  $ hg debugp1copies -r 3
  $ hg debugp2copies -r 3
  $ hg debugpathcopies 2 3
  x -> y
  $ hg debugpathcopies 1 3
  x -> z

Copy x->y on two separate branches. Pathcopies from one branch to the other
should not report the copy.
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg cp x y
  $ hg ci -qm 'copy x to y'
  $ hg co -q 0
  $ hg graft 1 -q
  $ hg l
  @  2 copy x to y
  |  y
  | o  1 copy x to y
  |/   y
  o  0 add x
     x
  $ hg debugp1copies -r 1
  x -> y
  $ hg debugp1copies -r 2
  x -> y
  $ hg debugpathcopies 1 2
  $ hg debugpathcopies 2 1

Copy x to y on one side of merge, create y and rename to z on the other side.
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg cp x y
  $ hg ci -qm 'copy x to y'
  $ hg co -q 0
  $ echo y > y
  $ hg ci -Aqm 'add y'
  $ hg mv y z
  $ hg ci -m 'rename y to z'
  $ hg merge -q 1
  $ hg ci -m 'merge'
  $ hg l
  @    4 merge
  |\
  | o  3 rename y to z
  | |  y z
  | o  2 add y
  | |  y
  o |  1 copy x to y
  |/   y
  o  0 add x
     x
  $ hg debugp1copies -r 3
  y -> z
  $ hg debugp2copies -r 3
  $ hg debugpathcopies 2 3
  y -> z
  $ hg debugpathcopies 1 3
  y -> z (no-filelog !)

Create x and y, then rename x to z on one side of merge, and rename y to z and
modify z on the other side. When storing copies in the changeset, we don't
filter out copies whose target was created on the other side of the merge.
  $ newrepo
  $ echo x > x
  $ echo y > y
  $ hg ci -Aqm 'add x and y'
  $ hg mv x z
  $ hg ci -qm 'rename x to z'
  $ hg co -q 0
  $ hg mv y z
  $ hg ci -qm 'rename y to z'
  $ echo z >> z
  $ hg ci -m 'modify z'
  $ hg merge -q 1
  warning: conflicts while merging z! (edit, then use 'hg resolve --mark')
  [1]
  $ echo z > z
  $ hg resolve -qm z
  $ hg ci -m 'merge 1 into 3'
Try merging the other direction too
  $ hg co -q 1
  $ hg merge -q 3
  warning: conflicts while merging z! (edit, then use 'hg resolve --mark')
  [1]
  $ echo z > z
  $ hg resolve -qm z
  $ hg ci -m 'merge 3 into 1'
  created new head
  $ hg l
  @    5 merge 3 into 1
  |\   z
  +---o  4 merge 1 into 3
  | |/   z
  | o  3 modify z
  | |  z
  | o  2 rename y to z
  | |  y z
  o |  1 rename x to z
  |/   x z
  o  0 add x and y
     x y
  $ hg debugpathcopies 1 4
  y -> z (no-filelog !)
  $ hg debugpathcopies 2 4
  x -> z (no-filelog !)
  $ hg debugpathcopies 0 4
  x -> z (filelog !)
  y -> z (no-filelog !)
  $ hg debugpathcopies 1 5
  y -> z (no-filelog !)
  $ hg debugpathcopies 2 5
  x -> z (no-filelog !)
  $ hg debugpathcopies 0 5
  x -> z

Create x and y, then remove y and rename x to y on one side of merge, and
modify x on the other side. The modification to x from the second side
should be propagated to y.
  $ newrepo
  $ echo original > x
  $ hg add x
  $ echo unrelated > y
  $ hg add y
  $ hg commit -m 'add x and y'
  $ hg remove y
  $ hg commit -m 'remove y'
  $ hg rename x y
  $ hg commit -m 'rename x to y'
  $ hg checkout -q 0
  $ echo modified > x
  $ hg commit -m 'modify x'
  created new head
  $ hg l
  @  3 modify x
  |  x
  | o  2 rename x to y
  | |  x y
  | o  1 remove y
  |/   y
  o  0 add x and y
     x y
#if filelog
  $ hg merge 2
  file 'x' was deleted in other [merge rev] but was modified in local [working copy].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  1 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
This should ideally be "modified", but we will probably not be able to fix
that in the filelog case.
  $ cat y
  original
#else
  $ hg merge 2
  merging x and y to y
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ cat y
  modified
#endif
Same as above, but in the opposite direction
#if filelog
  $ hg co -qC 2
  $ hg merge 3
  file 'x' was deleted in local [working copy] but was modified in other [merge rev].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
BROKEN: should be "modified"
  $ cat y
  original
#else
  $ hg co -qC 2
  $ hg merge 3
  merging y and x to y
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ cat y
  modified
#endif

Create x and y, then rename x to z on one side of merge, and rename y to z and
then delete z on the other side.
  $ newrepo
  $ echo x > x
  $ echo y > y
  $ hg ci -Aqm 'add x and y'
  $ hg mv x z
  $ hg ci -qm 'rename x to z'
  $ hg co -q 0
  $ hg mv y z
  $ hg ci -qm 'rename y to z'
  $ hg rm z
  $ hg ci -m 'delete z'
  $ hg merge -q 1
  $ echo z > z
  $ hg ci -m 'merge 1 into 3'
Try merging the other direction too
  $ hg co -q 1
  $ hg merge -q 3
  $ echo z > z
  $ hg ci -m 'merge 3 into 1'
  created new head
  $ hg l
  @    5 merge 3 into 1
  |\   z
  +---o  4 merge 1 into 3
  | |/   z
  | o  3 delete z
  | |  z
  | o  2 rename y to z
  | |  y z
  o |  1 rename x to z
  |/   x z
  o  0 add x and y
     x y
  $ hg debugpathcopies 1 4
  $ hg debugpathcopies 2 4
  x -> z (no-filelog !)
  $ hg debugpathcopies 0 4
  x -> z (no-changeset no-compatibility !)
  $ hg debugpathcopies 1 5
  $ hg debugpathcopies 2 5
  x -> z (no-filelog !)
  $ hg debugpathcopies 0 5
  x -> z


Test for a case in fullcopytracing algorithm where neither of the merging csets
is a descendant of the merge base. This test reflects that the algorithm
correctly finds the copies:

  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > evolution.createmarkers=True
  > evolution.allowunstable=True
  > EOF

  $ newrepo
  $ echo a > a
  $ hg add a
  $ hg ci -m "added a"
  $ echo b > b
  $ hg add b
  $ hg ci -m "added b"

  $ hg mv b b1
  $ hg ci -m "rename b to b1"

  $ hg up ".^"
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo d > d
  $ hg add d
  $ hg ci -m "added d"
  created new head

  $ echo baba >> b
  $ hg ci --amend -m "added d, modified b"

  $ hg l --hidden
  @  4 added d, modified b
  |  b d
  | x  3 added d
  |/   d
  | o  2 rename b to b1
  |/   b b1
  o  1 added b
  |  b
  o  0 added a
     a

Grafting revision 4 on top of revision 2, showing that it respect the rename:

  $ hg up 2 -q
  $ hg graft -r 4 --base 3 --hidden
  grafting 4:af28412ec03c "added d, modified b" (tip) (no-changeset !)
  grafting 4:6325ca0b7a1c "added d, modified b" (tip) (changeset !)
  merging b1 and b to b1

  $ hg l -l1 -p
  @  5 added d, modified b
  |  b1
  ~  diff -r 5a4825cc2926 -r 94a2f1a0e8e2 b1 (no-changeset !)
  ~  diff -r 0a0ed3b3251c -r d544fb655520 b1 (changeset !)
     --- a/b1	Thu Jan 01 00:00:00 1970 +0000
     +++ b/b1	Thu Jan 01 00:00:00 1970 +0000
     @@ -1,1 +1,2 @@
      b
     +baba
  
Test to make sure that fullcopytracing algorithm doesn't fail when neither of the
merging csets is a descendant of the base.
-------------------------------------------------------------------------------------------------

  $ newrepo
  $ echo a > a
  $ hg add a
  $ hg ci -m "added a"
  $ echo b > b
  $ hg add b
  $ hg ci -m "added b"

  $ echo foobar > willconflict
  $ hg add willconflict
  $ hg ci -m "added willconflict"
  $ echo c > c
  $ hg add c
  $ hg ci -m "added c"

  $ hg l
  @  3 added c
  |  c
  o  2 added willconflict
  |  willconflict
  o  1 added b
  |  b
  o  0 added a
     a

  $ hg up ".^^"
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ echo d > d
  $ hg add d
  $ hg ci -m "added d"
  created new head

  $ echo barfoo > willconflict
  $ hg add willconflict
  $ hg ci --amend -m "added willconflict and d"

  $ hg l
  @  5 added willconflict and d
  |  d willconflict
  | o  3 added c
  | |  c
  | o  2 added willconflict
  |/   willconflict
  o  1 added b
  |  b
  o  0 added a
     a

  $ hg rebase -r . -d 2 -t :other
  rebasing 5:5018b1509e94 tip "added willconflict and d" (no-changeset !)
  rebasing 5:af8d273bf580 tip "added willconflict and d" (changeset !)

  $ hg up 3 -q
  $ hg l --hidden
  o  6 added willconflict and d
  |  d willconflict
  | x  5 added willconflict and d
  | |  d willconflict
  | | x  4 added d
  | |/   d
  +---@  3 added c
  | |    c
  o |  2 added willconflict
  |/   willconflict
  o  1 added b
  |  b
  o  0 added a
     a

Now if we trigger a merge between revision 3 and 6 using base revision 4,
neither of the merging csets will be a descendant of the base revision:

  $ hg graft -r 6 --base 4 --hidden -t :other
  grafting 6:99802e4f1e46 "added willconflict and d" (tip) (no-changeset !)
  grafting 6:b19f0df72728 "added willconflict and d" (tip) (changeset !)

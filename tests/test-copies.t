
  $ cat >> $HGRCPATH << EOF
  > [alias]
  > l = log -G -T '{rev} {desc}\n{files}\n'
  > EOF

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
  $ hg ci -m 'rename x to y'
  $ hg l
  @  1 rename x to y
  |  x y
  o  0 add x
     x
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
BROKEN: the following command should not include the copy
  $ hg debugpathcopies 1 0 y
  y -> x

Copy a file onto another file
  $ newrepo
  $ echo x > x
  $ echo y > y
  $ hg ci -Aqm 'add x and y'
  $ hg cp -f x y
  $ hg ci -m 'copy x onto y'
  $ hg l
  @  1 copy x onto y
  |  y
  o  0 add x and y
     x y
Incorrectly doesn't show the rename
  $ hg debugpathcopies 0 1

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
Incorrectly doesn't show the rename
  $ hg debugpathcopies 0 1

Copy a file, then delete destination, then copy again. This does not create a new filelog entry.
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg cp x y
  $ hg ci -m 'copy x to y'
  $ hg rm y
  $ hg ci -m 'remove y'
  $ hg cp -f x y
  $ hg ci -m 'copy x onto y (again)'
  $ hg l
  @  3 copy x onto y (again)
  |  y
  o  2 remove y
  |  y
  o  1 copy x to y
  |  y
  o  0 add x
     x
  $ hg debugpathcopies 0 3
  x -> y

Rename file in a loop: x->y->z->x
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg mv x y
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

Copy x to y, then remove y, then add back y. With copy metadata in the changeset, this could easily
end up reporting y as copied from x (if we don't unmark it as a copy when it's removed).
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg mv x y
  $ hg ci -m 'rename x to y'
  $ hg rm y
  $ hg ci -qm 'remove y'
  $ echo x > y
  $ hg ci -Aqm 'add back y'
  $ hg l
  @  3 add back y
  |  y
  o  2 remove y
  |  y
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
BROKEN: x doesn't exist here
  $ hg debugpathcopies 1 2
  y -> x

Copies via null revision (there shouldn't be any)
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg cp x y
  $ hg ci -m 'copy x to y'
  $ hg co -q null
  $ echo x > x
  $ hg ci -Aqm 'add x (again)'
  $ hg l
  @  2 add x (again)
     x
  o  1 copy x to y
  |  y
  o  0 add x
     x
  $ hg debugpathcopies 1 2
  $ hg debugpathcopies 2 1

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
  $ hg ci -m 'merge rename from p2'
  $ hg l
  @    3 merge rename from p2
  |\   x
  | o  2 add z
  | |  z
  o |  1 rename x to y
  |/   x y
  o  0 add x
     x
Perhaps we should indicate the rename here, but `hg status` is documented to be weird during
merges, so...
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
  $ hg ci -m 'copy file from p1 in merge'
  $ hg co -q 1
  $ hg merge -q 0
  $ hg cp x z
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
  $ hg debugpathcopies 1 2
  y -> z
  $ hg debugpathcopies 0 2
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
  $ hg ci -qm 'merge'
  $ hg l
  @    2 merge
  |\   z
  | o  1 add x on branch 2
  |    x
  o  0 add x on branch 1
     x
It's a little weird that it shows up on both sides
  $ hg debugpathcopies 1 2
  x -> z
  $ hg debugpathcopies 0 2
  x -> z

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
  $ hg ci -qm 'merge'
  $ hg l
  @    2 merge
  |\   x z
  | o  1 add x on branch 2
  |    x
  o  0 add x on branch 1
     x
  $ hg debugpathcopies 1 2
  $ hg debugpathcopies 0 2
  x -> z

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
  $ hg debugpathcopies 2 3
  x -> y
  $ hg debugpathcopies 1 3
  x -> z

Copy x to y on one side of merge, create y and rename to z on the other side. Pathcopies from the
first side should not include the y->z rename since y didn't exist in the merge base.
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
  $ hg debugpathcopies 2 3
  y -> z
  $ hg debugpathcopies 1 3

Create x and y, then rename x to z on one side of merge, and rename y to z and modify z on the
other side.
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
  |\   y z
  +---o  4 merge 1 into 3
  | |/   x z
  | o  3 modify z
  | |  z
  | o  2 rename y to z
  | |  y z
  o |  1 rename x to z
  |/   x z
  o  0 add x and y
     x y
  $ hg debugpathcopies 1 4
  $ hg debugpathcopies 2 4
  $ hg debugpathcopies 0 4
  x -> z
  $ hg debugpathcopies 1 5
  $ hg debugpathcopies 2 5
  $ hg debugpathcopies 0 5
  x -> z


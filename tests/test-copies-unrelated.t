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

Copy a file, then delete destination, then copy again. This does not create a new filelog entry.
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ echo x2 > x
  $ hg ci -m 'modify x'
  $ hg co -q 0
  $ hg cp x y
  $ hg ci -qm 'copy x to y'
  $ hg rm y
  $ hg ci -m 'remove y'
  $ hg cp -f x y
  $ hg ci -m 'copy x onto y (again)'
  $ hg l
  @  4 copy x onto y (again)
  |  y
  o  3 remove y
  |  y
  o  2 copy x to y
  |  y
  | o  1 modify x
  |/   x
  o  0 add x
     x
  $ hg debugp1copies -r 4
  x -> y
  $ hg debugpathcopies 0 4
  x -> y
  $ hg graft -r 1
  grafting 1:* "modify x" (glob)
  merging y and x to y
  $ hg co -qC 1
  $ hg graft -r 4
  grafting 4:* "copy x onto y (again)" (glob)
  merging x and y to y

Copy x to y, then remove y, then add back y. With copy metadata in the
changeset, this could easily end up reporting y as copied from x (if we don't
unmark it as a copy when it's removed). Despite x and y not being related, we
want grafts to propagate across the rename.
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ echo x2 > x
  $ hg ci -m 'modify x'
  $ hg co -q 0
  $ hg mv x y
  $ hg ci -qm 'rename x to y'
  $ hg rm y
  $ hg ci -qm 'remove y'
  $ echo x > y
  $ hg ci -Aqm 'add back y'
  $ hg l
  @  4 add back y
  |  y
  o  3 remove y
  |  y
  o  2 rename x to y
  |  x y
  | o  1 modify x
  |/   x
  o  0 add x
     x
  $ hg debugpathcopies 0 4
BROKEN: This should succeed and merge the changes from x into y
  $ hg graft -r 1
  grafting 1:* "modify x" (glob)
  file 'x' was deleted in local [local] but was modified in other [graft].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

Add x, remove it, then add it back, then rename x to y. Similar to the case
above, but here the break in history is before the rename.
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ echo x2 > x
  $ hg ci -m 'modify x'
  $ hg co -q 0
  $ hg rm x
  $ hg ci -qm 'remove x'
  $ echo x > x
  $ hg ci -Aqm 'add x again'
  $ hg mv x y
  $ hg ci -m 'rename x to y'
  $ hg l
  @  4 rename x to y
  |  x y
  o  3 add x again
  |  x
  o  2 remove x
  |  x
  | o  1 modify x
  |/   x
  o  0 add x
     x
  $ hg debugpathcopies 0 4
  x -> y
  $ hg graft -r 1
  grafting 1:* "modify x" (glob)
  merging y and x to y
  $ hg co -qC 1
  $ hg graft -r 4
  grafting 4:* "rename x to y" (glob)
  merging x and y to y

Add x, modify it, remove it, then add it back, then rename x to y. Similar to
the case above, but here the re-added file's nodeid is different from before
the break.

  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ echo x2 > x
  $ hg ci -m 'modify x'
  $ echo x3 > x
  $ hg ci -qm 'modify x again'
  $ hg co -q 1
  $ hg rm x
  $ hg ci -qm 'remove x'
# Same content to avoid conflicts
  $ hg revert -r 1 x
  $ hg ci -Aqm 'add x again'
  $ hg mv x y
  $ hg ci -m 'rename x to y'
  $ hg l
  @  5 rename x to y
  |  x y
  o  4 add x again
  |  x
  o  3 remove x
  |  x
  | o  2 modify x again
  |/   x
  o  1 modify x
  |  x
  o  0 add x
     x
  $ hg debugpathcopies 0 5
  x -> y (no-filelog !)
#if no-filelog
  $ hg graft -r 2
  grafting 2:* "modify x again" (glob)
  merging y and x to y
#else
BROKEN: This should succeed and merge the changes from x into y
  $ hg graft -r 2
  grafting 2:* "modify x again" (glob)
  file 'x' was deleted in local [local] but was modified in other [graft].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]
#endif
  $ hg co -qC 2
BROKEN: This should succeed and merge the changes from x into y
  $ hg graft -r 5
  grafting 5:* "rename x to y"* (glob)
  file 'x' was deleted in other [graft] but was modified in local [local].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

Add x, remove it, then add it back, rename x to y from the first commit.
Similar to the case above, but here the break in history is parallel to the
rename.
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg rm x
  $ hg ci -qm 'remove x'
  $ echo x > x
  $ hg ci -Aqm 'add x again'
  $ echo x2 > x
  $ hg ci -m 'modify x'
  $ hg co -q 0
  $ hg mv x y
  $ hg ci -qm 'rename x to y'
  $ hg l
  @  4 rename x to y
  |  x y
  | o  3 modify x
  | |  x
  | o  2 add x again
  | |  x
  | o  1 remove x
  |/   x
  o  0 add x
     x
  $ hg debugpathcopies 2 4
  x -> y
  $ hg graft -r 3
  grafting 3:* "modify x" (glob)
  merging y and x to y
  $ hg co -qC 3
  $ hg graft -r 4
  grafting 4:* "rename x to y" (glob)
  merging x and y to y

Add x, remove it, then add it back, rename x to y from the first commit.
Similar to the case above, but here the re-added file's nodeid is different
from the base.
  $ newrepo
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ hg rm x
  $ hg ci -qm 'remove x'
  $ echo x2 > x
  $ hg ci -Aqm 'add x again with different content'
  $ hg co -q 0
  $ hg mv x y
  $ hg ci -qm 'rename x to y'
  $ hg l
  @  3 rename x to y
  |  x y
  | o  2 add x again with different content
  | |  x
  | o  1 remove x
  |/   x
  o  0 add x
     x
  $ hg debugpathcopies 2 3
  x -> y
BROKEN: This should merge the changes from x into y
  $ hg graft -r 2
  grafting 2:* "add x again with different content" (glob)
  $ hg co -qC 2
BROKEN: This should succeed and merge the changes from x into y
  $ hg graft -r 3
  grafting 3:* "rename x to y" (glob)
  file 'x' was deleted in other [graft] but was modified in local [local].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

Add x on two branches, then rename x to y on one side. Similar to the case
above, but here the break in history is via the base commit.
  $ newrepo
  $ echo a > a
  $ hg ci -Aqm 'base'
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ echo x2 > x
  $ hg ci -m 'modify x'
  $ hg co -q 0
  $ echo x > x
  $ hg ci -Aqm 'add x again'
  $ hg mv x y
  $ hg ci -qm 'rename x to y'
  $ hg l
  @  4 rename x to y
  |  x y
  o  3 add x again
  |  x
  | o  2 modify x
  | |  x
  | o  1 add x
  |/   x
  o  0 base
     a
  $ hg debugpathcopies 1 4
  x -> y
  $ hg graft -r 2
  grafting 2:* "modify x" (glob)
  merging y and x to y
  $ hg co -qC 2
  $ hg graft -r 4
  grafting 4:* "rename x to y"* (glob)
  merging x and y to y

Add x on two branches, with same content but different history, then rename x
to y on one side. Similar to the case above, here the file's nodeid is
different between the branches.
  $ newrepo
  $ echo a > a
  $ hg ci -Aqm 'base'
  $ echo x > x
  $ hg ci -Aqm 'add x'
  $ echo x2 > x
  $ hg ci -m 'modify x'
  $ hg co -q 0
  $ touch x
  $ hg ci -Aqm 'add empty x'
# Same content to avoid conflicts
  $ hg revert -r 1 x
  $ hg ci -m 'modify x to match commit 1'
  $ hg mv x y
  $ hg ci -qm 'rename x to y'
  $ hg l
  @  5 rename x to y
  |  x y
  o  4 modify x to match commit 1
  |  x
  o  3 add empty x
  |  x
  | o  2 modify x
  | |  x
  | o  1 add x
  |/   x
  o  0 base
     a
  $ hg debugpathcopies 1 5
  x -> y (no-filelog !)
#if no-filelog
  $ hg graft -r 2
  grafting 2:* "modify x" (glob)
  merging y and x to y
#else
BROKEN: This should succeed and merge the changes from x into y
  $ hg graft -r 2
  grafting 2:* "modify x" (glob)
  file 'x' was deleted in local [local] but was modified in other [graft].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]
#endif
  $ hg co -qC 2
BROKEN: This should succeed and merge the changes from x into y
  $ hg graft -r 5
  grafting 5:* "rename x to y"* (glob)
  file 'x' was deleted in other [graft] but was modified in local [local].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

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
  $ hg graft -r 1
  grafting 1:* "copy x to y" (glob)

Copies involving a merge of multiple roots.

  $ newrepo
  $ echo a > a
  $ hg ci -Aqm 'add a'
  $ echo a >> a
  $ hg ci -Aqm 'update a'
  $ echo a >> a
  $ hg ci -Aqm 'update a'

  $ hg up null
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo b > a
  $ hg ci -Aqm 'add a'
  $ hg mv a b
  $ hg ci -Aqm 'move a to b'
  $ echo b >> b
  $ hg ci -Aqm 'update b'
  $ hg merge 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m "merge with other branch"
  $ echo a >> a
  $ echo a >> a
  $ echo b >> b
  $ hg ci -Aqm 'update a and b'
  $ hg l
  @  7 update a and b
  |  a b
  o    6 merge with other branch
  |\
  | o  5 update b
  | |  b
  | o  4 move a to b
  | |  a b
  | o  3 add a
  |    a
  | o  2 update a
  | |  a
  | o  1 update a
  |/   a
  o  0 add a
     a
  $ hg cat a -r 7
  a
  a
  a
  $ hg cat a -r 2
  a
  a
  a
  $ hg cat a -r 0
  a
  $ hg debugpathcopies 7 2
  $ hg debugpathcopies 2 7
  $ hg merge 2
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)


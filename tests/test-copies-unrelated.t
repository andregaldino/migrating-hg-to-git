#testcases filelog compatibility changeset

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
  $ hg debugp1copies -r 3
  x -> y
  $ hg debugpathcopies 0 3
  x -> y

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
  $ hg debugp1copies -r 3
  $ hg debugpathcopies 0 3

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

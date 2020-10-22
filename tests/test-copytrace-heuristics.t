Test for the heuristic copytracing algorithm
============================================

  $ cat >> $TESTTMP/copytrace.sh << '__EOF__'
  > initclient() {
  > cat >> $1/.hg/hgrc <<EOF
  > [experimental]
  > copytrace = heuristics
  > copytrace.sourcecommitlimit = -1
  > EOF
  > }
  > __EOF__
  $ . "$TESTTMP/copytrace.sh"

  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > rebase=
  > [alias]
  > l = log -G -T 'rev: {rev}\ndesc: {desc}\n'
  > pl = log -G -T 'rev: {rev}, phase: {phase}\ndesc: {desc}\n'
  > EOF

NOTE: calling initclient() set copytrace.sourcecommitlimit=-1 as we want to
prevent the full copytrace algorithm to run and test the heuristic algorithm
without complexing the test cases with public and draft commits.

Check filename heuristics (same dirname and same basename)
----------------------------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ mkdir dir
  $ echo a > dir/file.txt
  $ hg addremove
  adding a
  adding dir/file.txt
  $ hg ci -m initial
  $ hg mv a b
  $ hg mv -q dir dir2
  $ hg ci -m 'mv a b, mv dir/ dir2/'
  $ hg up -q 0
  $ echo b > a
  $ echo b > dir/file.txt
  $ hg ci -qm 'mod a, mod dir/file.txt'

  $ hg l
  @  rev: 2
  |  desc: mod a, mod dir/file.txt
  | o  rev: 1
  |/   desc: mv a b, mv dir/ dir2/
  o  rev: 0
     desc: initial

  $ hg rebase -s . -d 1
  rebasing 2:557f403c0afd tip "mod a, mod dir/file.txt"
  merging b and a to b
  merging dir2/file.txt and dir/file.txt to dir2/file.txt
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/557f403c0afd-9926eeff-rebase.hg
  $ cd ..
  $ rm -rf repo

Make sure filename heuristics do not when they are not related
--------------------------------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo 'somecontent' > a
  $ hg add a
  $ hg ci -m initial
  $ hg rm a
  $ echo 'completelydifferentcontext' > b
  $ hg add b
  $ hg ci -m 'rm a, add b'
  $ hg up -q 0
  $ printf 'somecontent\nmoarcontent' > a
  $ hg ci -qm 'mode a'

  $ hg l
  @  rev: 2
  |  desc: mode a
  | o  rev: 1
  |/   desc: rm a, add b
  o  rev: 0
     desc: initial

  $ hg rebase -s . -d 1
  rebasing 2:d526312210b9 tip "mode a"
  file 'a' was deleted in local [dest] but was modified in other [source].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ cd ..
  $ rm -rf repo

Test when lca didn't modified the file that was moved
-----------------------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo 'somecontent' > a
  $ hg add a
  $ hg ci -m initial
  $ echo c > c
  $ hg add c
  $ hg ci -m randomcommit
  $ hg mv a b
  $ hg ci -m 'mv a b'
  $ hg up -q 1
  $ echo b > a
  $ hg ci -qm 'mod a'

  $ hg pl
  @  rev: 3, phase: draft
  |  desc: mod a
  | o  rev: 2, phase: draft
  |/   desc: mv a b
  o  rev: 1, phase: draft
  |  desc: randomcommit
  o  rev: 0, phase: draft
     desc: initial

  $ hg rebase -s . -d 2
  rebasing 3:9d5cf99c3d9f tip "mod a"
  merging b and a to b
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/9d5cf99c3d9f-f02358cc-rebase.hg
  $ cd ..
  $ rm -rf repo

Rebase "backwards"
------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo 'somecontent' > a
  $ hg add a
  $ hg ci -m initial
  $ echo c > c
  $ hg add c
  $ hg ci -m randomcommit
  $ hg mv a b
  $ hg ci -m 'mv a b'
  $ hg up -q 2
  $ echo b > b
  $ hg ci -qm 'mod b'

  $ hg l
  @  rev: 3
  |  desc: mod b
  o  rev: 2
  |  desc: mv a b
  o  rev: 1
  |  desc: randomcommit
  o  rev: 0
     desc: initial

  $ hg rebase -s . -d 0
  rebasing 3:fbe97126b396 tip "mod b"
  merging a and b to a
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/fbe97126b396-cf5452a1-rebase.hg
  $ cd ..
  $ rm -rf repo

Check a few potential move candidates
-------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ mkdir dir
  $ echo a > dir/a
  $ hg add dir/a
  $ hg ci -qm initial
  $ hg mv dir/a dir/b
  $ hg ci -qm 'mv dir/a dir/b'
  $ mkdir dir2
  $ echo b > dir2/a
  $ hg add dir2/a
  $ hg ci -qm 'create dir2/a'
  $ hg up -q 0
  $ echo b > dir/a
  $ hg ci -qm 'mod dir/a'

  $ hg l
  @  rev: 3
  |  desc: mod dir/a
  | o  rev: 2
  | |  desc: create dir2/a
  | o  rev: 1
  |/   desc: mv dir/a dir/b
  o  rev: 0
     desc: initial

  $ hg rebase -s . -d 2
  rebasing 3:6b2f4cece40f tip "mod dir/a"
  merging dir/b and dir/a to dir/b
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/6b2f4cece40f-503efe60-rebase.hg
  $ cd ..
  $ rm -rf repo

Test the copytrace.movecandidateslimit with many move candidates
----------------------------------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ hg mv a foo
  $ echo a > b
  $ echo a > c
  $ echo a > d
  $ echo a > e
  $ echo a > f
  $ echo a > g
  $ hg add b
  $ hg add c
  $ hg add d
  $ hg add e
  $ hg add f
  $ hg add g
  $ hg ci -m 'mv a foo, add many files'
  $ hg up -q ".^"
  $ echo b > a
  $ hg ci -m 'mod a'
  created new head

  $ hg l
  @  rev: 2
  |  desc: mod a
  | o  rev: 1
  |/   desc: mv a foo, add many files
  o  rev: 0
     desc: initial

With small limit

  $ hg rebase -s 2 -d 1 --config experimental.copytrace.movecandidateslimit=0
  rebasing 2:ef716627c70b tip "mod a"
  skipping copytracing for 'a', more candidates than the limit: 7
  file 'a' was deleted in local [dest] but was modified in other [source].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg rebase --abort
  rebase aborted

With default limit which is 100

  $ hg rebase -s 2 -d 1
  rebasing 2:ef716627c70b tip "mod a"
  merging foo and a to foo
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/ef716627c70b-24681561-rebase.hg

  $ cd ..
  $ rm -rf repo

Move file in one branch and delete it in another
-----------------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ hg mv a b
  $ hg ci -m 'mv a b'
  $ hg up -q ".^"
  $ hg rm a
  $ hg ci -m 'del a'
  created new head

  $ hg pl
  @  rev: 2, phase: draft
  |  desc: del a
  | o  rev: 1, phase: draft
  |/   desc: mv a b
  o  rev: 0, phase: draft
     desc: initial

  $ hg rebase -s 1 -d 2
  rebasing 1:472e38d57782 "mv a b"
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/472e38d57782-17d50e29-rebase.hg
  $ hg up -q c492ed3c7e35dcd1dc938053b8adf56e2cfbd062
  $ ls -A
  .hg
  b
  $ cd ..
  $ rm -rf repo

Move a directory in draft branch
--------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ mkdir dir
  $ echo a > dir/a
  $ hg add dir/a
  $ hg ci -qm initial
  $ echo b > dir/a
  $ hg ci -qm 'mod dir/a'
  $ hg up -q ".^"
  $ hg mv -q dir/ dir2
  $ hg ci -qm 'mv dir/ dir2/'

  $ hg l
  @  rev: 2
  |  desc: mv dir/ dir2/
  | o  rev: 1
  |/   desc: mod dir/a
  o  rev: 0
     desc: initial

  $ hg rebase -s . -d 1
  rebasing 2:a33d80b6e352 tip "mv dir/ dir2/"
  merging dir/a and dir2/a to dir2/a
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/a33d80b6e352-fecb9ada-rebase.hg
  $ cd ..
  $ rm -rf server
  $ rm -rf repo

Move file twice and rebase mod on top of moves
----------------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ hg mv a b
  $ hg ci -m 'mv a b'
  $ hg mv b c
  $ hg ci -m 'mv b c'
  $ hg up -q 0
  $ echo c > a
  $ hg ci -m 'mod a'
  created new head

  $ hg l
  @  rev: 3
  |  desc: mod a
  | o  rev: 2
  | |  desc: mv b c
  | o  rev: 1
  |/   desc: mv a b
  o  rev: 0
     desc: initial
  $ hg rebase -s . -d 2
  rebasing 3:d41316942216 tip "mod a"
  merging c and a to c
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/d41316942216-2b5949bc-rebase.hg

  $ cd ..
  $ rm -rf repo

Move file twice and rebase moves on top of mods
-----------------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ hg mv a b
  $ hg ci -m 'mv a b'
  $ hg mv b c
  $ hg ci -m 'mv b c'
  $ hg up -q 0
  $ echo c > a
  $ hg ci -m 'mod a'
  created new head
  $ hg l
  @  rev: 3
  |  desc: mod a
  | o  rev: 2
  | |  desc: mv b c
  | o  rev: 1
  |/   desc: mv a b
  o  rev: 0
     desc: initial
  $ hg rebase -s 1 -d .
  rebasing 1:472e38d57782 "mv a b"
  merging a and b to b
  rebasing 2:d3efd280421d "mv b c"
  merging b and c to c
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/472e38d57782-ab8d3c58-rebase.hg

  $ cd ..
  $ rm -rf repo

Move one file and add another file in the same folder in one branch, modify file in another branch
--------------------------------------------------------------------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ hg mv a b
  $ hg ci -m 'mv a b'
  $ echo c > c
  $ hg add c
  $ hg ci -m 'add c'
  $ hg up -q 0
  $ echo b > a
  $ hg ci -m 'mod a'
  created new head

  $ hg l
  @  rev: 3
  |  desc: mod a
  | o  rev: 2
  | |  desc: add c
  | o  rev: 1
  |/   desc: mv a b
  o  rev: 0
     desc: initial

  $ hg rebase -s . -d 2
  rebasing 3:ef716627c70b tip "mod a"
  merging b and a to b
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/ef716627c70b-24681561-rebase.hg
  $ ls -A
  .hg
  b
  c
  $ cat b
  b
  $ rm -rf repo

Merge test
----------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ echo b > a
  $ hg ci -m 'modify a'
  $ hg up -q 0
  $ hg mv a b
  $ hg ci -m 'mv a b'
  created new head
  $ hg up -q 2

  $ hg l
  @  rev: 2
  |  desc: mv a b
  | o  rev: 1
  |/   desc: modify a
  o  rev: 0
     desc: initial

  $ hg merge 1
  merging b and a to b
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m merge
  $ ls -A
  .hg
  b
  $ cd ..
  $ rm -rf repo

Copy and move file
------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ hg cp a c
  $ hg mv a b
  $ hg ci -m 'cp a c, mv a b'
  $ hg up -q 0
  $ echo b > a
  $ hg ci -m 'mod a'
  created new head

  $ hg l
  @  rev: 2
  |  desc: mod a
  | o  rev: 1
  |/   desc: cp a c, mv a b
  o  rev: 0
     desc: initial

  $ hg rebase -s . -d 1
  rebasing 2:ef716627c70b tip "mod a"
  merging b and a to b
  merging c and a to c
  saved backup bundle to $TESTTMP/repo/repo/.hg/strip-backup/ef716627c70b-24681561-rebase.hg
  $ ls -A
  .hg
  b
  c
  $ cat b
  b
  $ cat c
  b
  $ cd ..
  $ rm -rf repo

Do a merge commit with many consequent moves in one branch
----------------------------------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ echo b > a
  $ hg ci -qm 'mod a'
  $ hg up -q ".^"
  $ hg mv a b
  $ hg ci -qm 'mv a b'
  $ hg mv b c
  $ hg ci -qm 'mv b c'
  $ hg up -q 1
  $ hg l
  o  rev: 3
  |  desc: mv b c
  o  rev: 2
  |  desc: mv a b
  | @  rev: 1
  |/   desc: mod a
  o  rev: 0
     desc: initial

  $ hg merge 3
  merging a and c to c
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -qm 'merge'
  $ hg pl
  @    rev: 4, phase: draft
  |\   desc: merge
  | o  rev: 3, phase: draft
  | |  desc: mv b c
  | o  rev: 2, phase: draft
  | |  desc: mv a b
  o |  rev: 1, phase: draft
  |/   desc: mod a
  o  rev: 0, phase: draft
     desc: initial
  $ ls -A
  .hg
  c
  $ cd ..
  $ rm -rf repo

Test shelve/unshelve
-------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ echo b > a
  $ hg shelve
  shelved as default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg mv a b
  $ hg ci -m 'mv a b'

  $ hg l
  @  rev: 1
  |  desc: mv a b
  o  rev: 0
     desc: initial
  $ hg unshelve
  unshelving change 'default'
  rebasing shelved changes
  merging b and a to b
  $ ls -A
  .hg
  b
  $ cat b
  b
  $ cd ..
  $ rm -rf repo

Test full copytrace ability on draft branch
-------------------------------------------

File directory and base name changed in same move
  $ hg init repo
  $ initclient repo
  $ mkdir repo/dir1
  $ cd repo/dir1
  $ echo a > a
  $ hg add a
  $ hg ci -qm initial
  $ cd ..
  $ hg mv -q dir1 dir2
  $ hg mv dir2/a dir2/b
  $ hg ci -qm 'mv a b; mv dir1 dir2'
  $ hg up -q '.^'
  $ cd dir1
  $ echo b >> a
  $ cd ..
  $ hg ci -qm 'mod a'

  $ hg pl
  @  rev: 2, phase: draft
  |  desc: mod a
  | o  rev: 1, phase: draft
  |/   desc: mv a b; mv dir1 dir2
  o  rev: 0, phase: draft
     desc: initial

  $ hg rebase -s . -d 1 --config experimental.copytrace.sourcecommitlimit=100
  rebasing 2:6207d2d318e7 tip "mod a"
  merging dir2/b and dir1/a to dir2/b
  saved backup bundle to $TESTTMP/repo/repo/.hg/strip-backup/6207d2d318e7-1c9779ad-rebase.hg
  $ cat dir2/b
  a
  b
  $ cd ..
  $ rm -rf repo

Move directory in one merge parent, while adding file to original directory
in other merge parent. File moved on rebase.

  $ hg init repo
  $ initclient repo
  $ mkdir repo/dir1
  $ cd repo/dir1
  $ echo dummy > dummy
  $ hg add dummy
  $ cd ..
  $ hg ci -qm initial
  $ cd dir1
  $ echo a > a
  $ hg add a
  $ cd ..
  $ hg ci -qm 'hg add dir1/a'
  $ hg up -q '.^'
  $ hg mv -q dir1 dir2
  $ hg ci -qm 'mv dir1 dir2'

  $ hg pl
  @  rev: 2, phase: draft
  |  desc: mv dir1 dir2
  | o  rev: 1, phase: draft
  |/   desc: hg add dir1/a
  o  rev: 0, phase: draft
     desc: initial

  $ hg rebase -s . -d 1 --config experimental.copytrace.sourcecommitlimit=100
  rebasing 2:e8919e7df8d0 tip "mv dir1 dir2"
  saved backup bundle to $TESTTMP/repo/repo/.hg/strip-backup/e8919e7df8d0-f62fab62-rebase.hg
  $ ls dir2
  a
  dummy
  $ rm -rf repo

Testing the sourcecommitlimit config
-----------------------------------

  $ hg init repo
  $ initclient repo
  $ cd repo
  $ echo a > a
  $ hg ci -Aqm "added a"
  $ echo "more things" >> a
  $ hg ci -qm "added more things to a"
  $ hg up 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo b > b
  $ hg ci -Aqm "added b"
  $ mkdir foo
  $ hg mv a foo/bar
  $ hg ci -m "Moved a to foo/bar"
  $ hg pl
  @  rev: 3, phase: draft
  |  desc: Moved a to foo/bar
  o  rev: 2, phase: draft
  |  desc: added b
  | o  rev: 1, phase: draft
  |/   desc: added more things to a
  o  rev: 0, phase: draft
     desc: added a

When the sourcecommitlimit is small and we have more drafts, we use heuristics only

  $ hg rebase -s 1 -d .
  rebasing 1:8b6e13696c38 "added more things to a"
  file 'a' was deleted in local [dest] but was modified in other [source].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

But when we have "sourcecommitlimit > (no. of drafts from base to c1)", we do
fullcopytracing

  $ hg rebase --abort
  rebase aborted
  $ hg rebase -s 1 -d . --config experimental.copytrace.sourcecommitlimit=100
  rebasing 1:8b6e13696c38 "added more things to a"
  merging foo/bar and a to foo/bar
  saved backup bundle to $TESTTMP/repo/repo/repo/.hg/strip-backup/8b6e13696c38-fc14ac83-rebase.hg
  $ cd ..
  $ rm -rf repo

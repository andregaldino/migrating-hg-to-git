#require symlink execbit
  $ cat << EOF >> $HGRCPATH
  > [phases]
  > publish=False
  > [extensions]
  > amend=
  > rebase=
  > debugdrawdag=$TESTDIR/drawdag.py
  > strip=
  > [rebase]
  > experimental.inmemory=1
  > [diff]
  > git=1
  > [alias]
  > tglog = log -G --template "{rev}: {node|short} '{desc}'\n"
  > EOF

Rebase a simple DAG:
  $ hg init repo1
  $ cd repo1
  $ hg debugdrawdag <<'EOS'
  > c b
  > |/
  > d
  > |
  > a
  > EOS
  $ hg up -C a
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg tglog
  o  3: 814f6bd05178 'c'
  |
  | o  2: db0e82a16a62 'b'
  |/
  o  1: 02952614a83d 'd'
  |
  @  0: b173517d0057 'a'
  
  $ hg cat -r 3 c
  c (no-eol)
  $ hg cat -r 2 b
  b (no-eol)
  $ hg rebase --debug -r b -d c | grep rebasing
  rebasing in-memory
  rebasing 2:db0e82a16a62 "b" (b)
  $ hg tglog
  o  3: ca58782ad1e4 'b'
  |
  o  2: 814f6bd05178 'c'
  |
  o  1: 02952614a83d 'd'
  |
  @  0: b173517d0057 'a'
  
  $ hg cat -r 3 b
  b (no-eol)
  $ hg cat -r 2 c
  c (no-eol)
  $ cd ..

Case 2:
  $ hg init repo2
  $ cd repo2
  $ hg debugdrawdag <<'EOS'
  > c b
  > |/
  > d
  > |
  > a
  > EOS

Add a symlink and executable file:
  $ hg up -C c
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ ln -s somefile e
  $ echo f > f
  $ chmod +x f
  $ hg add e f
  $ hg amend -q
  $ hg up -Cq a

Write files to the working copy, and ensure they're still there after the rebase
  $ echo "abc" > a
  $ ln -s def b
  $ echo "ghi" > c
  $ echo "jkl" > d
  $ echo "mno" > e
  $ hg tglog
  o  3: f56b71190a8f 'c'
  |
  | o  2: db0e82a16a62 'b'
  |/
  o  1: 02952614a83d 'd'
  |
  @  0: b173517d0057 'a'
  
  $ hg cat -r 3 c
  c (no-eol)
  $ hg cat -r 2 b
  b (no-eol)
  $ hg cat -r 3 e
  somefile (no-eol)
  $ hg rebase --debug -s b -d a | grep rebasing
  rebasing in-memory
  rebasing 2:db0e82a16a62 "b" (b)
  $ hg tglog
  o  3: fc055c3b4d33 'b'
  |
  | o  2: f56b71190a8f 'c'
  | |
  | o  1: 02952614a83d 'd'
  |/
  @  0: b173517d0057 'a'
  
  $ hg cat -r 2 c
  c (no-eol)
  $ hg cat -r 3 b
  b (no-eol)
  $ hg rebase --debug -s 1 -d 3 | grep rebasing
  rebasing in-memory
  rebasing 1:02952614a83d "d" (d)
  rebasing 2:f56b71190a8f "c"
  $ hg tglog
  o  3: 753feb6fd12a 'c'
  |
  o  2: 09c044d2cb43 'd'
  |
  o  1: fc055c3b4d33 'b'
  |
  @  0: b173517d0057 'a'
  
Ensure working copy files are still there:
  $ cat a
  abc
  $ readlink.py b
  b -> def
  $ cat e
  mno

Ensure symlink and executable files were rebased properly:
  $ hg up -Cq 3
  $ readlink.py e
  e -> somefile
  $ ls -l f | cut -c -10
  -rwxr-xr-x

Rebase the working copy parent
  $ hg up -C 3
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg rebase -r 3 -d 0 --debug | grep rebasing
  rebasing in-memory
  rebasing 3:753feb6fd12a "c" (tip)
  $ hg tglog
  @  3: 844a7de3e617 'c'
  |
  | o  2: 09c044d2cb43 'd'
  | |
  | o  1: fc055c3b4d33 'b'
  |/
  o  0: b173517d0057 'a'
  

Test reporting of path conflicts

  $ hg rm a
  $ mkdir a
  $ touch a/a
  $ hg ci -Am "a/a"
  adding a/a
  $ hg tglog
  @  4: daf7dfc139cb 'a/a'
  |
  o  3: 844a7de3e617 'c'
  |
  | o  2: 09c044d2cb43 'd'
  | |
  | o  1: fc055c3b4d33 'b'
  |/
  o  0: b173517d0057 'a'
  
  $ hg rebase -r . -d 2
  rebasing 4:daf7dfc139cb "a/a" (tip)
  saved backup bundle to $TESTTMP/repo2/.hg/strip-backup/daf7dfc139cb-fdbfcf4f-rebase.hg

  $ hg tglog
  @  4: c6ad37a4f250 'a/a'
  |
  | o  3: 844a7de3e617 'c'
  | |
  o |  2: 09c044d2cb43 'd'
  | |
  o |  1: fc055c3b4d33 'b'
  |/
  o  0: b173517d0057 'a'
  
  $ echo foo > foo
  $ hg ci -Aqm "added foo"
  $ hg up '.^'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo bar > bar
  $ hg ci -Aqm "added bar"
  $ hg rm a/a
  $ echo a > a
  $ hg ci -Aqm "added a back!"
  $ hg tglog
  @  7: 855e9797387e 'added a back!'
  |
  o  6: d14530e5e3e6 'added bar'
  |
  | o  5: 9b94b9373deb 'added foo'
  |/
  o  4: c6ad37a4f250 'a/a'
  |
  | o  3: 844a7de3e617 'c'
  | |
  o |  2: 09c044d2cb43 'd'
  | |
  o |  1: fc055c3b4d33 'b'
  |/
  o  0: b173517d0057 'a'
  
  $ hg rebase -r . -d 5
  rebasing 7:855e9797387e "added a back!" (tip)
  saved backup bundle to $TESTTMP/repo2/.hg/strip-backup/855e9797387e-81ee4c5d-rebase.hg

  $ hg tglog
  @  7: bb3f02be2688 'added a back!'
  |
  | o  6: d14530e5e3e6 'added bar'
  | |
  o |  5: 9b94b9373deb 'added foo'
  |/
  o  4: c6ad37a4f250 'a/a'
  |
  | o  3: 844a7de3e617 'c'
  | |
  o |  2: 09c044d2cb43 'd'
  | |
  o |  1: fc055c3b4d33 'b'
  |/
  o  0: b173517d0057 'a'
  
  $ mkdir -p c/subdir
  $ echo c > c/subdir/file.txt
  $ hg add c/subdir/file.txt
  $ hg ci -m 'c/subdir/file.txt'
  $ hg rebase -r . -d 3 -n
  starting dry-run rebase; repository will not be changed
  rebasing 8:e147e6e3c490 "c/subdir/file.txt" (tip)
  abort: error: 'c/subdir/file.txt' conflicts with file 'c' in 3.
  [255]
  $ hg rebase -r 3 -d . -n
  starting dry-run rebase; repository will not be changed
  rebasing 3:844a7de3e617 "c"
  abort: error: file 'c' cannot be written because  'c/' is a directory in e147e6e3c490 (containing 1 entries: c/subdir/file.txt)
  [255]

  $ cd ..

Test path auditing (issue5818)

  $ mkdir lib_
  $ ln -s lib_ lib
  $ hg init repo
  $ cd repo
  $ mkdir -p ".$TESTTMP/lib"
  $ touch ".$TESTTMP/lib/a"
  $ hg add ".$TESTTMP/lib/a"
  $ hg ci -m 'a'

  $ touch ".$TESTTMP/lib/b"
  $ hg add ".$TESTTMP/lib/b"
  $ hg ci -m 'b'

  $ hg up -q '.^'
  $ touch ".$TESTTMP/lib/c"
  $ hg add ".$TESTTMP/lib/c"
  $ hg ci -m 'c'
  created new head
  $ hg rebase -s 1 -d .
  rebasing 1:* "b" (glob)
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/*-rebase.hg (glob)
  $ cd ..

Test dry-run rebasing

  $ hg init repo3
  $ cd repo3
  $ echo a>a
  $ hg ci -Aqma
  $ echo b>b
  $ hg ci -Aqmb
  $ echo c>c
  $ hg ci -Aqmc
  $ echo d>d
  $ hg ci -Aqmd
  $ echo e>e
  $ hg ci -Aqme

  $ hg up 1 -q
  $ echo f>f
  $ hg ci -Amf
  adding f
  created new head
  $ echo g>g
  $ hg ci -Aqmg
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  @  6:baf10c5166d4 test
  |  g
  |
  o  5:6343ca3eff20 test
  |  f
  |
  | o  4:e860deea161a test
  | |  e
  | |
  | o  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  |/   c
  |
  o  1:d2ae7f538514 test
  |  b
  |
  o  0:cb9a9f314b8b test
     a
  
Make sure it throws error while passing --continue or --abort with --dry-run
  $ hg rebase -s 2 -d 6 -n --continue
  abort: cannot specify both --dry-run and --continue
  [255]
  $ hg rebase -s 2 -d 6 -n --abort
  abort: cannot specify both --dry-run and --abort
  [255]

Check dryrun gives correct results when there is no conflict in rebasing
  $ hg rebase -s 2 -d 6 -n
  starting dry-run rebase; repository will not be changed
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  rebasing 4:e860deea161a "e"
  dry-run rebase completed successfully; run without -n/--dry-run to perform this rebase

  $ hg diff
  $ hg status

  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  @  6:baf10c5166d4 test
  |  g
  |
  o  5:6343ca3eff20 test
  |  f
  |
  | o  4:e860deea161a test
  | |  e
  | |
  | o  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  |/   c
  |
  o  1:d2ae7f538514 test
  |  b
  |
  o  0:cb9a9f314b8b test
     a
  
Check dryrun working with --collapse when there is no conflict
  $ hg rebase -s 2 -d 6 -n --collapse
  starting dry-run rebase; repository will not be changed
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  rebasing 4:e860deea161a "e"
  dry-run rebase completed successfully; run without -n/--dry-run to perform this rebase

Check dryrun gives correct results when there is conflict in rebasing
Make a conflict:
  $ hg up 6 -q
  $ echo conflict>e
  $ hg ci -Aqm "conflict with e"
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  @  7:d2c195b28050 test
  |  conflict with e
  |
  o  6:baf10c5166d4 test
  |  g
  |
  o  5:6343ca3eff20 test
  |  f
  |
  | o  4:e860deea161a test
  | |  e
  | |
  | o  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  |/   c
  |
  o  1:d2ae7f538514 test
  |  b
  |
  o  0:cb9a9f314b8b test
     a
  
  $ hg rebase -s 2 -d 7 -n
  starting dry-run rebase; repository will not be changed
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  rebasing 4:e860deea161a "e"
  merging e
  transaction abort!
  rollback completed
  hit a merge conflict
  [1]
  $ hg diff
  $ hg status
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  @  7:d2c195b28050 test
  |  conflict with e
  |
  o  6:baf10c5166d4 test
  |  g
  |
  o  5:6343ca3eff20 test
  |  f
  |
  | o  4:e860deea161a test
  | |  e
  | |
  | o  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  |/   c
  |
  o  1:d2ae7f538514 test
  |  b
  |
  o  0:cb9a9f314b8b test
     a
  
Check dryrun working with --collapse when there is conflicts
  $ hg rebase -s 2 -d 7 -n --collapse
  starting dry-run rebase; repository will not be changed
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  rebasing 4:e860deea161a "e"
  merging e
  hit a merge conflict
  [1]

In-memory rebase that fails due to merge conflicts

  $ hg rebase -s 2 -d 7
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  rebasing 4:e860deea161a "e"
  merging e
  transaction abort!
  rollback completed
  hit merge conflicts; re-running rebase without in-memory merge
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  rebasing 4:e860deea161a "e"
  merging e
  warning: conflicts while merging e! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see hg resolve, then hg rebase --continue)
  [1]
  $ hg rebase --abort
  saved backup bundle to $TESTTMP/repo3/.hg/strip-backup/c1e524d4287c-f91f82e1-backup.hg
  rebase aborted

Retrying without in-memory merge won't lose working copy changes
  $ cd ..
  $ hg clone repo3 repo3-dirty -q
  $ cd repo3-dirty
  $ echo dirty > a
  $ hg rebase -s 2 -d 7
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  rebasing 4:e860deea161a "e"
  merging e
  transaction abort!
  rollback completed
  hit merge conflicts; re-running rebase without in-memory merge
  abort: uncommitted changes
  [255]
  $ cat a
  dirty

Retrying without in-memory merge won't lose merge state
  $ cd ..
  $ hg clone repo3 repo3-merge-state -q
  $ cd repo3-merge-state
  $ hg merge 4
  merging e
  warning: conflicts while merging e! (edit, then use 'hg resolve --mark')
  2 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ hg resolve -l
  U e
  $ hg rebase -s 2 -d 7
  rebasing 2:177f92b77385 "c"
  abort: outstanding merge conflicts
  [255]
  $ hg resolve -l
  U e

==========================
Test for --confirm option|
==========================
  $ cd ..
  $ hg clone repo3 repo4 -q
  $ cd repo4
  $ hg strip 7 -q
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  @  6:baf10c5166d4 test
  |  g
  |
  o  5:6343ca3eff20 test
  |  f
  |
  | o  4:e860deea161a test
  | |  e
  | |
  | o  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  |/   c
  |
  o  1:d2ae7f538514 test
  |  b
  |
  o  0:cb9a9f314b8b test
     a
  
Check it gives error when both --dryrun and --confirm is used:
  $ hg rebase -s 2 -d . --confirm --dry-run
  abort: cannot specify both --confirm and --dry-run
  [255]
  $ hg rebase -s 2 -d . --confirm --abort
  abort: cannot specify both --confirm and --abort
  [255]
  $ hg rebase -s 2 -d . --confirm --continue
  abort: cannot specify both --confirm and --continue
  [255]

Test --confirm option when there are no conflicts:
  $ hg rebase -s 2 -d . --keep --config ui.interactive=True --confirm << EOF
  > n
  > EOF
  starting in-memory rebase
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  rebasing 4:e860deea161a "e"
  rebase completed successfully
  apply changes (yn)? n
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  @  6:baf10c5166d4 test
  |  g
  |
  o  5:6343ca3eff20 test
  |  f
  |
  | o  4:e860deea161a test
  | |  e
  | |
  | o  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  |/   c
  |
  o  1:d2ae7f538514 test
  |  b
  |
  o  0:cb9a9f314b8b test
     a
  
  $ hg rebase -s 2 -d . --keep --config ui.interactive=True --confirm << EOF
  > y
  > EOF
  starting in-memory rebase
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  rebasing 4:e860deea161a "e"
  rebase completed successfully
  apply changes (yn)? y
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  o  9:9fd28f55f6dc test
  |  e
  |
  o  8:12cbf031f469 test
  |  d
  |
  o  7:c83b1da5b1ae test
  |  c
  |
  @  6:baf10c5166d4 test
  |  g
  |
  o  5:6343ca3eff20 test
  |  f
  |
  | o  4:e860deea161a test
  | |  e
  | |
  | o  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  |/   c
  |
  o  1:d2ae7f538514 test
  |  b
  |
  o  0:cb9a9f314b8b test
     a
  
Test --confirm option when there is a conflict
  $ hg up tip -q
  $ echo ee>e
  $ hg ci --amend -m "conflict with e" -q
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  @  9:906d72f66a59 test
  |  conflict with e
  |
  o  8:12cbf031f469 test
  |  d
  |
  o  7:c83b1da5b1ae test
  |  c
  |
  o  6:baf10c5166d4 test
  |  g
  |
  o  5:6343ca3eff20 test
  |  f
  |
  | o  4:e860deea161a test
  | |  e
  | |
  | o  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  |/   c
  |
  o  1:d2ae7f538514 test
  |  b
  |
  o  0:cb9a9f314b8b test
     a
  
  $ hg rebase -s 4 -d . --keep --confirm
  starting in-memory rebase
  rebasing 4:e860deea161a "e"
  merging e
  hit a merge conflict
  [1]
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  @  9:906d72f66a59 test
  |  conflict with e
  |
  o  8:12cbf031f469 test
  |  d
  |
  o  7:c83b1da5b1ae test
  |  c
  |
  o  6:baf10c5166d4 test
  |  g
  |
  o  5:6343ca3eff20 test
  |  f
  |
  | o  4:e860deea161a test
  | |  e
  | |
  | o  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  |/   c
  |
  o  1:d2ae7f538514 test
  |  b
  |
  o  0:cb9a9f314b8b test
     a
  
Test a metadata-only in-memory merge
  $ cd $TESTTMP
  $ hg init no_exception
  $ cd no_exception
# Produce the following graph:
#   o  'add +x to foo.txt'
#   | o  r1  (adds bar.txt, just for something to rebase to)
#   |/
#   o  r0   (adds foo.txt, no +x)
  $ echo hi > foo.txt
  $ hg ci -qAm r0
  $ echo hi > bar.txt
  $ hg ci -qAm r1
  $ hg co -qr ".^"
  $ chmod +x foo.txt
  $ hg ci -qAm 'add +x to foo.txt'
issue5960: this was raising an AttributeError exception
  $ hg rebase -r . -d 1
  rebasing 2:539b93e77479 "add +x to foo.txt" (tip)
  saved backup bundle to $TESTTMP/no_exception/.hg/strip-backup/*.hg (glob)
  $ hg diff -c tip
  diff --git a/foo.txt b/foo.txt
  old mode 100644
  new mode 100755

Test rebasing a commit with copy information, but no content changes

  $ cd ..
  $ hg clone -q repo1 merge-and-rename
  $ cd merge-and-rename
  $ cat << EOF >> .hg/hgrc
  > [experimental]
  > evolution.createmarkers=True
  > evolution.allowunstable=True
  > EOF
  $ hg co -q 1
  $ hg mv d e
  $ hg ci -qm 'rename d to e'
  $ hg co -q 3
  $ hg merge -q 4
  $ hg ci -m 'merge'
  $ hg co -q 2
  $ mv d e
  $ hg addremove -qs 0
  $ hg ci -qm 'untracked rename of d to e'
  $ hg debugobsolete -q `hg log -T '{node}' -r 4` `hg log -T '{node}' -r .`
  1 new orphan changesets
  $ hg tglog
  @  6: 676538af172d 'untracked rename of d to e'
  |
  | *    5: 71cb43376053 'merge'
  | |\
  | | x  4: 2c8b5dad7956 'rename d to e'
  | | |
  | o |  3: ca58782ad1e4 'b'
  |/ /
  o /  2: 814f6bd05178 'c'
  |/
  o  1: 02952614a83d 'd'
  |
  o  0: b173517d0057 'a'
  
  $ hg rebase -b 5 -d tip
  rebasing 3:ca58782ad1e4 "b"
  rebasing 5:71cb43376053 "merge"
  note: not rebasing 5:71cb43376053 "merge", its destination already has all its changes

  $ cd ..

Test rebasing a commit with copy information

  $ hg init rebase-rename
  $ cd rebase-rename
  $ echo a > a
  $ hg ci -Aqm 'add a'
  $ echo a2 > a
  $ hg ci -m 'modify a'
  $ hg co -q 0
  $ hg mv a b
  $ hg ci -qm 'rename a to b'
  $ hg rebase -d 1
  rebasing 2:b977edf6f839 "rename a to b" (tip)
  merging a and b to b
  saved backup bundle to $TESTTMP/rebase-rename/.hg/strip-backup/b977edf6f839-0864f570-rebase.hg
  $ hg st --copies --change .
  A b
    a
  R a
  $ cd ..

Test rebasing a commit with copy information, where the target is empty

  $ hg init rebase-rename-empty
  $ cd rebase-rename-empty
  $ echo a > a
  $ hg ci -Aqm 'add a'
  $ cat > a
  $ hg ci -m 'make a empty'
  $ hg co -q 0
  $ hg mv a b
  $ hg ci -qm 'rename a to b'
BROKEN: shouldn't crash
  $ hg rebase -d 1
  rebasing 2:b977edf6f839 "rename a to b" (tip)
  merging a and b to b
  abort: b@c71e275f666f: not found in manifest!
  [255]
  $ hg st --copies --change .
  A b
    a
  R a
  $ cd ..
Rebase across a copy with --collapse

  $ hg init rebase-rename-collapse
  $ cd rebase-rename-collapse
  $ echo a > a
  $ hg ci -Aqm 'add a'
  $ hg mv a b
  $ hg ci -m 'rename a to b'
  $ hg co -q 0
  $ echo a2 > a
  $ hg ci -qm 'modify a'
  $ hg rebase -r . -d 1 --collapse
  rebasing 2:41c4ea50d4cf "modify a" (tip)
  merging b and a to b
  saved backup bundle to $TESTTMP/rebase-rename-collapse/.hg/strip-backup/41c4ea50d4cf-b90b7994-rebase.hg
  $ cd ..

Test rebasing when the file we are merging in destination is empty

  $ hg init test
  $ cd test
  $ echo a > foo
  $ hg ci -Aqm 'added a to foo'

  $ rm foo
  $ touch foo
  $ hg di
  diff --git a/foo b/foo
  --- a/foo
  +++ b/foo
  @@ -1,1 +0,0 @@
  -a

  $ hg ci -m "make foo an empty file"

  $ hg up '.^'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo b > foo
  $ hg di
  diff --git a/foo b/foo
  --- a/foo
  +++ b/foo
  @@ -1,1 +1,1 @@
  -a
  +b
  $ hg ci -m "add b to foo"
  created new head

  $ hg rebase -r . -d 1 --config ui.merge=internal:merge3
  rebasing 2:fb62b706688e "add b to foo" (tip)
  merging foo
  hit merge conflicts; re-running rebase without in-memory merge
  rebasing 2:fb62b706688e "add b to foo" (tip)
  merging foo
  warning: conflicts while merging foo! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see hg resolve, then hg rebase --continue)
  [1]

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
  rebasing in memory
  rebasing 2:db0e82a16a62 b "b"
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
  rebasing in memory
  rebasing 2:db0e82a16a62 b "b"
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
  rebasing in memory
  rebasing 1:02952614a83d d "d"
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
  rebasing in memory
  rebasing 3:753feb6fd12a tip "c"
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
  rebasing 4:daf7dfc139cb tip "a/a"
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
  rebasing 7:855e9797387e tip "added a back!"
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
  rebasing 8:e147e6e3c490 tip "c/subdir/file.txt"
  abort: error: 'c/subdir/file.txt' conflicts with file 'c' in 3.
  [255]
FIXME: shouldn't need this, but when we hit path conflicts in dryrun mode, we
don't clean up rebasestate.
  $ hg rebase --abort
  rebase aborted
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
  abort: cannot specify both --continue and --dry-run
  [10]
  $ hg rebase -s 2 -d 6 -n --abort
  abort: cannot specify both --abort and --dry-run
  [10]

When nothing to rebase
  $ hg reb -r . -d '.^' -n
  starting dry-run rebase; repository will not be changed
  nothing to rebase
  [1]

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
  hit merge conflicts; rebasing that commit again in the working copy
  merging e
  warning: conflicts while merging e! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
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
  hit merge conflicts; rebasing that commit again in the working copy
  transaction abort!
  rollback completed
  abort: uncommitted changes
  [20]
  $ cat a
  dirty
  $ hg status -v
  M a

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
  abort: outstanding uncommitted merge
  (use 'hg commit' or 'hg merge --abort')
  [20]
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
  [10]
  $ hg rebase -s 2 -d . --confirm --abort
  abort: cannot specify both --abort and --confirm
  [10]
  $ hg rebase -s 2 -d . --confirm --continue
  abort: cannot specify both --continue and --confirm
  [10]

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
  rebasing 2:539b93e77479 tip "add +x to foo.txt"
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
  | *    5: 574d92ad16fc 'merge'
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
  rebasing 5:574d92ad16fc "merge"
  note: not rebasing 5:574d92ad16fc "merge", its destination already has all its changes

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
  rebasing 2:b977edf6f839 tip "rename a to b"
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
  $ hg rebase -d 1
  rebasing 2:b977edf6f839 tip "rename a to b"
  merging a and b to b
  saved backup bundle to $TESTTMP/rebase-rename-empty/.hg/strip-backup/b977edf6f839-0864f570-rebase.hg
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
  rebasing 2:41c4ea50d4cf tip "modify a"
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
  rebasing 2:fb62b706688e tip "add b to foo"
  merging foo
  hit merge conflicts; rebasing that commit again in the working copy
  merging foo
  warning: conflicts while merging foo! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ cd $TESTTMP

Test rebasing when we're in the middle of a rebase already
  $ hg init test_issue6214
  $ cd test_issue6214
  $ echo r0 > r0
  $ hg ci -qAm 'r0'
  $ echo hi > foo
  $ hg ci -qAm 'hi from foo'
  $ hg co -q '.^'
  $ echo bye > foo
  $ hg ci -qAm 'bye from foo'
  $ hg co -q '.^'
  $ echo unrelated > some_other_file
  $ hg ci -qAm 'some unrelated changes'
  $ hg log -G -T'{rev}: {desc}\n{files%"{file}\n"}'
  @  3: some unrelated changes
  |  some_other_file
  | o  2: bye from foo
  |/   foo
  | o  1: hi from foo
  |/   foo
  o  0: r0
     r0
  $ hg rebase -r 2 -d 1 -t:merge3
  rebasing 2:b4d249fbf8dd "bye from foo"
  merging foo
  hit merge conflicts; rebasing that commit again in the working copy
  merging foo
  warning: conflicts while merging foo! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg rebase -r 3 -d 1 -t:merge3
  abort: rebase in progress
  (use 'hg rebase --continue', 'hg rebase --abort', or 'hg rebase --stop')
  [20]
  $ hg resolve --list
  U foo
  $ hg resolve --all --re-merge -t:other
  (no more unresolved files)
  continue: hg rebase --continue
  $ hg rebase --continue
  rebasing 2:b4d249fbf8dd "bye from foo"
  saved backup bundle to $TESTTMP/test_issue6214/.hg/strip-backup/b4d249fbf8dd-299ec25c-rebase.hg
  $ hg log -G -T'{rev}: {desc}\n{files%"{file}\n"}'
  o  3: bye from foo
  |  foo
  | @  2: some unrelated changes
  | |  some_other_file
  o |  1: hi from foo
  |/   foo
  o  0: r0
     r0

  $ cd ..

Changesets that become empty should not be committed. Merges are not empty by
definition.

  $ hg init keep_merge
  $ cd keep_merge
  $ echo base > base; hg add base; hg ci -m base
  $ echo test > test; hg add test; hg ci -m a
  $ hg up 0 -q
  $ echo test > test; hg add test; hg ci -m b -q
  $ hg up 0 -q
  $ echo test > test; hg add test; hg ci -m c -q
  $ hg up 1 -q
  $ hg merge 2 -q
  $ hg ci -m merge
  $ hg up null -q
  $ hg tglog
  o    4: 59c8292117b1 'merge'
  |\
  | | o  3: 531f80391e4a 'c'
  | | |
  | o |  2: 0194f1db184a 'b'
  | |/
  o /  1: 6f252845ea45 'a'
  |/
  o  0: d20a80d4def3 'base'
  
  $ hg rebase -s 2 -d 3
  rebasing 2:0194f1db184a "b"
  note: not rebasing 2:0194f1db184a "b", its destination already has all its changes
  rebasing 4:59c8292117b1 tip "merge"
  saved backup bundle to $TESTTMP/keep_merge/.hg/strip-backup/0194f1db184a-aee31d03-rebase.hg
  $ hg tglog
  o    3: 506e2454484b 'merge'
  |\
  | o  2: 531f80391e4a 'c'
  | |
  o |  1: 6f252845ea45 'a'
  |/
  o  0: d20a80d4def3 'base'
  

Test that update_hash_refs works.
  $ hg co 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo update_hash_refs > update_hash_refs
  $ hg add update_hash_refs
  $ hg ci -m 'this will change hash'
  created new head
  $ echo changed >> update_hash_refs
  $ hg ci -m "this starts as the child of `hg log -r . -T'{node|short}'` but not 506e2454484b. Also, ffffffffffffffff"
  $ hg tglog
  @  5: a8b42cbbde83 'this starts as the child of 98789aa60148 but not 506e2454484b. Also, ffffffffffffffff'
  |
  o  4: 98789aa60148 'this will change hash'
  |
  | o    3: 506e2454484b 'merge'
  | |\
  +---o  2: 531f80391e4a 'c'
  | |
  | o  1: 6f252845ea45 'a'
  |/
  o  0: d20a80d4def3 'base'
  
  $ hg rebase -r '.^::' -d 3
  rebasing 4:98789aa60148 "this will change hash"
  rebasing 5:a8b42cbbde83 tip "this starts as the child of 98789aa60148 but not 506e2454484b. Also, ffffffffffffffff"
  saved backup bundle to $TESTTMP/keep_merge/.hg/strip-backup/98789aa60148-da3f4c2c-rebase.hg
  $ hg tglog
  @  5: 0fd2912e6cc1 'this starts as the child of c16c25696fe7 but not 506e2454484b. Also, ffffffffffffffff'
  |
  o  4: c16c25696fe7 'this will change hash'
  |
  o    3: 506e2454484b 'merge'
  |\
  | o  2: 531f80391e4a 'c'
  | |
  o |  1: 6f252845ea45 'a'
  |/
  o  0: d20a80d4def3 'base'
  

Add an explicit test for rewrite_hash_refs when the detected prefix is
ambiguous. Here's the super low-tech way I found this collision, if the hashing
scheme ever changes:
# hg init
# echo test0 > test
# hg ci -qAm 'test0' -u 'test' -d '0 0'
# i=1
# while [[ $(chg log -r . -T'{shortest(node, 6)}' | wc -c) -eq 6 ]]; do
#   chg co -r 0000000000
#   echo "test$i" > test
#   chg ci -qAm "test$i" -u test -d '0 0'
#   (( ++i ))
# done
  $ hg co -q 0000000000
  $ echo test5281 > test
  $ hg ci -qAm 'test5281'
  $ hg co -q 000000000
  $ echo test9912 > test
  $ hg ci -qAm 'test9912'
  $ hg co -q 4
  $ echo contents > some_file
  $ hg ci -qAm 'The previous two (parentless) commits had a hash prefix of b04363. Check that rewrite_hash_refs will not fail because of that.'
  $ hg rebase -r . -d 5
  rebasing 8:5c4cdabf5769 tip "The previous two (parentless) commits had a hash prefix of b04363. Check that rewrite_hash_refs will not fail because of that."
  saved backup bundle to $TESTTMP/keep_merge/.hg/strip-backup/5c4cdabf5769-335e1828-rebase.hg

  $ cd ..

Test (virtual) working directory without changes, created by merge conflict
resolution. There was a regression where the file was incorrectly detected as
changed although the file contents were the same as in the parent.

  $ hg init nofilechanges
  $ cd nofilechanges
  $ echo a > a; hg add a; hg ci -m a
  $ echo foo > test; hg add test; hg ci -m b
  $ hg up 0 -q
  $ echo bar > test; hg add test; hg ci -m c
  created new head
  $ hg rebase -d 2 -d 1 --tool :local
  rebasing 2:ca2749322ee5 tip "c"
  note: not rebasing 2:ca2749322ee5 tip "c", its destination already has all its changes
  saved backup bundle to $TESTTMP/nofilechanges/.hg/strip-backup/ca2749322ee5-6dc7e94b-rebase.hg

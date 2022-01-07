==========================
Test rebase with obsolete
==========================

Enable obsolete

  $ cat >> $HGRCPATH << EOF
  > [command-templates]
  > log= {rev}:{node|short} {desc|firstline}{if(obsolete,' ({obsfate})')}
  > [experimental]
  > evolution.createmarkers=True
  > evolution.allowunstable=True
  > [phases]
  > publish=False
  > [extensions]
  > rebase=
  > drawdag=$TESTDIR/drawdag.py
  > strip=
  > EOF

Test that bookmark is moved and working dir is updated when all changesets have
equivalents in destination
  $ hg init rbsrepo && cd rbsrepo
  $ echo "[experimental]" > .hg/hgrc
  $ echo "evolution=true" >> .hg/hgrc
  $ echo root > root && hg ci -Am root
  adding root
  $ echo a > a && hg ci -Am a
  adding a
  $ hg up 0
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo b > b && hg ci -Am b
  adding b
  created new head
  $ hg rebase -r 2 -d 1
  rebasing 2:1e9a3c00cbe9 tip "b"
  $ hg log -r .  # working dir is at rev 3 (successor of 2)
  3:be1832deae9a b (no-eol)
  $ hg book -r 2 mybook --hidden  # rev 2 has a bookmark on it now
  bookmarking hidden changeset 1e9a3c00cbe9
  (hidden revision '1e9a3c00cbe9' was rewritten as: be1832deae9a)
  $ hg up 2 && hg log -r .  # working dir is at rev 2 again
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  2:1e9a3c00cbe9 b (rewritten using rebase as 3:be1832deae9a) (no-eol)
  $ hg rebase -r 2 -d 3 --config experimental.evolution.track-operation=1
  note: not rebasing 2:1e9a3c00cbe9 mybook "b", already in destination as 3:be1832deae9a tip "b"
Check that working directory and bookmark was updated to rev 3 although rev 2
was skipped
  $ hg log -r .
  3:be1832deae9a b (no-eol)
  $ hg bookmarks
     mybook                    3:be1832deae9a
  $ hg debugobsolete --rev tip
  1e9a3c00cbe90d236ac05ef61efcc5e40b7412bc be1832deae9ac531caa7438b8dcf6055a122cd8e 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '4', 'operation': 'rebase', 'user': 'test'}

Obsoleted working parent and bookmark could be moved if an ancestor of working
parent gets moved:

  $ hg init $TESTTMP/ancestor-wd-move
  $ cd $TESTTMP/ancestor-wd-move
  $ hg debugdrawdag <<'EOS'
  >  E D1  # rebase: D1 -> D2
  >  | |
  >  | C
  > D2 |
  >  | B
  >  |/
  >  A
  > EOS
  $ hg update D1 -q
  $ hg bookmark book -i
  $ hg rebase -r B+D1 -d E
  rebasing 1:112478962961 B "B"
  note: not rebasing 5:15ecf15e0114 book D1 tip "D1", already in destination as 2:0807738e0be9 D2 "D2"
  1 new orphan changesets
  $ hg log -G -T '{desc} {bookmarks}'
  @  B book
  |
  | x  D1
  | |
  o |  E
  | |
  | *  C
  | |
  o |  D2
  | |
  | x  B
  |/
  o  A
  
Rebasing a merge with one of its parent having a hidden successor

  $ hg init $TESTTMP/merge-p1-hidden-successor
  $ cd $TESTTMP/merge-p1-hidden-successor

  $ hg debugdrawdag <<'EOS'
  >  E
  >  |
  > B3 B2 # amend: B1 -> B2 -> B3
  >  |/   # B2 is hidden
  >  |  D
  >  |  |\
  >  | B1 C
  >  |/
  >  A
  > EOS
  1 new orphan changesets

  $ eval `hg tags -T '{tag}={node}\n'`
  $ rm .hg/localtags

  $ hg rebase -r $D -d $E
  rebasing 5:9e62094e4d94 "D"

  $ hg log -G
  o    7:a699d059adcf D
  |\
  | o  6:ecc93090a95c E
  | |
  | o  4:0dc878468a23 B3
  | |
  o |  1:96cc3511f894 C
   /
  o  0:426bada5c675 A
  
For some reasons (--hidden, directaccess, etc.),
rebasestate may contain hidden hashes. "rebase --abort" should work regardless.

  $ hg init $TESTTMP/hidden-state1
  $ cd $TESTTMP/hidden-state1

  $ hg debugdrawdag <<'EOS'
  >    C
  >    |
  >  D B # B/D=B
  >  |/  
  >  A
  > EOS

  $ eval `hg tags -T '{tag}={node}\n'`
  $ rm .hg/localtags

  $ hg update -q $C
  $ hg rebase -s $B -d $D
  rebasing 1:2ec65233581b "B"
  merging D
  warning: conflicts while merging D! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg debugobsolete $B
  1 new obsolescence markers
  obsoleted 1 changesets
  1 new orphan changesets
  $ hg debugobsolete $C
  1 new obsolescence markers
  obsoleted 1 changesets
  $ cp -R . $TESTTMP/hidden-state2

  $ hg log -G
  @  2:b18e25de2cf5 D
  |
  | %  1:2ec65233581b B (pruned)
  |/
  o  0:426bada5c675 A
  
  $ hg summary
  parent: 2:b18e25de2cf5 tip
   D
  branch: default
  commit: 1 modified, 1 added, 1 unknown, 1 unresolved
  update: (current)
  phases: 3 draft
  rebase: 0 rebased, 2 remaining (rebase --continue)

  $ hg rebase --abort
  rebase aborted

Also test --continue for the above case

  $ cd $TESTTMP/hidden-state2
  $ hg resolve -m
  (no more unresolved files)
  continue: hg rebase --continue
  $ hg rebase --continue
  note: not rebasing 1:2ec65233581b "B", it has no successor
  note: not rebasing 3:7829726be4dc tip "C", it has no successor
  $ hg log -G
  @  2:b18e25de2cf5 D
  |
  o  0:426bada5c675 A
  
====================
Test --stop option |
====================
  $ cd ..
  $ hg init rbstop
  $ cd rbstop
  $ echo a>a
  $ hg ci -Aqma
  $ echo b>b
  $ hg ci -Aqmb
  $ echo c>c
  $ hg ci -Aqmc
  $ echo d>d
  $ hg ci -Aqmd
  $ hg up 0 -q
  $ echo f>f
  $ hg ci -Aqmf
  $ echo D>d
  $ hg ci -Aqm "conflict with d"
  $ hg up 3 -q
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  o  5:00bfc9898aeb test
  |  conflict with d
  |
  o  4:dafd40200f93 test
  |  f
  |
  | @  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  | |  c
  | |
  | o  1:d2ae7f538514 test
  |/   b
  |
  o  0:cb9a9f314b8b test
     a
  
  $ hg rebase -s 1 -d 5
  rebasing 1:d2ae7f538514 "b"
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  merging d
  warning: conflicts while merging d! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg rebase --stop
  1 new orphan changesets
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  o  7:7fffad344617 test
  |  c
  |
  o  6:b15528633407 test
  |  b
  |
  o  5:00bfc9898aeb test
  |  conflict with d
  |
  o  4:dafd40200f93 test
  |  f
  |
  | @  3:055a42cdd887 test
  | |  d
  | |
  | x  2:177f92b77385 test
  | |  c
  | |
  | x  1:d2ae7f538514 test
  |/   b
  |
  o  0:cb9a9f314b8b test
     a
  
Test it aborts if unstable csets is not allowed:
===============================================
  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > evolution.allowunstable=False
  > EOF

  $ hg strip 6 --no-backup -q
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  o  5:00bfc9898aeb test
  |  conflict with d
  |
  o  4:dafd40200f93 test
  |  f
  |
  | @  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  | |  c
  | |
  | o  1:d2ae7f538514 test
  |/   b
  |
  o  0:cb9a9f314b8b test
     a
  
  $ hg rebase -s 1 -d 5
  rebasing 1:d2ae7f538514 "b"
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  merging d
  warning: conflicts while merging d! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg rebase --stop
  abort: cannot remove original changesets with unrebased descendants
  (either enable obsmarkers to allow unstable revisions or use --keep to keep original changesets)
  [20]
  $ hg rebase --abort
  saved backup bundle to $TESTTMP/rbstop/.hg/strip-backup/b15528633407-6eb72b6f-backup.hg
  rebase aborted

Test --stop when --keep is passed:
==================================
  $ hg rebase -s 1 -d 5 --keep
  rebasing 1:d2ae7f538514 "b"
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  merging d
  warning: conflicts while merging d! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg rebase --stop
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  o  7:7fffad344617 test
  |  c
  |
  o  6:b15528633407 test
  |  b
  |
  o  5:00bfc9898aeb test
  |  conflict with d
  |
  o  4:dafd40200f93 test
  |  f
  |
  | @  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  | |  c
  | |
  | o  1:d2ae7f538514 test
  |/   b
  |
  o  0:cb9a9f314b8b test
     a
  
Test --stop aborts when --collapse was passed:
=============================================
  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > evolution.allowunstable=True
  > EOF

  $ hg strip 6
  saved backup bundle to $TESTTMP/rbstop/.hg/strip-backup/b15528633407-6eb72b6f-backup.hg
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  o  5:00bfc9898aeb test
  |  conflict with d
  |
  o  4:dafd40200f93 test
  |  f
  |
  | @  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  | |  c
  | |
  | o  1:d2ae7f538514 test
  |/   b
  |
  o  0:cb9a9f314b8b test
     a
  
  $ hg rebase -s 1 -d 5 --collapse -m "collapsed b c d"
  rebasing 1:d2ae7f538514 "b"
  rebasing 2:177f92b77385 "c"
  rebasing 3:055a42cdd887 "d"
  merging d
  warning: conflicts while merging d! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg rebase --stop
  abort: cannot stop in --collapse session
  [20]
  $ hg rebase --abort
  rebase aborted
  $ hg diff
  $ hg log -G --template "{rev}:{short(node)} {person(author)}\n{firstline(desc)} {topic}\n\n"
  o  5:00bfc9898aeb test
  |  conflict with d
  |
  o  4:dafd40200f93 test
  |  f
  |
  | @  3:055a42cdd887 test
  | |  d
  | |
  | o  2:177f92b77385 test
  | |  c
  | |
  | o  1:d2ae7f538514 test
  |/   b
  |
  o  0:cb9a9f314b8b test
     a
  
Test --stop raise errors with conflicting options:
=================================================
  $ hg rebase -s 3 -d 5
  rebasing 3:055a42cdd887 "d"
  merging d
  warning: conflicts while merging d! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg rebase --stop --dry-run
  abort: cannot specify both --stop and --dry-run
  [10]

  $ hg rebase -s 3 -d 5
  abort: rebase in progress
  (use 'hg rebase --continue', 'hg rebase --abort', or 'hg rebase --stop')
  [20]
  $ hg rebase --stop --continue
  abort: cannot specify both --stop and --continue
  [10]

Test --stop moves bookmarks of original revisions to new rebased nodes:
======================================================================
  $ cd ..
  $ hg init repo
  $ cd repo

  $ echo a > a
  $ hg ci -Am A
  adding a

  $ echo b > b
  $ hg ci -Am B
  adding b
  $ hg book X
  $ hg book Y

  $ echo c > c
  $ hg ci -Am C
  adding c
  $ hg book Z

  $ echo d > d
  $ hg ci -Am D
  adding d

  $ hg up 0 -q
  $ echo e > e
  $ hg ci -Am E
  adding e
  created new head

  $ echo doubt > d
  $ hg ci -Am "conflict with d"
  adding d

  $ hg log -GT "{rev}: {node|short} '{desc}' bookmarks: {bookmarks}\n"
  @  5: 39adf30bc1be 'conflict with d' bookmarks:
  |
  o  4: 9c1e55f411b6 'E' bookmarks:
  |
  | o  3: 67a385d4e6f2 'D' bookmarks: Z
  | |
  | o  2: 49cb3485fa0c 'C' bookmarks: Y
  | |
  | o  1: 6c81ed0049f8 'B' bookmarks: X
  |/
  o  0: 1994f17a630e 'A' bookmarks:
  
  $ hg rebase -s 1 -d 5
  rebasing 1:6c81ed0049f8 X "B"
  rebasing 2:49cb3485fa0c Y "C"
  rebasing 3:67a385d4e6f2 Z "D"
  merging d
  warning: conflicts while merging d! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg rebase --stop
  1 new orphan changesets
  $ hg log -GT "{rev}: {node|short} '{desc}' bookmarks: {bookmarks}\n"
  o  7: 9c86c650b686 'C' bookmarks: Y
  |
  o  6: 9b87b54e5fd8 'B' bookmarks: X
  |
  @  5: 39adf30bc1be 'conflict with d' bookmarks:
  |
  o  4: 9c1e55f411b6 'E' bookmarks:
  |
  | *  3: 67a385d4e6f2 'D' bookmarks: Z
  | |
  | x  2: 49cb3485fa0c 'C' bookmarks:
  | |
  | x  1: 6c81ed0049f8 'B' bookmarks:
  |/
  o  0: 1994f17a630e 'A' bookmarks:
  

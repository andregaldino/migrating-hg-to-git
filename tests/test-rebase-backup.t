  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > rebase=
  > EOF

==================================
Test backup-bundle config option |
==================================
Test with Pre-obsmarker rebase:
1) When config option is not set:
  $ hg init repo1
  $ cd repo1
  $ echo a>a
  $ hg ci -qAma
  $ echo b>b
  $ hg ci -qAmb
  $ echo c>c
  $ hg ci -qAmc
  $ hg up 0 -q
  $ echo d>d
  $ hg ci -qAmd
  $ echo e>e
  $ hg ci -qAme
  $ hg log -GT "{rev}: {firstline(desc)}\n"
  @  4: e
  |
  o  3: d
  |
  | o  2: c
  | |
  | o  1: b
  |/
  o  0: a
  
  $ hg rebase -s 1 -d .
  rebasing 1:d2ae7f538514 "b"
  rebasing 2:177f92b77385 "c"
  saved backup bundle to $TESTTMP/repo1/.hg/strip-backup/d2ae7f538514-c7ed7a78-rebase.hg
  $ hg log -GT "{rev}: {firstline(desc)}\n"
  o  4: c
  |
  o  3: b
  |
  @  2: e
  |
  o  1: d
  |
  o  0: a
  

2) When config option is set:
  $ cat << EOF >> $HGRCPATH
  > [rewrite]
  > backup-bundle = False
  > EOF

  $ echo f>f
  $ hg ci -Aqmf
  $ echo g>g
  $ hg ci -Aqmg
  $ hg log -GT "{rev}: {firstline(desc)}\n"
  @  6: g
  |
  o  5: f
  |
  | o  4: c
  | |
  | o  3: b
  |/
  o  2: e
  |
  o  1: d
  |
  o  0: a
  
  $ hg rebase -s 3 -d .
  rebasing 3:05bff2a95b12 "b"
  rebasing 4:1762bde4404d "c"

  $ hg log -GT "{rev}: {firstline(desc)}\n"
  o  6: c
  |
  o  5: b
  |
  @  4: g
  |
  o  3: f
  |
  o  2: e
  |
  o  1: d
  |
  o  0: a
  
Test when rebased revisions are stripped during abort:
======================================================

  $ echo conflict > c
  $ hg ci -Am "conflict with c"
  adding c
  created new head
  $ hg log -GT "{rev}: {firstline(desc)}\n"
  @  7: conflict with c
  |
  | o  6: c
  | |
  | o  5: b
  |/
  o  4: g
  |
  o  3: f
  |
  o  2: e
  |
  o  1: d
  |
  o  0: a
  
When backup-bundle = True:
  $ cat << EOF >> $HGRCPATH
  > [rewrite]
  > backup-bundle = True
  > EOF
  $ hg rebase -s 5 -d .
  rebasing 5:1f8148a544ee "b"
  rebasing 6:f8bc7d28e573 "c"
  merging c
  warning: conflicts while merging c! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg rebase --abort
  saved backup bundle to $TESTTMP/repo1/.hg/strip-backup/818c1a43c916-2b644d96-backup.hg
  rebase aborted

When backup-bundle = False:
  $ cat << EOF >> $HGRCPATH
  > [rewrite]
  > backup-bundle = False
  > EOF
  $ hg rebase -s 5 -d .
  rebasing 5:1f8148a544ee "b"
  rebasing 6:f8bc7d28e573 "c"
  merging c
  warning: conflicts while merging c! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]
  $ hg rebase --abort
  rebase aborted
  $ cd ..


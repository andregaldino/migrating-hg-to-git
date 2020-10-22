  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase=
  > 
  > [phases]
  > publish=False
  > 
  > [alias]
  > tglog = log -G --template "{rev}:{phase} '{desc}' {branches}\n"
  > EOF


  $ hg init a
  $ cd a

  $ echo A > A
  $ hg add A
  $ hg ci -m A

  $ echo 'B' > B
  $ hg add B
  $ hg ci -m B

  $ echo C >> A
  $ hg ci -m C

  $ hg up -q -C 0

  $ echo D >> A
  $ hg ci -m D
  created new head

  $ echo E > E
  $ hg add E
  $ hg ci -m E

  $ hg up -q -C 0

  $ hg branch 'notdefault'
  marked working directory as branch notdefault
  (branches are permanent and global, did you want a bookmark?)
  $ echo F >> A
  $ hg ci -m F

  $ cd ..


Rebasing B onto E - check keep: and phases

  $ hg clone -q -u . a a1
  $ cd a1
  $ hg phase --force --secret 2

  $ hg tglog
  @  5:draft 'F' notdefault
  |
  | o  4:draft 'E'
  | |
  | o  3:draft 'D'
  |/
  | o  2:secret 'C'
  | |
  | o  1:draft 'B'
  |/
  o  0:draft 'A'
  
  $ hg rebase -s 1 -d 4 --keep
  rebasing 1:27547f69f254 "B"
  rebasing 2:965c486023db "C"
  merging A
  warning: conflicts while merging A! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

Solve the conflict and go on:

  $ echo 'conflict solved' > A
  $ rm A.orig
  $ hg resolve -m A
  (no more unresolved files)
  continue: hg rebase --continue
  $ hg rebase --continue
  already rebased 1:27547f69f254 "B" as 45396c49d53b
  rebasing 2:965c486023db "C"

  $ hg tglog
  o  7:secret 'C'
  |
  o  6:draft 'B'
  |
  | @  5:draft 'F' notdefault
  | |
  o |  4:draft 'E'
  | |
  o |  3:draft 'D'
  |/
  | o  2:secret 'C'
  | |
  | o  1:draft 'B'
  |/
  o  0:draft 'A'
  
  $ cd ..


Rebase F onto E - check keepbranches:

  $ hg clone -q -u . a a2
  $ cd a2
  $ hg phase --force --secret 2

  $ hg tglog
  @  5:draft 'F' notdefault
  |
  | o  4:draft 'E'
  | |
  | o  3:draft 'D'
  |/
  | o  2:secret 'C'
  | |
  | o  1:draft 'B'
  |/
  o  0:draft 'A'
  
  $ hg rebase -s 5 -d 4 --keepbranches
  rebasing 5:01e6ebbd8272 tip "F"
  merging A
  warning: conflicts while merging A! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

Solve the conflict and go on:

  $ echo 'conflict solved' > A
  $ rm A.orig
  $ hg resolve -m A
  (no more unresolved files)
  continue: hg rebase --continue
  $ hg rebase --continue
  rebasing 5:01e6ebbd8272 tip "F"
  saved backup bundle to $TESTTMP/a2/.hg/strip-backup/01e6ebbd8272-6fd3a015-rebase.hg

  $ hg tglog
  @  5:draft 'F' notdefault
  |
  o  4:draft 'E'
  |
  o  3:draft 'D'
  |
  | o  2:secret 'C'
  | |
  | o  1:draft 'B'
  |/
  o  0:draft 'A'
  
  $ cat >> .hg/hgrc << EOF
  > [experimental]
  > evolution.createmarkers=True
  > EOF

When updating away from a dirty, obsolete wdir, don't complain that the old p1
is filtered and requires --hidden.

  $ echo conflict > A
  $ hg debugobsolete 071d07019675449d53b7e312c65bcf28adbbdb64 965c486023dbfdc9c32c52dc249a231882fd5c17
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg update -r 2 --config ui.merge=internal:merge --merge
  merging A
  warning: conflicts while merging A! (edit, then use 'hg resolve --mark')
  1 files updated, 0 files merged, 1 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges
  [1]
  $ hg resolve A
  merging A
  warning: conflicts while merging A! (edit, then use 'hg resolve --mark')
  [1]

An unresolved conflict will pin the obsolete revision

  $ hg log -G -Tcompact
  %  5[tip]   071d07019675   1970-01-01 00:00 +0000   test
  |    F
  |
  o  4   ae36e8e3dfd7   1970-01-01 00:00 +0000   test
  |    E
  |
  o  3:0   46b37eabc604   1970-01-01 00:00 +0000   test
  |    D
  |
  | @  2   965c486023db   1970-01-01 00:00 +0000   test
  | |    C
  | |
  | o  1   27547f69f254   1970-01-01 00:00 +0000   test
  |/     B
  |
  o  0   4a2df7238c3b   1970-01-01 00:00 +0000   test
       A
  

But resolving the conflicts will unpin it

  $ hg resolve -m A
  (no more unresolved files)
  $ hg log -G -Tcompact
  o  4[tip]   ae36e8e3dfd7   1970-01-01 00:00 +0000   test
  |    E
  |
  o  3:0   46b37eabc604   1970-01-01 00:00 +0000   test
  |    D
  |
  | @  2   965c486023db   1970-01-01 00:00 +0000   test
  | |    C
  | |
  | o  1   27547f69f254   1970-01-01 00:00 +0000   test
  |/     B
  |
  o  0   4a2df7238c3b   1970-01-01 00:00 +0000   test
       A
  
  $ hg up -C -q .

  $ cd ..

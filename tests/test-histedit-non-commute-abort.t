  $ . "$TESTDIR/histedit-helpers.sh"

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > histedit=
  > EOF

  $ initrepo ()
  > {
  >     hg init r
  >     cd r
  >     for x in a b c d e f ; do
  >         echo $x > $x
  >         hg add $x
  >         hg ci -m $x
  >     done
  >     echo a >> e
  >     hg ci -m 'does not commute with e'
  >     cd ..
  > }

  $ initrepo
  $ cd r

log before edit
  $ hg log --graph
  @  changeset:   6:bfa474341cc9
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     does not commute with e
  |
  o  changeset:   5:652413bf663e
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     f
  |
  o  changeset:   4:e860deea161a
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     e
  |
  o  changeset:   3:055a42cdd887
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     d
  |
  o  changeset:   2:177f92b77385
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     c
  |
  o  changeset:   1:d2ae7f538514
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     b
  |
  o  changeset:   0:cb9a9f314b8b
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     a
  

edit the history
  $ hg histedit 177f92b77385 --commands - 2>&1 <<EOF | fixbundle
  > pick 177f92b77385 c
  > pick 055a42cdd887 d
  > pick bfa474341cc9 does not commute with e
  > pick e860deea161a e
  > pick 652413bf663e f
  > EOF
  merging e
  warning: conflicts while merging e! (edit, then use 'hg resolve --mark')
  Fix up the change (pick e860deea161a)
  (hg histedit --continue to resume)

insert unsupported advisory merge record
  $ hg --config extensions.fakemergerecord=$TESTDIR/fakemergerecord.py fakemergerecord -x
  $ hg debugmergestate
  local (already edited): 8f7551c7e4a2f2efe0bc8c741baf7f227d65d758
  other (current change): e860deea161a2f77de56603b340ebbb4536308ae
  file: e (state "u")
    local path: e (hash 58e6b3a414a1e090dfc6029add0f3555ccba127f, flags "")
    ancestor path: e (node 0000000000000000000000000000000000000000)
    other path: e (node 6b67ccefd5ce6de77e7ead4f5292843a0255329f)
    extra: ancestorlinknode = 0000000000000000000000000000000000000000
    extra: merged = yes
  $ hg resolve -l
  U e

insert unsupported mandatory merge record
  $ hg --config extensions.fakemergerecord=$TESTDIR/fakemergerecord.py fakemergerecord -X
  $ hg debugmergestate
  abort: unsupported merge state records: X
  (see https://mercurial-scm.org/wiki/MergeStateRecords for more information)
  [255]
  $ hg resolve -l
  abort: unsupported merge state records: X
  (see https://mercurial-scm.org/wiki/MergeStateRecords for more information)
  [255]
  $ hg resolve -ma
  abort: unsupported merge state records: X
  (see https://mercurial-scm.org/wiki/MergeStateRecords for more information)
  [255]

abort the edit (should clear out merge state)
  $ hg histedit --abort 2>&1 | fixbundle
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugmergestate
  no merge state found

log after abort
  $ hg resolve -l
  $ hg log --graph
  @  changeset:   6:bfa474341cc9
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     does not commute with e
  |
  o  changeset:   5:652413bf663e
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     f
  |
  o  changeset:   4:e860deea161a
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     e
  |
  o  changeset:   3:055a42cdd887
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     d
  |
  o  changeset:   2:177f92b77385
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     c
  |
  o  changeset:   1:d2ae7f538514
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     b
  |
  o  changeset:   0:cb9a9f314b8b
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     a
  

Early tree conflict doesn't leave histedit in a wedged state. Note
that we don't specify --commands here: we catch the problem before we
even prompt the user for rules, sidestepping any dataloss issues.

  $ hg rm c
  $ hg ci -m 'remove c'
  $ echo collision > c

  $ hg histedit e860deea161a
  c: untracked file differs
  abort: untracked files in working directory conflict with files in 055a42cdd887
  [20]

We should have detected the collision early enough we're not in a
histedit state, and p1 is unchanged.

  $ hg log -r 'p1()' -T'{node}\n'
  1b0954ff00fccb15a37b679e4a35e9b01dfe685e
  $ hg status --config ui.tweakdefaults=yes
  ? c
  ? e.orig

  $ cd ..

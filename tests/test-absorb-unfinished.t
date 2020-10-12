  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > absorb=
  > EOF

Abort absorb if there is an unfinished operation.

  $ hg init abortunresolved
  $ cd abortunresolved

  $ echo "foo1" > foo.whole
  $ hg commit -Aqm "foo 1"

  $ hg update null
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo "foo2" > foo.whole
  $ hg commit -Aqm "foo 2"

  $ hg --config extensions.rebase= rebase -r 1 -d 0
  rebasing 1:c3b6dc0e177a tip "foo 2"
  merging foo.whole
  warning: conflicts while merging foo.whole! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg --config extensions.rebase= absorb
  abort: rebase in progress
  (use 'hg rebase --continue', 'hg rebase --abort', or 'hg rebase --stop')
  [20]


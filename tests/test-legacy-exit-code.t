Tests that the exit code is as expected when ui.detailed-exit-code is *not*
enabled.

  $ cat >> $HGRCPATH << EOF
  > [ui]
  > detailed-exit-code=no
  > EOF

  $ hg init
  $ echo a > a
Expect exit code 0 on success
  $ hg ci -Aqm initial

  $ hg co nonexistent
  abort: unknown revision 'nonexistent'
  [255]

  $ hg co 'none()'
  abort: empty revision set
  [255]

  $ hg co 'invalid('
  hg: parse error at 8: not a prefix: end
  (invalid(
           ^ here)
  [255]

  $ hg co 'invalid('
  hg: parse error at 8: not a prefix: end
  (invalid(
           ^ here)
  [255]

  $ hg continue
  abort: no operation in progress
  [255]

  $ hg st --config a=b
  abort: malformed --config option: 'a=b' (use --config section.name=value)
  [255]

  $ echo b > a
  $ hg ci -m second
  $ echo c > a
  $ hg ci -m third
  $ hg --config extensions.rebase= rebase -r . -d 0 -q
  warning: conflicts while merging a! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [1]

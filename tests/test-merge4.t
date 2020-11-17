  $ hg init
  $ echo This is file a1 > a
  $ hg add a
  $ hg commit -m "commit #0"
  $ echo This is file b1 > b
  $ hg add b
  $ hg commit -m "commit #1"
  $ hg update 0
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo This is file c1 > c
  $ hg add c
  $ hg commit -m "commit #2"
  created new head
  $ hg merge 1
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ rm b
  $ echo This is file c22 > c

Test hg behaves when committing with a missing file added by a merge

  $ hg commit -m "commit #3"
  abort: cannot commit merge with missing files
  [255]


Test conflict*() revsets

# Bad usage
  $ hg log -r 'conflictlocal(foo)'
  hg: parse error: conflictlocal takes no arguments
  [10]
  $ hg log -r 'conflictother(foo)'
  hg: parse error: conflictother takes no arguments
  [10]
  $ hg co -C .
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
# No merge parents when not merging
  $ hg log -r 'conflictlocal() + conflictother()'
# No merge parents when there is no conflict
  $ hg merge 1
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg log -r 'conflictlocal() + conflictother()'
  $ hg co -C .
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo conflict > b
  $ hg ci -Aqm 'conflicting change to b'
  $ hg merge 1
  merging b
  warning: conflicts while merging b! (edit, then use 'hg resolve --mark')
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
# Shows merge parents when there is a conflict
  $ hg log -r 'conflictlocal()' -T '{rev} {desc}\n'
  3 conflicting change to b
  $ hg log -r 'conflictother()' -T '{rev} {desc}\n'
  1 commit #1

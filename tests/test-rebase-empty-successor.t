  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > rebase=
  > [alias]
  > tglog = log -G -T "{rev} '{desc}'\n"
  > EOF

  $ hg init

  $ echo a > a; hg add a; hg ci -m a
  $ echo b > b; hg add b; hg ci -m b1
  $ hg up 0 -q
  $ echo b > b; hg add b; hg ci -m b2 -q

  $ hg tglog
  @  2 'b2'
  |
  | o  1 'b1'
  |/
  o  0 'a'
  

With rewrite.empty-successor=skip, b2 is skipped because it would become empty.

  $ hg rebase -s 2 -d 1 --config rewrite.empty-successor=skip --dry-run
  starting dry-run rebase; repository will not be changed
  rebasing 2:6e2aad5e0f3c tip "b2"
  note: not rebasing 2:6e2aad5e0f3c tip "b2", its destination already has all its changes
  dry-run rebase completed successfully; run without -n/--dry-run to perform this rebase

With rewrite.empty-successor=keep, b2 will be recreated although it became empty.

  $ hg rebase -s 2 -d 1 --config rewrite.empty-successor=keep
  rebasing 2:6e2aad5e0f3c tip "b2"
  note: created empty successor for 2:6e2aad5e0f3c tip "b2", its destination already has all its changes
  saved backup bundle to $TESTTMP/.hg/strip-backup/6e2aad5e0f3c-7d7c8801-rebase.hg

  $ hg tglog
  @  2 'b2'
  |
  o  1 'b1'
  |
  o  0 'a'
  

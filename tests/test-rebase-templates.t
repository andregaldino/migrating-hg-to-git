Testing templating for rebase command

Setup

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase=
  > [experimental]
  > evolution=createmarkers
  > EOF

  $ hg init repo
  $ cd repo
  $ for ch in a b c d; do echo foo > $ch; hg commit -Aqm "Added "$ch; done

  $ hg log -G -T "{rev}:{node|short} {desc}"
  @  3:62615734edd5 Added d
  |
  o  2:28ad74487de9 Added c
  |
  o  1:29becc82797a Added b
  |
  o  0:18d04c59bb5d Added a
  
Getting the JSON output for nodechanges

  $ hg rebase -s 2 -d 0 -q -Tjson
  [
   {
    "nodechanges": {"28ad74487de9599d00d81085be739c61fc340652": ["849767420fd5519cf0026232411a943ed03cc9fb"], "62615734edd52f06b6fb9c2beb429e4fe30d57b8": ["df21b32134ba85d86bca590cbe9b8b7cbc346c53"]}
   }
  ]

  $ hg log -G -T "{rev}:{node|short} {desc}"
  @  5:df21b32134ba Added d
  |
  o  4:849767420fd5 Added c
  |
  | o  1:29becc82797a Added b
  |/
  o  0:18d04c59bb5d Added a
  
  $ hg rebase -s 1 -d 5 -q -T "{nodechanges|json}"
  {"29becc82797a4bc11ec8880b58eaecd2ab3e7760": ["d9d6773efc831c274eace04bc13e8e6412517139"]} (no-eol)

  $ hg log -G -T "{rev}:{node|short} {desc}"
  o  6:d9d6773efc83 Added b
  |
  @  5:df21b32134ba Added d
  |
  o  4:849767420fd5 Added c
  |
  o  0:18d04c59bb5d Added a
  

  $ hg rebase -s 6 -d 4 -q -T "{nodechanges % '{oldnode}:{newnodes % ' {node} '}'}"
  d9d6773efc831c274eace04bc13e8e6412517139: f48cd65c6dc3d2acb55da54402a5b029546e546f  (no-eol)

  $ hg log -G -T "{rev}:{node|short} {desc}"
  o  7:f48cd65c6dc3 Added b
  |
  | @  5:df21b32134ba Added d
  |/
  o  4:849767420fd5 Added c
  |
  o  0:18d04c59bb5d Added a
  


  $ hg rebase -s 7 -d 5 -q --keep -T "{nodechanges % '{oldnode}:{newnodes % ' {node} '}'}"
  f48cd65c6dc3d2acb55da54402a5b029546e546f: 6f7dda91e55e728fb798f3e44dbecf0ebaa83267  (no-eol)

  $ hg log -G -T "{rev}:{node|short} {desc}"
  o  8:6f7dda91e55e Added b
  |
  | o  7:f48cd65c6dc3 Added b
  | |
  @ |  5:df21b32134ba Added d
  |/
  o  4:849767420fd5 Added c
  |
  o  0:18d04c59bb5d Added a
  

Respects command-templates.oneline-summary

  $ hg rebase -r 7 -d 8 -n --config command-templates.oneline-summary='rev: {rev}'
  starting dry-run rebase; repository will not be changed
  rebasing rev: 7
  note: not rebasing rev: 7, its destination already has all its changes
  dry-run rebase completed successfully; run without -n/--dry-run to perform this rebase


command-templates.oneline-summary.rebase overrides

  $ hg rebase -r 7 -d 8 -n \
  > --config command-templates.oneline-summary='global: {rev}' \
  > --config command-templates.oneline-summary.rebase='override: {rev}'
  starting dry-run rebase; repository will not be changed
  rebasing override: 7
  note: not rebasing override: 7, its destination already has all its changes
  dry-run rebase completed successfully; run without -n/--dry-run to perform this rebase


check namespaces and coloring (labels)

  $ hg tag -l -r 7 my-tag
  $ hg rebase -r 7 -d 8 -n
  starting dry-run rebase; repository will not be changed
  rebasing 7:f48cd65c6dc3 my-tag "Added b"
  note: not rebasing 7:f48cd65c6dc3 my-tag "Added b", its destination already has all its changes
  dry-run rebase completed successfully; run without -n/--dry-run to perform this rebase
  $ hg bookmark -r 7 my-bookmark
  $ hg rebase -r 7 -d 8 -n
  starting dry-run rebase; repository will not be changed
  rebasing 7:f48cd65c6dc3 my-bookmark my-tag "Added b"
  note: not rebasing 7:f48cd65c6dc3 my-bookmark my-tag "Added b", its destination already has all its changes
  dry-run rebase completed successfully; run without -n/--dry-run to perform this rebase
  $ hg rebase -r 7 -d 8 -n --color=debug
  [ ui.status|starting dry-run rebase; repository will not be changed]
  [ ui.status|rebasing [oneline-summary.changeset|7:f48cd65c6dc3] [oneline-summary.bookmarks|my-bookmark] [oneline-summary.tags|my-tag] "[oneline-summary.desc|Added b]"]
  [ ui.warning|note: not rebasing [oneline-summary.changeset|7:f48cd65c6dc3] [oneline-summary.bookmarks|my-bookmark] [oneline-summary.tags|my-tag] "[oneline-summary.desc|Added b]", its destination already has all its changes]
  [ ui.status|dry-run rebase completed successfully; run without -n/--dry-run to perform this rebase]

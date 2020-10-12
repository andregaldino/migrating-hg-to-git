Test histedit extension: Merge tools
====================================

Initialization
---------------

  $ . "$TESTDIR/histedit-helpers.sh"

  $ cat >> $HGRCPATH <<EOF
  > [alias]
  > logt = log --template '{rev}:{node|short} {desc|firstline}\n'
  > [extensions]
  > histedit=
  > mockmakedate = $TESTDIR/mockmakedate.py
  > EOF

Merge conflict
--------------

  $ hg init r
  $ cd r
  $ cat >> .hg/hgrc <<EOF
  > [command-templates]
  > pre-merge-tool-output='pre-merge message for {node}\n'
  > EOF

  $ echo foo > file
  $ hg add file
  $ hg ci -m "First" -d "1 0"
  $ echo bar > file
  $ hg ci -m "Second" -d "2 0"

  $ hg logt --graph
  @  1:2aa920f62fb9 Second
  |
  o  0:7181f42b8fca First
  

Invert the order of the commits, but fail the merge.
  $ hg histedit --config ui.merge=false --commands - 2>&1 <<EOF | fixbundle
  > pick 2aa920f62fb9 Second
  > pick 7181f42b8fca First
  > EOF
  merging file
  pre-merge message for b90fa2e91a6d11013945a5f684be45b84a8ca6ec
  merging file failed!
  Fix up the change (pick 7181f42b8fca)
  (hg histedit --continue to resume)

  $ hg histedit --abort | fixbundle
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

Invert the order of the commits, and pretend the merge succeeded.
  $ hg histedit --config ui.merge=true --commands - 2>&1 <<EOF | fixbundle
  > pick 2aa920f62fb9 Second
  > pick 7181f42b8fca First
  > EOF
  merging file
  pre-merge message for b90fa2e91a6d11013945a5f684be45b84a8ca6ec
  7181f42b8fca: skipping changeset (no changes)
  $ hg histedit --abort
  abort: no histedit in progress
  [20]
  $ cd ..

Test legacy config name

  $ hg init r2
  $ cd r2
  $ echo foo > file
  $ hg add file
  $ hg ci -m "First"
  $ echo bar > file
  $ hg ci -m "Second"
  $ echo conflict > file
  $ hg co -m 0 --config ui.merge=false \
  > --config ui.pre-merge-tool-output-template='legacy config: {node}\n'
  merging file
  legacy config: 889c9c4d58bd4ce74815efd04a01e0f2bf6765a7
  merging file failed!
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges
  [1]

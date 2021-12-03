test that a commit clears the merge state.

  $ hg init repo
  $ cd repo

  $ echo foo > file1
  $ echo foo > file2
  $ hg commit -Am 'add files'
  adding file1
  adding file2

  $ echo bar >> file1
  $ echo bar >> file2
  $ hg commit -Am 'append bar to files'

create a second head with conflicting edits

  $ hg up -C 0
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo baz >> file1
  $ echo baz >> file2
  $ hg commit -Am 'append baz to files'
  created new head

create a third head with no conflicting edits
  $ hg up -qC 0
  $ echo foo > file3
  $ hg commit -Am 'add non-conflicting file'
  adding file3
  created new head

failing merge

  $ hg up -qC 2
  $ hg merge --tool=internal:fail 1
  0 files updated, 0 files merged, 0 files removed, 2 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]

resolve -l should contain unresolved entries

  $ hg resolve -l
  U file1
  U file2

  $ hg resolve -l --no-status
  file1
  file2

resolving an unknown path should emit a warning, but not for -l

  $ hg resolve -m does-not-exist
  arguments do not match paths that need resolving
  $ hg resolve -l does-not-exist

tell users how they could have used resolve

  $ mkdir nested
  $ cd nested
  $ hg resolve -m file1
  arguments do not match paths that need resolving
  (try: hg resolve -m path:file1)
  $ hg resolve -m file1 filez
  arguments do not match paths that need resolving
  (try: hg resolve -m path:file1 path:filez)
  $ hg resolve -m path:file1 path:filez
  $ hg resolve -l
  R file1
  U file2
  $ hg resolve -l --config ui.relative-paths=yes
  R ../file1
  U ../file2
  $ hg resolve --re-merge filez file2
  arguments do not match paths that need resolving
  (try: hg resolve --re-merge path:filez path:file2)
  $ hg resolve -m filez file2
  arguments do not match paths that need resolving
  (try: hg resolve -m path:filez path:file2)
  $ hg resolve -m path:filez path:file2
  (no more unresolved files)
  $ hg resolve -l
  R file1
  R file2

cleanup
  $ hg resolve -u
  $ cd ..
  $ rmdir nested

resolve the failure

  $ echo resolved > file1
  $ hg resolve -m file1

resolve -l should show resolved file as resolved

  $ hg resolve -l
  R file1
  U file2

  $ hg resolve -l -Tjson
  [
   {
    "mergestatus": "R",
    "path": "file1"
   },
   {
    "mergestatus": "U",
    "path": "file2"
   }
  ]

  $ hg resolve -l -T '{path} {mergestatus} {status} {p1rev} {p2rev}\n'
  file1 R M 2 1
  file2 U M 2 1

resolve -m without paths should mark all resolved

  $ hg resolve -m
  (no more unresolved files)
  $ hg commit -m 'resolved'

resolve -l should be empty after commit

  $ hg resolve -l

  $ hg resolve -l -Tjson
  [
  ]

resolve --all should abort when no merge in progress

  $ hg resolve --all
  abort: resolve command not applicable when not merging
  [20]

resolve -m should abort when no merge in progress

  $ hg resolve -m
  abort: resolve command not applicable when not merging
  [20]

can not update or merge when there are unresolved conflicts

  $ hg up -qC 0
  $ echo quux >> file1
  $ hg up 1
  merging file1
  warning: conflicts while merging file1! (edit, then use 'hg resolve --mark')
  1 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges
  [1]
  $ hg up 0
  abort: outstanding merge conflicts
  (use 'hg resolve' to resolve)
  [20]
  $ hg merge 2
  abort: outstanding merge conflicts
  (use 'hg resolve' to resolve)
  [20]
  $ hg merge --force 2
  abort: outstanding merge conflicts
  (use 'hg resolve' to resolve)
  [20]

set up conflict-free merge

  $ hg up -qC 3
  $ hg merge 1
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

resolve --all should do nothing in merge without conflicts
  $ hg resolve --all
  (no more unresolved files)

resolve -m should do nothing in merge without conflicts

  $ hg resolve -m
  (no more unresolved files)

get back to conflicting state

  $ hg up -qC 2
  $ hg merge --tool=internal:fail 1
  0 files updated, 0 files merged, 0 files removed, 2 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]

resolve without arguments should suggest --all
  $ hg resolve
  abort: no files or directories specified
  (use --all to re-merge all unresolved files)
  [10]

resolve --all should re-merge all unresolved files
  $ hg resolve --all
  merging file1
  warning: conflicts while merging file1! (edit, then use 'hg resolve --mark')
  merging file2
  warning: conflicts while merging file2! (edit, then use 'hg resolve --mark')
  [1]
  $ cat file1.orig
  foo
  baz
  $ cat file2.orig
  foo
  baz

.orig files should exists where specified
  $ hg resolve --all --verbose --config 'ui.origbackuppath=.hg/origbackups'
  merging file1
  creating directory: $TESTTMP/repo/.hg/origbackups
  warning: conflicts while merging file1! (edit, then use 'hg resolve --mark')
  merging file2
  warning: conflicts while merging file2! (edit, then use 'hg resolve --mark')
  [1]
  $ ls .hg/origbackups
  file1
  file2
  $ grep '<<<' file1 > /dev/null
  $ grep '<<<' file2 > /dev/null

resolve <file> should re-merge file
  $ echo resolved > file1
  $ hg resolve -q file1
  warning: conflicts while merging file1! (edit, then use 'hg resolve --mark')
  [1]
  $ grep '<<<' file1 > /dev/null

test .orig behavior with resolve

  $ hg resolve -q file1 --tool "sh -c 'f --dump \"$TESTTMP/repo/file1.orig\"'"
  $TESTTMP/repo/file1.orig:
  >>>
  foo
  baz
  <<<

resolve <file> should do nothing if 'file' was marked resolved
  $ echo resolved > file1
  $ hg resolve -m file1
  $ hg resolve -q file1
  $ cat file1
  resolved

insert unsupported advisory merge record

  $ hg --config extensions.fakemergerecord=$TESTDIR/fakemergerecord.py fakemergerecord -x
  $ hg debugmergestate
  local (working copy): 57653b9f834a4493f7240b0681efcb9ae7cab745
  other (merge rev): dc77451844e37f03f5c559e3b8529b2b48d381d1
  file: file1 (state "r")
    local path: file1 (hash 60b27f004e454aca81b0480209cce5081ec52390, flags "")
    ancestor path: file1 (node 2ed2a3912a0b24502043eae84ee4b279c18b90dd)
    other path: file1 (node 6f4310b00b9a147241b071a60c28a650827fb03d)
    extra: ancestorlinknode = 99726c03216e233810a2564cbc0adfe395007eac
    extra: merged = yes
  file: file2 (state "u")
    local path: file2 (hash cb99b709a1978bd205ab9dfd4c5aaa1fc91c7523, flags "")
    ancestor path: file2 (node 2ed2a3912a0b24502043eae84ee4b279c18b90dd)
    other path: file2 (node 6f4310b00b9a147241b071a60c28a650827fb03d)
    extra: ancestorlinknode = 99726c03216e233810a2564cbc0adfe395007eac
    extra: merged = yes
  $ hg resolve -l
  R file1
  U file2

test json output

  $ hg debugmergestate -T json
  [
   {
    "commits": [{"label": "working copy", "name": "local", "node": "57653b9f834a4493f7240b0681efcb9ae7cab745"}, {"label": "merge rev", "name": "other", "node": "dc77451844e37f03f5c559e3b8529b2b48d381d1"}],
    "extras": [],
    "files": [{"ancestor_node": "2ed2a3912a0b24502043eae84ee4b279c18b90dd", "ancestor_path": "file1", "extras": [{"key": "ancestorlinknode", "value": "99726c03216e233810a2564cbc0adfe395007eac"}, {"key": "merged", "value": "yes"}], "local_flags": "", "local_key": "60b27f004e454aca81b0480209cce5081ec52390", "local_path": "file1", "other_node": "6f4310b00b9a147241b071a60c28a650827fb03d", "other_path": "file1", "path": "file1", "state": "r"}, {"ancestor_node": "2ed2a3912a0b24502043eae84ee4b279c18b90dd", "ancestor_path": "file2", "extras": [{"key": "ancestorlinknode", "value": "99726c03216e233810a2564cbc0adfe395007eac"}, {"key": "merged", "value": "yes"}], "local_flags": "", "local_key": "cb99b709a1978bd205ab9dfd4c5aaa1fc91c7523", "local_path": "file2", "other_node": "6f4310b00b9a147241b071a60c28a650827fb03d", "other_path": "file2", "path": "file2", "state": "u"}]
   }
  ]


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
  $ hg summary
  warning: merge state has unsupported record types: X
  parent: 2:57653b9f834a 
   append baz to files
  parent: 1:dc77451844e3 
   append bar to files
  branch: default
  commit: 2 modified, 2 unknown (merge)
  update: 2 new changesets (update)
  phases: 5 draft

update --clean shouldn't abort on unsupported records

  $ hg up -qC 1
  $ hg debugmergestate
  no merge state found

test crashed merge with empty mergestate

  $ mkdir .hg/merge
  $ touch .hg/merge/state

resolve -l should be empty

  $ hg resolve -l

resolve -m can be configured to look for remaining conflict markers
  $ hg up -qC 2
  $ hg merge -q --tool=internal:merge 1
  warning: conflicts while merging file1! (edit, then use 'hg resolve --mark')
  warning: conflicts while merging file2! (edit, then use 'hg resolve --mark')
  [1]
  $ hg resolve -l
  U file1
  U file2
  $ echo 'remove markers' > file1
  $ hg --config commands.resolve.mark-check=abort resolve -m
  warning: the following files still have conflict markers:
    file2
  abort: conflict markers detected
  (use --all to mark anyway)
  [20]
  $ hg resolve -l
  U file1
  U file2
Try with --all from the hint
  $ hg --config commands.resolve.mark-check=abort resolve -m --all
  warning: the following files still have conflict markers:
    file2
  (no more unresolved files)
  $ hg resolve -l
  R file1
  R file2
Test with :mergediff conflict markers
  $ hg resolve --unmark
  $ hg resolve --re-merge -t :mergediff file2
  merging file2
  warning: conflicts while merging file2! (edit, then use 'hg resolve --mark')
  [1]
  $ hg resolve -l
  U file1
  U file2
  $ hg --config commands.resolve.mark-check=abort resolve -m
  warning: the following files still have conflict markers:
    file2
  abort: conflict markers detected
  (use --all to mark anyway)
  [20]
  $ hg resolve -l
  U file1
  U file2
Test option value 'warn'
  $ hg resolve --unmark
  $ hg resolve -l
  U file1
  U file2
  $ hg --config commands.resolve.mark-check=warn resolve -m
  warning: the following files still have conflict markers:
    file2
  (no more unresolved files)
  $ hg resolve -l
  R file1
  R file2
If the file is already marked as resolved, we don't warn about it
  $ hg resolve --unmark file1
  $ hg resolve -l
  U file1
  R file2
  $ hg --config commands.resolve.mark-check=warn resolve -m
  (no more unresolved files)
  $ hg resolve -l
  R file1
  R file2
If the user passes an invalid value, we treat it as 'none'.
  $ hg resolve --unmark
  $ hg resolve -l
  U file1
  U file2
  $ hg --config commands.resolve.mark-check=nope resolve -m
  (no more unresolved files)
  $ hg resolve -l
  R file1
  R file2
Test explicitly setting the option to 'none'
  $ hg resolve --unmark
  $ hg resolve -l
  U file1
  U file2
  $ hg --config commands.resolve.mark-check=none resolve -m
  (no more unresolved files)
  $ hg resolve -l
  R file1
  R file2
Test with marking an explicit file as resolved, this should not abort (since
there's no --force flag, we have no way of combining --all with a filename)
  $ hg resolve --unmark
  $ hg resolve -l
  U file1
  U file2
(This downgrades to a warning since an explicit file was specified).
  $ hg --config commands.resolve.mark-check=abort resolve -m file2
  warning: the following files still have conflict markers:
    file2
  $ hg resolve -l
  U file1
  R file2
Testing the --re-merge flag
  $ hg resolve --unmark file1
  $ hg resolve -l
  U file1
  R file2
  $ hg resolve --mark --re-merge
  abort: too many actions specified
  [10]
  $ hg resolve --re-merge --all
  merging file1
  warning: conflicts while merging file1! (edit, then use 'hg resolve --mark')
  [1]
Explicit re-merge
  $ hg resolve --unmark file1
  $ hg resolve --config commands.resolve.explicit-re-merge=1 --all
  abort: no action specified
  (use --mark, --unmark, --list or --re-merge)
  [10]
  $ hg resolve --config commands.resolve.explicit-re-merge=1 --re-merge --all
  merging file1
  warning: conflicts while merging file1! (edit, then use 'hg resolve --mark')
  [1]

  $ cd ..

======================================================
Test 'hg resolve' confirm config option functionality |
======================================================
  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > rebase=
  > EOF

  $ hg init repo2
  $ cd repo2

  $ echo boss > boss
  $ hg ci -Am "add boss"
  adding boss

  $ for emp in emp1 emp2 emp3; do echo work > $emp; done;
  $ hg ci -Aqm "added emp1 emp2 emp3"

  $ hg up 0
  0 files updated, 0 files merged, 3 files removed, 0 files unresolved

  $ for emp in emp1 emp2 emp3; do echo nowork > $emp; done;
  $ hg ci -Aqm "added lazy emp1 emp2 emp3"

  $ hg log -GT "{rev} {node|short} {firstline(desc)}\n"
  @  2 0acfd4a49af0 added lazy emp1 emp2 emp3
  |
  | o  1 f30f98a8181f added emp1 emp2 emp3
  |/
  o  0 88660038d466 add boss
  
  $ hg rebase -s 1 -d 2
  rebasing 1:f30f98a8181f "added emp1 emp2 emp3"
  merging emp1
  warning: conflicts while merging emp1! (edit, then use 'hg resolve --mark')
  merging emp2
  warning: conflicts while merging emp2! (edit, then use 'hg resolve --mark')
  merging emp3
  warning: conflicts while merging emp3! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

Test when commands.resolve.confirm config option is not set:
===========================================================
  $ hg resolve --all
  merging emp1
  warning: conflicts while merging emp1! (edit, then use 'hg resolve --mark')
  merging emp2
  warning: conflicts while merging emp2! (edit, then use 'hg resolve --mark')
  merging emp3
  warning: conflicts while merging emp3! (edit, then use 'hg resolve --mark')
  [1]

Test when config option is set:
==============================
  $ cat >> .hg/hgrc << EOF
  > [ui]
  > interactive = True
  > [commands]
  > resolve.confirm = True
  > EOF

  $ hg resolve
  abort: no files or directories specified
  (use --all to re-merge all unresolved files)
  [10]
  $ hg resolve --all << EOF
  > n
  > EOF
  re-merge all unresolved files (yn)? n
  abort: user quit
  [250]

  $ hg resolve --all << EOF
  > y
  > EOF
  re-merge all unresolved files (yn)? y
  merging emp1
  warning: conflicts while merging emp1! (edit, then use 'hg resolve --mark')
  merging emp2
  warning: conflicts while merging emp2! (edit, then use 'hg resolve --mark')
  merging emp3
  warning: conflicts while merging emp3! (edit, then use 'hg resolve --mark')
  [1]

Test that commands.resolve.confirm respect --mark option (only when no patterns args are given):
===============================================================================================

  $ hg resolve -m emp1
  $ hg resolve -l
  R emp1
  U emp2
  U emp3

  $ hg resolve -m << EOF
  > n
  > EOF
  mark all unresolved files as resolved (yn)? n
  abort: user quit
  [250]

  $ hg resolve -m << EOF
  > y
  > EOF
  mark all unresolved files as resolved (yn)? y
  (no more unresolved files)
  continue: hg rebase --continue
  $ hg resolve -l
  R emp1
  R emp2
  R emp3

Test that commands.resolve.confirm respect --unmark option (only when no patterns args are given):
=================================================================================================

  $ hg resolve -u emp1

  $ hg resolve -l
  U emp1
  R emp2
  R emp3

  $ hg resolve -u << EOF
  > n
  > EOF
  mark all resolved files as unresolved (yn)? n
  abort: user quit
  [250]

  $ hg resolve -m << EOF
  > y
  > EOF
  mark all unresolved files as resolved (yn)? y
  (no more unresolved files)
  continue: hg rebase --continue

  $ hg resolve -l
  R emp1
  R emp2
  R emp3

  $ hg rebase --abort
  rebase aborted

Done with commands.resolve.confirm tests:
  $ cd ..

Test that commands.resolve.mark-check works even if there are deleted files:
  $ hg init resolve-deleted
  $ cd resolve-deleted
  $ echo r0 > file1
  $ hg ci -qAm r0
  $ echo r1 > file1
  $ hg ci -qm r1
  $ hg co -qr 0
  $ hg rm file1
  $ hg ci -qm "r2 (delete file1)"

(At this point we have r0 creating file1, and sibling commits r1 and r2, which
 modify and delete file1, respectively)

  $ hg merge -r 1
  file 'file1' was deleted in local [working copy] but was modified in other [merge rev].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ hg resolve --list
  U file1
Because we left it as 'unresolved' the file should still exist.
  $ [ -f file1 ] || echo "File does not exist?"
BC behavior: `hg resolve --mark` accepts that the file is still there, and
doesn't have a problem with this situation.
  $ hg resolve --mark --config commands.resolve.mark-check=abort
  (no more unresolved files)
  $ hg resolve --list
  R file1
The file is still there:
  $ [ -f file1 ] || echo "File does not exist?"
Let's check mark-check=warn:
  $ hg resolve --unmark file1
  $ hg resolve --mark --config commands.resolve.mark-check=warn
  (no more unresolved files)
  $ hg resolve --list
  R file1
The file is still there:
  $ [ -f file1 ] || echo "File does not exist?"
Let's resolve the issue by deleting the file via `hg resolve`
  $ hg resolve --unmark file1
  $ echo 'd' | hg resolve file1 --config ui.interactive=1
  file 'file1' was deleted in local [working copy] but was modified in other [merge rev].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? d
  (no more unresolved files)
  $ hg resolve --list
  R file1
The file is deleted:
  $ [ -f file1 ] && echo "File still exists?" || true
Doing `hg resolve --mark` doesn't break now that the file is missing:
  $ hg resolve --mark --config commands.resolve.mark-check=abort
  (no more unresolved files)
  $ hg resolve --mark --config commands.resolve.mark-check=warn
  (no more unresolved files)
Resurrect the file, and delete it outside of hg:
  $ hg resolve --unmark file1
  $ hg resolve file1
  file 'file1' was deleted in local [working copy] but was modified in other [merge rev].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  [1]
  $ [ -f file1 ] || echo "File does not exist?"
  $ hg resolve --list
  U file1
  $ rm file1
  $ hg resolve --mark --config commands.resolve.mark-check=abort
  (no more unresolved files)
  $ hg resolve --list
  R file1
  $ hg resolve --unmark file1
  $ hg resolve file1
  file 'file1' was deleted in local [working copy] but was modified in other [merge rev].
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  [1]
  $ [ -f file1 ] || echo "File does not exist?"
  $ hg resolve --list
  U file1
  $ rm file1
  $ hg resolve --mark --config commands.resolve.mark-check=warn
  (no more unresolved files)
  $ hg resolve --list
  R file1


For completeness, let's try that in the opposite direction (merging r2 into r1,
instead of r1 into r2):
  $ hg update -qCr 1
  $ hg merge -r 2
  file 'file1' was deleted in other [merge rev] but was modified in local [working copy].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ hg resolve --list
  U file1
Because we left it as 'unresolved' the file should still exist.
  $ [ -f file1 ] || echo "File does not exist?"
BC behavior: `hg resolve --mark` accepts that the file is still there, and
doesn't have a problem with this situation.
  $ hg resolve --mark --config commands.resolve.mark-check=abort
  (no more unresolved files)
  $ hg resolve --list
  R file1
The file is still there:
  $ [ -f file1 ] || echo "File does not exist?"
Let's check mark-check=warn:
  $ hg resolve --unmark file1
  $ hg resolve --mark --config commands.resolve.mark-check=warn
  (no more unresolved files)
  $ hg resolve --list
  R file1
The file is still there:
  $ [ -f file1 ] || echo "File does not exist?"
Let's resolve the issue by deleting the file via `hg resolve`
  $ hg resolve --unmark file1
  $ echo 'd' | hg resolve file1 --config ui.interactive=1
  file 'file1' was deleted in other [merge rev] but was modified in local [working copy].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? d
  (no more unresolved files)
  $ hg resolve --list
  R file1
The file is deleted:
  $ [ -f file1 ] && echo "File still exists?" || true
Doing `hg resolve --mark` doesn't break now that the file is missing:
  $ hg resolve --mark --config commands.resolve.mark-check=abort
  (no more unresolved files)
  $ hg resolve --mark --config commands.resolve.mark-check=warn
  (no more unresolved files)
Resurrect the file, and delete it outside of hg:
  $ hg resolve --unmark file1
  $ hg resolve file1
  file 'file1' was deleted in other [merge rev] but was modified in local [working copy].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  [1]
  $ [ -f file1 ] || echo "File does not exist?"
  $ hg resolve --list
  U file1
  $ rm file1
  $ hg resolve --mark --config commands.resolve.mark-check=abort
  (no more unresolved files)
  $ hg resolve --list
  R file1
  $ hg resolve --unmark file1
  $ hg resolve file1
  file 'file1' was deleted in other [merge rev] but was modified in local [working copy].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  [1]
  $ [ -f file1 ] || echo "File does not exist?"
  $ hg resolve --list
  U file1
  $ rm file1
  $ hg resolve --mark --config commands.resolve.mark-check=warn
  (no more unresolved files)
  $ hg resolve --list
  R file1

  $ cd ..

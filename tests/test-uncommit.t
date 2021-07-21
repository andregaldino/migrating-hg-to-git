Test uncommit - set up the config

  $ cat >> $HGRCPATH <<EOF
  > [experimental]
  > evolution.createmarkers=True
  > evolution.allowunstable=True
  > [extensions]
  > uncommit =
  > drawdag=$TESTDIR/drawdag.py
  > EOF

Build up a repo

  $ hg init repo
  $ cd repo
  $ hg bookmark foo

Help for uncommit

  $ hg help uncommit
  hg uncommit [OPTION]... [FILE]...
  
  uncommit part or all of a local changeset
  
      This command undoes the effect of a local commit, returning the affected
      files to their uncommitted state. This means that files modified or
      deleted in the changeset will be left unchanged, and so will remain
      modified in the working directory.
  
      If no files are specified, the commit will be pruned, unless --keep is
      given.
  
  (use 'hg help -e uncommit' to show help for the uncommit extension)
  
  options ([+] can be repeated):
  
      --keep                     allow an empty commit after uncommitting
      --allow-dirty-working-copy allow uncommit with outstanding changes
   -n --note TEXT                store a note on uncommit
   -I --include PATTERN [+]      include names matching the given patterns
   -X --exclude PATTERN [+]      exclude names matching the given patterns
   -m --message TEXT             use text as commit message
   -l --logfile FILE             read commit message from file
   -d --date DATE                record the specified date as commit date
   -u --user USER                record the specified user as committer
   -D --currentdate              record the current date as commit date
   -U --currentuser              record the current user as committer
  
  (some details hidden, use --verbose to show complete help)

Uncommit with no commits should fail

  $ hg uncommit
  abort: cannot uncommit the null revision
  (no changeset checked out)
  [10]

Create some commits

  $ touch files
  $ hg add files
  $ for i in a ab abc abcd abcde; do echo $i > files; echo $i > file-$i; hg add file-$i; hg commit -m "added file-$i"; done
  $ ls -A
  .hg
  file-a
  file-ab
  file-abc
  file-abcd
  file-abcde
  files

  $ hg log -G -T '{rev}:{node} {desc}' --hidden
  @  4:6c4fd43ed714e7fcd8adbaa7b16c953c2e985b60 added file-abcde
  |
  o  3:6db330d65db434145c0b59d291853e9a84719b24 added file-abcd
  |
  o  2:abf2df566fc193b3ac34d946e63c1583e4d4732b added file-abc
  |
  o  1:69a232e754b08d568c4899475faf2eb44b857802 added file-ab
  |
  o  0:3004d2d9b50883c1538fc754a3aeb55f1b4084f6 added file-a
  
Simple uncommit off the top, also moves bookmark

  $ hg bookmark
   * foo                       4:6c4fd43ed714
  $ hg uncommit
  $ hg status
  M files
  A file-abcde
  $ hg bookmark
   * foo                       3:6db330d65db4

  $ hg log -G -T '{rev}:{node} {desc}' --hidden
  x  4:6c4fd43ed714e7fcd8adbaa7b16c953c2e985b60 added file-abcde
  |
  @  3:6db330d65db434145c0b59d291853e9a84719b24 added file-abcd
  |
  o  2:abf2df566fc193b3ac34d946e63c1583e4d4732b added file-abc
  |
  o  1:69a232e754b08d568c4899475faf2eb44b857802 added file-ab
  |
  o  0:3004d2d9b50883c1538fc754a3aeb55f1b4084f6 added file-a
  

Recommit

  $ hg commit -m 'new change abcde'
  $ hg status
  $ hg heads -T '{rev}:{node} {desc}'
  5:0c07a3ccda771b25f1cb1edbd02e683723344ef1 new change abcde (no-eol)

Uncommit of non-existent and unchanged files aborts
  $ hg uncommit nothinghere
  abort: cannot uncommit "nothinghere"
  (file does not exist)
  [10]
  $ hg status
  $ hg uncommit file-abc
  abort: cannot uncommit "file-abc"
  (file was not changed in working directory parent)
  [10]
  $ hg status

Try partial uncommit, also moves bookmark

  $ hg bookmark
   * foo                       5:0c07a3ccda77
  $ hg uncommit files
  $ hg status
  M files
  $ hg bookmark
   * foo                       6:3727deee06f7
  $ hg heads -T '{rev}:{node} {desc}'
  6:3727deee06f72f5ffa8db792ee299cf39e3e190b new change abcde (no-eol)
  $ hg log -r . -p -T '{rev}:{node} {desc}'
  6:3727deee06f72f5ffa8db792ee299cf39e3e190b new change abcdediff -r 6db330d65db4 -r 3727deee06f7 file-abcde
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file-abcde	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +abcde
  
  $ hg log -G -T '{rev}:{node} {desc}' --hidden
  @  6:3727deee06f72f5ffa8db792ee299cf39e3e190b new change abcde
  |
  | x  5:0c07a3ccda771b25f1cb1edbd02e683723344ef1 new change abcde
  |/
  | x  4:6c4fd43ed714e7fcd8adbaa7b16c953c2e985b60 added file-abcde
  |/
  o  3:6db330d65db434145c0b59d291853e9a84719b24 added file-abcd
  |
  o  2:abf2df566fc193b3ac34d946e63c1583e4d4732b added file-abc
  |
  o  1:69a232e754b08d568c4899475faf2eb44b857802 added file-ab
  |
  o  0:3004d2d9b50883c1538fc754a3aeb55f1b4084f6 added file-a
  
  $ hg commit -m 'update files for abcde'

Uncommit with dirty state

  $ echo "foo" >> files
  $ cat files
  abcde
  foo
  $ hg status
  M files
  $ hg uncommit
  abort: uncommitted changes
  (requires --allow-dirty-working-copy to uncommit)
  [20]
  $ hg uncommit files
  abort: uncommitted changes
  (requires --allow-dirty-working-copy to uncommit)
  [20]
  $ cat files
  abcde
  foo
  $ hg commit --amend -m "files abcde + foo"

Testing the 'experimental.uncommitondirtywdir' config

  $ echo "bar" >> files
  $ hg uncommit
  abort: uncommitted changes
  (requires --allow-dirty-working-copy to uncommit)
  [20]
  $ hg uncommit --config experimental.uncommitondirtywdir=True
  $ hg commit -m "files abcde + foo"

Uncommit in the middle of a stack, does not move bookmark

  $ hg checkout '.^^^'
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved
  (leaving bookmark foo)
  $ hg log -r . -p -T '{rev}:{node} {desc}'
  2:abf2df566fc193b3ac34d946e63c1583e4d4732b added file-abcdiff -r 69a232e754b0 -r abf2df566fc1 file-abc
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file-abc	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +abc
  diff -r 69a232e754b0 -r abf2df566fc1 files
  --- a/files	Thu Jan 01 00:00:00 1970 +0000
  +++ b/files	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -ab
  +abc
  
  $ hg bookmark
     foo                       9:48e5bd7cd583
  $ hg uncommit
  3 new orphan changesets
  $ hg status
  M files
  A file-abc
  $ hg heads -T '{rev}:{node} {desc}'
  9:48e5bd7cd583eb24164ef8b89185819c84c96ed7 files abcde + foo (no-eol)
  $ hg bookmark
     foo                       9:48e5bd7cd583
  $ hg commit -m 'new abc'
  created new head

Partial uncommit in the middle, does not move bookmark

  $ hg checkout '.^'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg log -r . -p -T '{rev}:{node} {desc}'
  1:69a232e754b08d568c4899475faf2eb44b857802 added file-abdiff -r 3004d2d9b508 -r 69a232e754b0 file-ab
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file-ab	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +ab
  diff -r 3004d2d9b508 -r 69a232e754b0 files
  --- a/files	Thu Jan 01 00:00:00 1970 +0000
  +++ b/files	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -a
  +ab
  
  $ hg bookmark
     foo                       9:48e5bd7cd583
  $ hg uncommit file-ab
  1 new orphan changesets
  $ hg status
  A file-ab

  $ hg heads -T '{rev}:{node} {desc}\n'
  11:8eb87968f2edb7f27f27fe676316e179de65fff6 added file-ab
  10:5dc89ca4486f8a88716c5797fa9f498d13d7c2e1 new abc
  9:48e5bd7cd583eb24164ef8b89185819c84c96ed7 files abcde + foo

  $ hg bookmark
     foo                       9:48e5bd7cd583
  $ hg commit -m 'update ab'
  $ hg status
  $ hg heads -T '{rev}:{node} {desc}\n'
  12:f21039c59242b085491bb58f591afc4ed1c04c09 update ab
  10:5dc89ca4486f8a88716c5797fa9f498d13d7c2e1 new abc
  9:48e5bd7cd583eb24164ef8b89185819c84c96ed7 files abcde + foo

  $ hg log -G -T '{rev}:{node} {desc}' --hidden
  @  12:f21039c59242b085491bb58f591afc4ed1c04c09 update ab
  |
  o  11:8eb87968f2edb7f27f27fe676316e179de65fff6 added file-ab
  |
  | *  10:5dc89ca4486f8a88716c5797fa9f498d13d7c2e1 new abc
  | |
  | | *  9:48e5bd7cd583eb24164ef8b89185819c84c96ed7 files abcde + foo
  | | |
  | | | x  8:84beeba0ac30e19521c036e4d2dd3a5fa02586ff files abcde + foo
  | | |/
  | | | x  7:0977fa602c2fd7d8427ed4e7ee15ea13b84c9173 update files for abcde
  | | |/
  | | *  6:3727deee06f72f5ffa8db792ee299cf39e3e190b new change abcde
  | | |
  | | | x  5:0c07a3ccda771b25f1cb1edbd02e683723344ef1 new change abcde
  | | |/
  | | | x  4:6c4fd43ed714e7fcd8adbaa7b16c953c2e985b60 added file-abcde
  | | |/
  | | *  3:6db330d65db434145c0b59d291853e9a84719b24 added file-abcd
  | | |
  | | x  2:abf2df566fc193b3ac34d946e63c1583e4d4732b added file-abc
  | |/
  | x  1:69a232e754b08d568c4899475faf2eb44b857802 added file-ab
  |/
  o  0:3004d2d9b50883c1538fc754a3aeb55f1b4084f6 added file-a
  
Uncommit with draft parent

  $ hg uncommit
  $ hg phase -r .
  11: draft
  $ hg commit -m 'update ab again'

Phase is preserved

  $ hg uncommit --keep --config phases.new-commit=secret
  note: keeping empty commit
  $ hg phase -r .
  14: draft
  $ hg commit --amend -m 'update ab again'

Uncommit with public parent

  $ hg phase -p "::.^"
  $ hg uncommit
  $ hg phase -r .
  11: public

Partial uncommit with public parent

  $ echo xyz > xyz
  $ hg add xyz
  $ hg commit -m "update ab and add xyz"
  $ hg uncommit xyz
  $ hg status
  A xyz
  $ hg phase -r .
  17: draft
  $ hg phase -r ".^"
  11: public

Uncommit with --keep or experimental.uncommit.keep leaves an empty changeset

  $ cd $TESTTMP
  $ hg init repo1
  $ cd repo1
  $ hg debugdrawdag <<'EOS'
  > Q
  > |
  > P
  > EOS
  $ hg up Q -q
  $ hg uncommit --keep
  note: keeping empty commit
  $ hg log -G -T '{desc} FILES: {files}'
  @  Q FILES:
  |
  | x  Q FILES: Q
  |/
  o  P FILES: P
  
  $ cat >> .hg/hgrc <<EOF
  > [experimental]
  > uncommit.keep=True
  > EOF
  $ hg ci --amend
  $ hg uncommit
  note: keeping empty commit
  $ hg log -G -T '{desc} FILES: {files}'
  @  Q FILES:
  |
  | x  Q FILES: Q
  |/
  o  P FILES: P
  
  $ hg status
  A Q
  $ hg ci --amend
  $ hg uncommit --no-keep
  $ hg log -G -T '{desc} FILES: {files}'
  x  Q FILES: Q
  |
  @  P FILES: P
  
  $ hg status
  A Q
  $ cd ..
  $ rm -rf repo1

Testing uncommit while merge

  $ hg init repo2
  $ cd repo2

Create some history

  $ touch a
  $ hg add a
  $ for i in 1 2 3; do echo $i > a; hg commit -m "a $i"; done
  $ hg checkout 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ touch b
  $ hg add b
  $ for i in 1 2 3; do echo $i > b; hg commit -m "b $i"; done
  created new head
  $ hg log -G -T '{rev}:{node} {desc}' --hidden
  @  5:2cd56cdde163ded2fbb16ba2f918c96046ab0bf2 b 3
  |
  o  4:c3a0d5bb3b15834ffd2ef9ef603e93ec65cf2037 b 2
  |
  o  3:49bb009ca26078726b8870f1edb29fae8f7618f5 b 1
  |
  | o  2:990982b7384266e691f1bc08ca36177adcd1c8a9 a 3
  | |
  | o  1:24d38e3cf160c7b6f5ffe82179332229886a6d34 a 2
  |/
  o  0:ea4e33293d4d274a2ba73150733c2612231f398c a 1
  

Add and expect uncommit to fail on both merge working dir and merge changeset

  $ hg merge 2
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg uncommit
  abort: outstanding uncommitted merge
  (requires --allow-dirty-working-copy to uncommit)
  [20]

  $ hg uncommit --config experimental.uncommitondirtywdir=True
  abort: cannot uncommit changesets while merging
  [20]

  $ hg status
  M a
  $ hg commit -m 'merge a and b'

  $ hg uncommit
  abort: cannot uncommit merge changeset
  [10]

  $ hg status
  $ hg log -G -T '{rev}:{node} {desc}' --hidden
  @    6:c03b9c37bc67bf504d4912061cfb527b47a63c6e merge a and b
  |\
  | o  5:2cd56cdde163ded2fbb16ba2f918c96046ab0bf2 b 3
  | |
  | o  4:c3a0d5bb3b15834ffd2ef9ef603e93ec65cf2037 b 2
  | |
  | o  3:49bb009ca26078726b8870f1edb29fae8f7618f5 b 1
  | |
  o |  2:990982b7384266e691f1bc08ca36177adcd1c8a9 a 3
  | |
  o |  1:24d38e3cf160c7b6f5ffe82179332229886a6d34 a 2
  |/
  o  0:ea4e33293d4d274a2ba73150733c2612231f398c a 1
  

Rename a->b, then remove b in working copy. Result should remove a.

  $ hg co -q 0
  $ hg mv a b
  $ hg ci -qm 'move a to b'
  $ hg rm b
  $ hg uncommit --config experimental.uncommitondirtywdir=True
  $ hg st --copies
  R a
  $ hg revert a

Rename a->b, then rename b->c in working copy. Result should rename a->c.

  $ hg co -q 0
  $ hg mv a b
  $ hg ci -qm 'move a to b'
  $ hg mv b c
  $ hg uncommit --config experimental.uncommitondirtywdir=True
  $ hg st --copies
  A c
    a
  R a
  $ hg revert a
  $ hg forget c
  $ rm c

Copy a->b1 and a->b2, then rename b1->c in working copy. Result should copy a->b2 and a->c.

  $ hg co -q 0
  $ hg cp a b1
  $ hg cp a b2
  $ hg ci -qm 'move a to b1 and b2'
  $ hg mv b1 c
  $ hg uncommit --config experimental.uncommitondirtywdir=True
  $ hg st --copies
  A b2
    a
  A c
    a
  $ cd ..

--allow-dirty-working-copy should also work on a dirty PATH

  $ hg init issue5977
  $ cd issue5977
  $ echo 'super critical info!' > a
  $ hg ci -Am 'add a'
  adding a
  $ echo 'foo' > b
  $ hg add b
  $ hg status
  A b
  $ hg uncommit a
  note: keeping empty commit
  $ cat a
  super critical info!
  $ hg log
  changeset:   1:656ba143d384
  tag:         tip
  parent:      -1:000000000000
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     add a
  
  $ hg ci -Am 'add b'
  $ echo 'foo bar' > b
  $ hg uncommit b
  abort: uncommitted changes
  (requires --allow-dirty-working-copy to uncommit)
  [20]
  $ hg uncommit --allow-dirty-working-copy b
  $ hg log
  changeset:   3:30fa958635b2
  tag:         tip
  parent:      1:656ba143d384
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     add b
  
  changeset:   1:656ba143d384
  parent:      -1:000000000000
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     add a
  
Removes can be uncommitted

  $ hg ci -m 'modified b'
  $ hg rm b
  $ hg ci -m 'remove b'
  $ hg uncommit b
  note: keeping empty commit
  $ hg status
  R b

Uncommitting a directory won't run afoul of the checks that an explicit file
can be uncommitted.

  $ mkdir dir
  $ echo 1 > dir/file.txt
  $ hg ci -Aqm 'add file in directory'
  $ hg uncommit dir -m 'uncommit with message' -u 'different user' \
  >                 -d 'Jun 30 12:12:12 1980 +0000'
  $ hg status
  A dir/file.txt
  $ hg log -r .
  changeset:   8:b4dd26dc42e0
  tag:         tip
  parent:      6:2278a4c24330
  user:        different user
  date:        Mon Jun 30 12:12:12 1980 +0000
  summary:     uncommit with message
  
Bad option combinations

  $ hg rollback -q --config ui.rollback=True
  $ hg uncommit -U --user 'user'
  abort: cannot specify both --user and --currentuser
  [10]
  $ hg uncommit -D --date today
  abort: cannot specify both --date and --currentdate
  [10]

`uncommit <dir>` and `cd <dir> && uncommit .` behave the same...

  $ echo 2 > dir/file2.txt
  $ hg ci -Aqm 'add file2 in directory'
  $ hg uncommit dir
  note: keeping empty commit
  $ hg status
  A dir/file2.txt

  $ hg rollback -q --config ui.rollback=True
  $ cd dir
  $ hg uncommit . -n 'this is a note'
  note: keeping empty commit
  $ hg status
  A dir/file2.txt
  $ cd ..

... and errors out the same way when nothing can be uncommitted

  $ hg rollback -q --config ui.rollback=True
  $ mkdir emptydir
  $ hg uncommit emptydir
  abort: cannot uncommit "emptydir"
  (file was untracked in working directory parent)
  [10]

  $ cd emptydir
  $ hg uncommit .
  abort: cannot uncommit "emptydir"
  (file was untracked in working directory parent)
  [10]
  $ hg status
  $ cd ..

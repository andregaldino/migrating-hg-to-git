
  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > copies.write-to=changeset-only
  > copies.read-from=changeset-only
  > [alias]
  > changesetcopies = log -r . -T 'files: {files}
  >   {extras % "{ifcontains("files", key, "{key}: {value}\n")}"}
  >   {extras % "{ifcontains("copies", key, "{key}: {value}\n")}"}'
  > showcopies = log -r . -T '{file_copies % "{source} -> {name}\n"}'
  > [extensions]
  > rebase =
  > split =
  > EOF

Check that copies are recorded correctly

  $ hg init repo
  $ cd repo
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ hg cp a b
  $ hg cp a c
  $ hg cp a d
  $ hg ci -m 'copy a to b, c, and d'
  $ hg changesetcopies
  files: b c d
  filesadded: 0
  1
  2
  
  p1copies: 0\x00a (esc)
  1\x00a (esc)
  2\x00a (esc)
  $ hg showcopies
  a -> b
  a -> c
  a -> d
  $ hg showcopies --config experimental.copies.read-from=compatibility
  a -> b
  a -> c
  a -> d
  $ hg showcopies --config experimental.copies.read-from=filelog-only

Check that renames are recorded correctly

  $ hg mv b b2
  $ hg ci -m 'rename b to b2'
  $ hg changesetcopies
  files: b b2
  filesadded: 1
  filesremoved: 0
  
  p1copies: 1\x00b (esc)
  $ hg showcopies
  b -> b2

Rename onto existing file. This should get recorded in the changeset files list and in the extras,
even though there is no filelog entry.

  $ hg cp b2 c --force
  $ hg st --copies
  M c
    b2
  $ hg debugindex c
     rev linkrev nodeid       p1           p2
       0       1 b789fdd96dc2 000000000000 000000000000
  $ hg ci -m 'move b onto d'
  $ hg changesetcopies
  files: c
  
  p1copies: 0\x00b2 (esc)
  $ hg showcopies
  b2 -> c
  $ hg debugindex c
     rev linkrev nodeid       p1           p2
       0       1 b789fdd96dc2 000000000000 000000000000

Create a merge commit with copying done during merge.

  $ hg co 0
  0 files updated, 0 files merged, 3 files removed, 0 files unresolved
  $ hg cp a e
  $ hg cp a f
  $ hg ci -m 'copy a to e and f'
  created new head
  $ hg merge 3
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
File 'a' exists on both sides, so 'g' could be recorded as being from p1 or p2, but we currently
always record it as being from p1
  $ hg cp a g
File 'd' exists only in p2, so 'h' should be from p2
  $ hg cp d h
File 'f' exists only in p1, so 'i' should be from p1
  $ hg cp f i
  $ hg ci -m 'merge'
  $ hg changesetcopies
  files: g h i
  filesadded: 0
  1
  2
  
  p1copies: 0\x00a (esc)
  2\x00f (esc)
  p2copies: 1\x00d (esc)
  $ hg showcopies
  a -> g
  d -> h
  f -> i

Test writing to both changeset and filelog

  $ hg cp a j
  $ hg ci -m 'copy a to j' --config experimental.copies.write-to=compatibility
  $ hg changesetcopies
  files: j
  filesadded: 0
  filesremoved: 
  
  p1copies: 0\x00a (esc)
  p2copies: 
  $ hg debugdata j 0
  \x01 (esc)
  copy: a
  copyrev: b789fdd96dc2f3bd229c1dd8eedf0fc60e2b68e3
  \x01 (esc)
  a
  $ hg showcopies
  a -> j
  $ hg showcopies --config experimental.copies.read-from=compatibility
  a -> j
  $ hg showcopies --config experimental.copies.read-from=filelog-only
  a -> j
The entries should be written to extras even if they're empty (so the client
won't have to fall back to reading from filelogs)
  $ echo x >> j
  $ hg ci -m 'modify j' --config experimental.copies.write-to=compatibility
  $ hg changesetcopies
  files: j
  filesadded: 
  filesremoved: 
  
  p1copies: 
  p2copies: 

Test writing only to filelog

  $ hg cp a k
  $ hg ci -m 'copy a to k' --config experimental.copies.write-to=filelog-only
  $ hg changesetcopies
  files: k
  
  $ hg debugdata k 0
  \x01 (esc)
  copy: a
  copyrev: b789fdd96dc2f3bd229c1dd8eedf0fc60e2b68e3
  \x01 (esc)
  a
  $ hg showcopies
  $ hg showcopies --config experimental.copies.read-from=compatibility
  a -> k
  $ hg showcopies --config experimental.copies.read-from=filelog-only
  a -> k

  $ cd ..

Test rebasing a commit with copy information

  $ hg init rebase-rename
  $ cd rebase-rename
  $ echo a > a
  $ hg ci -Aqm 'add a'
  $ echo a2 > a
  $ hg ci -m 'modify a'
  $ hg co -q 0
  $ hg mv a b
  $ hg ci -qm 'rename a to b'
  $ hg rebase -d 1 --config rebase.experimental.inmemory=yes
  rebasing 2:fc7287ac5b9b "rename a to b" (tip)
  merging a and b to b
  saved backup bundle to $TESTTMP/rebase-rename/.hg/strip-backup/fc7287ac5b9b-8f2a95ec-rebase.hg
  $ hg st --change . --copies
  A b
    a
  R a
  $ cd ..

Test splitting a commit

  $ hg init split
  $ cd split
  $ echo a > a
  $ echo b > b
  $ hg ci -Aqm 'add a and b'
  $ echo a2 > a
  $ hg mv b c
  $ hg ci -m 'modify a, move b to c'
  $ (hg --config ui.interactive=yes split 2>&1 | grep mercurial.error) <<EOF
  > y
  > y
  > n
  > y
  > EOF
  mercurial.error.ProgrammingError: some copy targets missing from file list
  $ cd ..

Test committing half a rename

  $ hg init partial
  $ cd partial
  $ echo a > a
  $ hg ci -Aqm 'add a'
  $ hg mv a b
  $ hg ci -m 'remove a' a 2>&1 | grep mercurial.error
  mercurial.error.ProgrammingError: some copy targets missing from file list
  $ cd ..

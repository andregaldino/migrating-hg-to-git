#testcases extra sidedata

#if extra
  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > copies.write-to=changeset-only
  > copies.read-from=changeset-only
  > [alias]
  > changesetcopies = log -r . -T 'files: {files}
  >   {extras % "{ifcontains("files", key, "{key}: {value}\n")}"}
  >   {extras % "{ifcontains("copies", key, "{key}: {value}\n")}"}'
  > EOF
#endif

#if sidedata
  $ cat >> $HGRCPATH << EOF
  > [format]
  > exp-use-copies-side-data-changeset = yes
  > EOF
#endif

  $ cat >> $HGRCPATH << EOF
  > [alias]
  > showcopies = log -r . -T '{file_copies % "{source} -> {name}\n"}'
  > [extensions]
  > rebase =
  > split =
  > EOF

Check that copies are recorded correctly

  $ hg init repo
  $ cd repo
#if sidedata
  $ hg debugformat -v | egrep 'format-variant|revlog-v2|copies-sdc|changelog-v2'
  format-variant     repo config default
  copies-sdc:         yes    yes      no
  revlog-v2:           no     no      no
  changelog-v2:       yes    yes      no
#else
  $ hg debugformat -v | egrep 'format-variant|revlog-v2|copies-sdc|changelog-v2'
  format-variant     repo config default
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
#endif
  $ echo a > a
  $ hg add a
  $ hg ci -m initial
  $ hg cp a b
  $ hg cp a c
  $ hg cp a d
  $ hg ci -m 'copy a to b, c, and d'

#if extra

  $ hg changesetcopies
  files: b c d
  filesadded: 0
  1
  2
  
  p1copies: 0\x00a (esc)
  1\x00a (esc)
  2\x00a (esc)
#else
  $ hg debugsidedata -c -v -- -1
  1 sidedata entries
   entry-0014 size 44
    '\x00\x00\x00\x04\x00\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00\x06\x00\x00\x00\x03\x00\x00\x00\x00\x06\x00\x00\x00\x04\x00\x00\x00\x00abcd'
#endif

  $ hg showcopies
  a -> b
  a -> c
  a -> d

#if extra

  $ hg showcopies --config experimental.copies.read-from=compatibility
  a -> b
  a -> c
  a -> d
  $ hg showcopies --config experimental.copies.read-from=filelog-only

#endif

Check that renames are recorded correctly

  $ hg mv b b2
  $ hg ci -m 'rename b to b2'

#if extra

  $ hg changesetcopies
  files: b b2
  filesadded: 1
  filesremoved: 0
  
  p1copies: 1\x00b (esc)

#else
  $ hg debugsidedata -c -v -- -1
  1 sidedata entries
   entry-0014 size 25
    '\x00\x00\x00\x02\x0c\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x03\x00\x00\x00\x00bb2'
#endif

  $ hg showcopies
  b -> b2


Rename onto existing file. This should get recorded in the changeset files list and in the extras,
even though there is no filelog entry.

  $ hg cp b2 c --force
  $ hg st --copies
  M c
    b2

#if extra

  $ hg debugindex c
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       1 b789fdd96dc2 000000000000 000000000000

#else

  $ hg debugindex c
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       1 37d9b5d994ea 000000000000 000000000000

#endif


  $ hg ci -m 'move b onto d'

#if extra

  $ hg changesetcopies
  files: c
  
  p1copies: 0\x00b2 (esc)

#else
  $ hg debugsidedata -c -v -- -1
  1 sidedata entries
   entry-0014 size 25
    '\x00\x00\x00\x02\x00\x00\x00\x00\x02\x00\x00\x00\x00\x16\x00\x00\x00\x03\x00\x00\x00\x00b2c'
#endif

  $ hg showcopies
  b2 -> c

#if extra

  $ hg debugindex c
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       1 b789fdd96dc2 000000000000 000000000000

#else

  $ hg debugindex c
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       1 37d9b5d994ea 000000000000 000000000000
       1       3 029625640347 000000000000 000000000000

#endif

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

#if extra

  $ hg changesetcopies
  files: g h i
  filesadded: 0
  1
  2
  
  p1copies: 0\x00a (esc)
  2\x00f (esc)
  p2copies: 1\x00d (esc)

#else
  $ hg debugsidedata -c -v -- -1
  1 sidedata entries
   entry-0014 size 64
    '\x00\x00\x00\x06\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00\x00\x06\x00\x00\x00\x04\x00\x00\x00\x00\x07\x00\x00\x00\x05\x00\x00\x00\x01\x06\x00\x00\x00\x06\x00\x00\x00\x02adfghi'
#endif

  $ hg showcopies
  a -> g
  d -> h
  f -> i

Test writing to both changeset and filelog

  $ hg cp a j
#if extra
  $ hg ci -m 'copy a to j' --config experimental.copies.write-to=compatibility
  $ hg changesetcopies
  files: j
  filesadded: 0
  filesremoved: 
  
  p1copies: 0\x00a (esc)
  p2copies: 
#else
  $ hg ci -m 'copy a to j'
  $ hg debugsidedata -c -v -- -1
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x00\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00aj'
#endif
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
Existing copy information in the changeset gets removed on amend and writing
copy information on to the filelog
#if extra
  $ hg ci --amend -m 'copy a to j, v2' \
  > --config experimental.copies.write-to=filelog-only
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/*-*-amend.hg (glob)
  $ hg changesetcopies
  files: j
  
#else
  $ hg ci --amend -m 'copy a to j, v2'
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/*-*-amend.hg (glob)
  $ hg debugsidedata -c -v -- -1
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x00\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00aj'
#endif
  $ hg showcopies --config experimental.copies.read-from=filelog-only
  a -> j
The entries should be written to extras even if they're empty (so the client
won't have to fall back to reading from filelogs)
  $ echo x >> j
#if extra
  $ hg ci -m 'modify j' --config experimental.copies.write-to=compatibility
  $ hg changesetcopies
  files: j
  filesadded: 
  filesremoved: 
  
  p1copies: 
  p2copies: 
#else
  $ hg ci -m 'modify j'
  $ hg debugsidedata -c -v -- -1
  1 sidedata entries
   entry-0014 size 14
    '\x00\x00\x00\x01\x14\x00\x00\x00\x01\x00\x00\x00\x00j'
#endif

Test writing only to filelog

  $ hg cp a k
#if extra
  $ hg ci -m 'copy a to k' --config experimental.copies.write-to=filelog-only

  $ hg changesetcopies
  files: k
  
#else
  $ hg ci -m 'copy a to k'
  $ hg debugsidedata -c -v -- -1
  1 sidedata entries
   entry-0014 size 24
    '\x00\x00\x00\x02\x00\x00\x00\x00\x01\x00\x00\x00\x00\x06\x00\x00\x00\x02\x00\x00\x00\x00ak'
#endif

  $ hg debugdata k 0
  \x01 (esc)
  copy: a
  copyrev: b789fdd96dc2f3bd229c1dd8eedf0fc60e2b68e3
  \x01 (esc)
  a
#if extra
  $ hg showcopies

  $ hg showcopies --config experimental.copies.read-from=compatibility
  a -> k
  $ hg showcopies --config experimental.copies.read-from=filelog-only
  a -> k
#else
  $ hg showcopies
  a -> k
#endif

Existing copy information is preserved by amend
  $ hg cp a l
  $ hg ci -m 'copy a to l'
  $ hg showcopies
  a -> l
  $ hg ci --amend -m 'new description'
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/*-*-amend.hg (glob)
  $ hg showcopies
  a -> l

No crash on partial amend
  $ hg st --change .
  A l
  $ echo modified >> a
  $ hg rm l
  $ hg commit --amend a
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/*-*-amend.hg (glob)

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
Not only do we want this to run in-memory, it shouldn't fall back to
on-disk merge (no conflicts), so we force it to be in-memory
with no fallback.
  $ hg rebase -d 1 --config rebase.experimental.inmemory=yes --config devel.rebase.force-in-memory-merge=yes
  rebasing 2:* tip "rename a to b" (glob)
  merging a and b to b
  saved backup bundle to $TESTTMP/rebase-rename/.hg/strip-backup/*-*-rebase.hg (glob)
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
  $ hg --config ui.interactive=yes split <<EOF
  > y
  > y
  > n
  > y
  > EOF
  diff --git a/a b/a
  1 hunks, 1 lines changed
  examine changes to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -1,1 +1,1 @@
  -a
  +a2
  record this change to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  diff --git a/b b/c
  rename from b
  rename to c
  examine changes to 'b' and 'c'?
  (enter ? for help) [Ynesfdaq?] n
  
  created new head
  diff --git a/b b/c
  rename from b
  rename to c
  examine changes to 'b' and 'c'?
  (enter ? for help) [Ynesfdaq?] y
  
  saved backup bundle to $TESTTMP/split/.hg/strip-backup/*-*-split.hg (glob)
  $ cd ..

Test committing half a rename

  $ hg init partial
  $ cd partial
  $ echo a > a
  $ hg ci -Aqm 'add a'
  $ hg mv a b
  $ hg ci -m 'remove a' a

#if sidedata

Test upgrading/downgrading to sidedata storage
==============================================

downgrading

  $ hg debugformat -v | egrep 'format-variant|revlog-v2|copies-sdc|changelog-v2'
  format-variant     repo config default
  copies-sdc:         yes    yes      no
  revlog-v2:           no     no      no
  changelog-v2:       yes    yes      no
  $ hg debugsidedata -c -- 0
  1 sidedata entries
   entry-0014 size 14
  $ hg debugsidedata -c -- 1
  1 sidedata entries
   entry-0014 size 14
  $ hg debugsidedata -m -- 0
  $ cat << EOF > .hg/hgrc
  > [format]
  > exp-use-copies-side-data-changeset = no
  > EOF
  $ hg debugupgraderepo --run --quiet --no-backup
  upgrade will perform the following actions:
  
  requirements
     preserved: * (glob)
     removed: exp-changelog-v2, exp-copies-sidedata-changeset
  
  processed revlogs:
    - changelog
  
  $ hg debugformat -v | egrep 'format-variant|revlog-v2|copies-sdc|changelog-v2'
  format-variant     repo config default
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  $ hg debugsidedata -c -- 0
  $ hg debugsidedata -c -- 1
  $ hg debugsidedata -m -- 0

upgrading

  $ cat << EOF > .hg/hgrc
  > [format]
  > exp-use-copies-side-data-changeset = yes
  > EOF
  $ hg debugupgraderepo --run --quiet --no-backup
  upgrade will perform the following actions:
  
  requirements
     preserved: * (glob)
     added: exp-changelog-v2, exp-copies-sidedata-changeset
  
  processed revlogs:
    - changelog
  
  $ hg debugformat -v | egrep 'format-variant|revlog-v2|copies-sdc|changelog-v2'
  format-variant     repo config default
  copies-sdc:         yes    yes      no
  revlog-v2:           no     no      no
  changelog-v2:       yes    yes      no
  $ hg debugsidedata -c -- 0
  1 sidedata entries
   entry-0014 size 14
  $ hg debugsidedata -c -- 1
  1 sidedata entries
   entry-0014 size 14
  $ hg debugsidedata -m -- 0

#endif

  $ cd ..

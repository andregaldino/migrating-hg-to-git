Testing cloning with the EOL extension

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > eol =
  > 
  > [eol]
  > native = CRLF
  > EOF

setup repository

  $ hg init repo
  $ cd repo
  $ cat > .hgeol <<EOF
  > [patterns]
  > **.txt = native
  > EOF
  $ printf "first\r\nsecond\r\nthird\r\n" > a.txt
  $ hg commit --addremove -m 'checkin'
  adding .hgeol
  adding a.txt

Test commit of removed .hgeol and how it immediately makes the automatic
changes explicit and committable.

  $ cd ..
  $ hg clone repo repo-2
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd repo-2
  $ cat a.txt
  first\r (esc)
  second\r (esc)
  third\r (esc)
  $ hg cat a.txt
  first
  second
  third
  $ hg remove .hgeol
  $ touch a.txt *  # ensure consistent st dirtyness checks, ignoring dirstate timing
  $ hg st -v --debug
  M a.txt
  R .hgeol
  $ hg commit -m 'remove eol'
  $ hg exp
  # HG changeset patch
  # User test
  # Date 0 0
  #      Thu Jan 01 00:00:00 1970 +0000
  # Node ID 3c20c2d90333b6ecdc8f7aa8f9b73223c7c7a608
  # Parent  90f94e2cf4e24628afddd641688dfe4cd476d6e4
  remove eol
  
  diff -r 90f94e2cf4e2 -r 3c20c2d90333 .hgeol
  --- a/.hgeol	Thu Jan 01 00:00:00 1970 +0000
  +++ /dev/null	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,2 +0,0 @@
  -[patterns]
  -**.txt = native
  diff -r 90f94e2cf4e2 -r 3c20c2d90333 a.txt
  --- a/a.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,3 +1,3 @@
  -first
  -second
  -third
  +first\r (esc)
  +second\r (esc)
  +third\r (esc)
  $ hg push --quiet
  $ cd ..

Test clone of repo with .hgeol in working dir, but no .hgeol in default
checkout revision tip. The repo is correctly updated to be consistent and have
the exact content checked out without filtering, ignoring the current .hgeol in
the source repo:

  $ cat repo/.hgeol
  [patterns]
  **.txt = native
  $ hg clone repo repo-3 -v --debug
  linked 7 files
  updating to branch default
  resolving manifests
   branchmerge: False, force: False, partial: False
   ancestor: 000000000000, local: 000000000000+, remote: 3c20c2d90333
  calling hook preupdate.eol: hgext.eol.preupdate
   a.txt: remote created -> g
  getting a.txt
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  updating the branch cache
  $ cd repo-3

  $ cat a.txt
  first\r (esc)
  second\r (esc)
  third\r (esc)

Test clone of revision with .hgeol

  $ cd ..
  $ hg clone -r 0 repo repo-4
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  new changesets 90f94e2cf4e2
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd repo-4
  $ cat .hgeol
  [patterns]
  **.txt = native

  $ cat a.txt
  first\r (esc)
  second\r (esc)
  third\r (esc)

  $ cd ..

#testcases obsstore-on obsstore-off

  $ cat > $TESTTMP/editor.py <<EOF
  > #!"$PYTHON"
  > import os
  > import sys
  > path = os.path.join(os.environ['TESTTMP'], 'messages')
  > messages = open(path).read().split('--\n')
  > prompt = open(sys.argv[1]).read()
  > sys.stdout.write(''.join('EDITOR: %s' % l for l in prompt.splitlines(True)))
  > sys.stdout.flush()
  > with open(sys.argv[1], 'w') as f:
  >    f.write(messages[0])
  > with open(path, 'w') as f:
  >    f.write('--\n'.join(messages[1:]))
  > EOF

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > drawdag=$TESTDIR/drawdag.py
  > split=
  > [ui]
  > interactive=1
  > color=no
  > paginate=never
  > [diff]
  > git=1
  > unified=0
  > [commands]
  > commit.interactive.unified=0
  > [alias]
  > glog=log -G -T '{rev}:{node|short} {desc} {bookmarks}\n'
  > EOF

#if obsstore-on
  $ cat >> $HGRCPATH <<EOF
  > [experimental]
  > evolution=all
  > EOF
#endif

  $ hg init a
  $ cd a

Nothing to split

  $ hg split
  nothing to split
  [1]

  $ hg commit -m empty --config ui.allowemptycommit=1
  $ hg split
  abort: cannot split an empty revision
  [10]

  $ rm -rf .hg
  $ hg init

Cannot split working directory

  $ hg split -r 'wdir()'
  abort: cannot split working directory
  [10]

Generate some content.  The sed filter drop CR on Windows, which is dropped in
the a > b line.

  $ $TESTDIR/seq.py 1 5 | sed 's/\r$//' >> a
  $ hg ci -m a1 -A a -q
  $ hg bookmark -i r1
  $ sed 's/1/11/;s/3/33/;s/5/55/' a > b
  $ mv b a
  $ hg ci -m a2 -q
  $ hg bookmark -i r2

Cannot split a public changeset

  $ hg phase --public -r 'all()'
  $ hg split .
  abort: cannot split public changesets: 1df0d5c5a3ab
  (see 'hg help phases' for details)
  [10]

  $ hg phase --draft -f -r 'all()'

Cannot split while working directory is dirty

  $ touch dirty
  $ hg add dirty
  $ hg split .
  abort: uncommitted changes
  [20]
  $ hg forget dirty
  $ rm dirty

Make a clean directory for future tests to build off of

  $ cp -R . ../clean

Split a head

  $ hg bookmark r3

  $ hg split 'all()'
  abort: cannot split multiple revisions
  [10]

This function splits a bit strangely primarily to avoid changing the behavior of
the test after a bug was fixed with how split/commit --interactive handled
`commands.commit.interactive.unified=0`: when there were no context lines,
it kept only the last diff hunk. When running split, this meant that runsplit
was always recording three commits, one for each diff hunk, in reverse order
(the base commit was the last diff hunk in the file).
  $ runsplit() {
  > cat > $TESTTMP/messages <<EOF
  > split 1
  > --
  > split 2
  > --
  > split 3
  > EOF
  > cat <<EOF | hg split "$@"
  > y
  > n
  > n
  > y
  > y
  > n
  > y
  > y
  > y
  > EOF
  > }

  $ HGEDITOR=false runsplit
  diff --git a/a b/a
  3 hunks, 3 lines changed
  examine changes to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -1,1 +1,1 @@
  -1
  +11
  record change 1/3 to 'a'?
  (enter ? for help) [Ynesfdaq?] n
  
  @@ -3,1 +3,1 @@ 2
  -3
  +33
  record change 2/3 to 'a'?
  (enter ? for help) [Ynesfdaq?] n
  
  @@ -5,1 +5,1 @@ 4
  -5
  +55
  record change 3/3 to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  transaction abort!
  rollback completed
  abort: edit failed: false exited with status 1
  [250]
  $ hg status

  $ HGEDITOR="\"$PYTHON\" $TESTTMP/editor.py"
  $ runsplit
  diff --git a/a b/a
  3 hunks, 3 lines changed
  examine changes to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -1,1 +1,1 @@
  -1
  +11
  record change 1/3 to 'a'?
  (enter ? for help) [Ynesfdaq?] n
  
  @@ -3,1 +3,1 @@ 2
  -3
  +33
  record change 2/3 to 'a'?
  (enter ? for help) [Ynesfdaq?] n
  
  @@ -5,1 +5,1 @@ 4
  -5
  +55
  record change 3/3 to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  EDITOR: HG: Splitting 1df0d5c5a3ab. Write commit message for the first split changeset.
  EDITOR: a2
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed a
  created new head
  diff --git a/a b/a
  2 hunks, 2 lines changed
  examine changes to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -1,1 +1,1 @@
  -1
  +11
  record change 1/2 to 'a'?
  (enter ? for help) [Ynesfdaq?] n
  
  @@ -3,1 +3,1 @@ 2
  -3
  +33
  record change 2/2 to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  EDITOR: HG: Splitting 1df0d5c5a3ab. So far it has been split into:
  EDITOR: HG: - 2:e704349bd21b tip "split 1"
  EDITOR: HG: Write commit message for the next split changeset.
  EDITOR: a2
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed a
  diff --git a/a b/a
  1 hunks, 1 lines changed
  examine changes to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -1,1 +1,1 @@
  -1
  +11
  record this change to 'a'?
  (enter ? for help) [Ynesfdaq?] y
  
  EDITOR: HG: Splitting 1df0d5c5a3ab. So far it has been split into:
  EDITOR: HG: - 2:e704349bd21b tip "split 1"
  EDITOR: HG: - 3:a09ad58faae3 "split 2"
  EDITOR: HG: Write commit message for the next split changeset.
  EDITOR: a2
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed a
  saved backup bundle to $TESTTMP/a/.hg/strip-backup/1df0d5c5a3ab-8341b760-split.hg (obsstore-off !)

#if obsstore-off
  $ hg bookmark
     r1                        0:a61bcde8c529
     r2                        3:00eebaf8d2e2
   * r3                        3:00eebaf8d2e2
  $ hg glog -p
  @  3:00eebaf8d2e2 split 3 r2 r3
  |  diff --git a/a b/a
  |  --- a/a
  |  +++ b/a
  |  @@ -1,1 +1,1 @@
  |  -1
  |  +11
  |
  o  2:a09ad58faae3 split 2
  |  diff --git a/a b/a
  |  --- a/a
  |  +++ b/a
  |  @@ -3,1 +3,1 @@
  |  -3
  |  +33
  |
  o  1:e704349bd21b split 1
  |  diff --git a/a b/a
  |  --- a/a
  |  +++ b/a
  |  @@ -5,1 +5,1 @@
  |  -5
  |  +55
  |
  o  0:a61bcde8c529 a1 r1
     diff --git a/a b/a
     new file mode 100644
     --- /dev/null
     +++ b/a
     @@ -0,0 +1,5 @@
     +1
     +2
     +3
     +4
     +5
  
#else
  $ hg bookmark
     r1                        0:a61bcde8c529
     r2                        4:00eebaf8d2e2
   * r3                        4:00eebaf8d2e2
  $ hg glog
  @  4:00eebaf8d2e2 split 3 r2 r3
  |
  o  3:a09ad58faae3 split 2
  |
  o  2:e704349bd21b split 1
  |
  o  0:a61bcde8c529 a1 r1
  
#endif

Split a head while working parent is not that head

  $ cp -R $TESTTMP/clean $TESTTMP/b
  $ cd $TESTTMP/b

  $ hg up 0 -q
  $ hg bookmark r3

  $ runsplit tip >/dev/null

#if obsstore-off
  $ hg bookmark
     r1                        0:a61bcde8c529
     r2                        3:00eebaf8d2e2
   * r3                        0:a61bcde8c529
  $ hg glog
  o  3:00eebaf8d2e2 split 3 r2
  |
  o  2:a09ad58faae3 split 2
  |
  o  1:e704349bd21b split 1
  |
  @  0:a61bcde8c529 a1 r1 r3
  
#else
  $ hg bookmark
     r1                        0:a61bcde8c529
     r2                        4:00eebaf8d2e2
   * r3                        0:a61bcde8c529
  $ hg glog
  o  4:00eebaf8d2e2 split 3 r2
  |
  o  3:a09ad58faae3 split 2
  |
  o  2:e704349bd21b split 1
  |
  @  0:a61bcde8c529 a1 r1 r3
  
#endif

Split a non-head

  $ cp -R $TESTTMP/clean $TESTTMP/c
  $ cd $TESTTMP/c
  $ echo d > d
  $ hg ci -m d1 -A d
  $ hg bookmark -i d1
  $ echo 2 >> d
  $ hg ci -m d2
  $ echo 3 >> d
  $ hg ci -m d3
  $ hg bookmark -i d3
  $ hg up '.^' -q
  $ hg bookmark d2
  $ cp -R . ../d

  $ runsplit -r 1 | grep rebasing
  rebasing 2:b5c5ea414030 d1 "d1"
  rebasing 3:f4a0a8d004cc d2 "d2"
  rebasing 4:777940761eba d3 "d3"
#if obsstore-off
  $ hg bookmark
     d1                        4:c4b449ef030e
   * d2                        5:c9dd00ab36a3
     d3                        6:19f476bc865c
     r1                        0:a61bcde8c529
     r2                        3:00eebaf8d2e2
  $ hg glog -p
  o  6:19f476bc865c d3 d3
  |  diff --git a/d b/d
  |  --- a/d
  |  +++ b/d
  |  @@ -2,0 +3,1 @@
  |  +3
  |
  @  5:c9dd00ab36a3 d2 d2
  |  diff --git a/d b/d
  |  --- a/d
  |  +++ b/d
  |  @@ -1,0 +2,1 @@
  |  +2
  |
  o  4:c4b449ef030e d1 d1
  |  diff --git a/d b/d
  |  new file mode 100644
  |  --- /dev/null
  |  +++ b/d
  |  @@ -0,0 +1,1 @@
  |  +d
  |
  o  3:00eebaf8d2e2 split 3 r2
  |  diff --git a/a b/a
  |  --- a/a
  |  +++ b/a
  |  @@ -1,1 +1,1 @@
  |  -1
  |  +11
  |
  o  2:a09ad58faae3 split 2
  |  diff --git a/a b/a
  |  --- a/a
  |  +++ b/a
  |  @@ -3,1 +3,1 @@
  |  -3
  |  +33
  |
  o  1:e704349bd21b split 1
  |  diff --git a/a b/a
  |  --- a/a
  |  +++ b/a
  |  @@ -5,1 +5,1 @@
  |  -5
  |  +55
  |
  o  0:a61bcde8c529 a1 r1
     diff --git a/a b/a
     new file mode 100644
     --- /dev/null
     +++ b/a
     @@ -0,0 +1,5 @@
     +1
     +2
     +3
     +4
     +5
  
#else
  $ hg bookmark
     d1                        8:c4b449ef030e
   * d2                        9:c9dd00ab36a3
     d3                        10:19f476bc865c
     r1                        0:a61bcde8c529
     r2                        7:00eebaf8d2e2
  $ hg glog
  o  10:19f476bc865c d3 d3
  |
  @  9:c9dd00ab36a3 d2 d2
  |
  o  8:c4b449ef030e d1 d1
  |
  o  7:00eebaf8d2e2 split 3 r2
  |
  o  6:a09ad58faae3 split 2
  |
  o  5:e704349bd21b split 1
  |
  o  0:a61bcde8c529 a1 r1
  
#endif

Split a non-head without rebase

  $ cd $TESTTMP/d
#if obsstore-off
  $ runsplit -r 1 --no-rebase
  abort: cannot split changeset, as that will orphan 3 descendants
  (see 'hg help evolution.instability')
  [10]
#else
  $ runsplit -r 1 --no-rebase >/dev/null
  3 new orphan changesets
  $ hg bookmark
     d1                        2:b5c5ea414030
   * d2                        3:f4a0a8d004cc
     d3                        4:777940761eba
     r1                        0:a61bcde8c529
     r2                        7:00eebaf8d2e2

  $ hg glog
  o  7:00eebaf8d2e2 split 3 r2
  |
  o  6:a09ad58faae3 split 2
  |
  o  5:e704349bd21b split 1
  |
  | *  4:777940761eba d3 d3
  | |
  | @  3:f4a0a8d004cc d2 d2
  | |
  | *  2:b5c5ea414030 d1 d1
  | |
  | x  1:1df0d5c5a3ab a2
  |/
  o  0:a61bcde8c529 a1 r1
  
#endif

Split a non-head with obsoleted descendants

#if obsstore-on
  $ hg init $TESTTMP/e
  $ cd $TESTTMP/e
  $ hg debugdrawdag <<'EOS'
  >   H I   J
  >   | |   |
  >   F G1 G2  # amend: G1 -> G2
  >   | |  /   # prune: F
  >   C D E
  >    \|/
  >     B
  >     |
  >     A
  > EOS
  2 new orphan changesets
  $ eval `hg tags -T '{tag}={node}\n'`
  $ rm .hg/localtags
  $ hg split $B --config experimental.evolution=createmarkers
  abort: cannot split changeset, as that will orphan 4 descendants
  (see 'hg help evolution.instability')
  [10]
  $ cat > $TESTTMP/messages <<EOF
  > Split B
  > EOF
  $ cat <<EOF | hg split $B
  > y
  > y
  > EOF
  diff --git a/B b/B
  new file mode 100644
  examine changes to 'B'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -0,0 +1,1 @@
  +B
  \ No newline at end of file
  record this change to 'B'?
  (enter ? for help) [Ynesfdaq?] y
  
  EDITOR: HG: Splitting 112478962961. Write commit message for the first split changeset.
  EDITOR: B
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: added B
  created new head
  rebasing 2:26805aba1e60 "C"
  rebasing 3:be0ef73c17ad "D"
  rebasing 4:49cb92066bfd "E"
  rebasing 7:97a6268cc7ef "G2"
  rebasing 10:e2f1e425c0db "J"
  $ hg glog -r 'sort(all(), topo)'
  o  16:556c085f8b52 J
  |
  o  15:8761f6c9123f G2
  |
  o  14:a7aeffe59b65 E
  |
  | o  13:e1e914ede9ab D
  |/
  | o  12:01947e9b98aa C
  |/
  o  11:0947baa74d47 Split B
  |
  | *  9:88ede1d5ee13 I
  | |
  | x  6:af8cbf225b7b G1
  | |
  | x  3:be0ef73c17ad D
  | |
  | | *  8:74863e5b5074 H
  | | |
  | | x  5:ee481a2a1e69 F
  | | |
  | | x  2:26805aba1e60 C
  | |/
  | x  1:112478962961 B
  |/
  o  0:426bada5c675 A
  
#endif

Preserve secret phase in split

  $ cp -R $TESTTMP/clean $TESTTMP/phases1
  $ cd $TESTTMP/phases1
  $ hg phase --secret -fr tip
  $ hg log -T '{short(node)} {phase}\n'
  1df0d5c5a3ab secret
  a61bcde8c529 draft
  $ runsplit tip >/dev/null
  $ hg log -T '{short(node)} {phase}\n'
  00eebaf8d2e2 secret
  a09ad58faae3 secret
  e704349bd21b secret
  a61bcde8c529 draft

Do not move things to secret even if phases.new-commit=secret

  $ cp -R $TESTTMP/clean $TESTTMP/phases2
  $ cd $TESTTMP/phases2
  $ cat >> .hg/hgrc <<EOF
  > [phases]
  > new-commit=secret
  > EOF
  $ hg log -T '{short(node)} {phase}\n'
  1df0d5c5a3ab draft
  a61bcde8c529 draft
  $ runsplit tip >/dev/null
  $ hg log -T '{short(node)} {phase}\n'
  00eebaf8d2e2 draft
  a09ad58faae3 draft
  e704349bd21b draft
  a61bcde8c529 draft

`hg split` with ignoreblanklines=1 does not infinite loop

  $ mkdir $TESTTMP/f
  $ hg init $TESTTMP/f/a
  $ cd $TESTTMP/f/a
  $ printf '1\n2\n3\n4\n5\n' > foo
  $ cp foo bar
  $ hg ci -qAm initial
  $ printf '1\n\n2\n3\ntest\n4\n5\n' > bar
  $ printf '1\n2\n3\ntest\n4\n5\n' > foo
  $ hg ci -qm splitme
  $ cat > $TESTTMP/messages <<EOF
  > split 1
  > --
  > split 2
  > EOF
  $ printf 'f\nn\nf\n' | hg --config extensions.split= --config diff.ignoreblanklines=1 split
  diff --git a/bar b/bar
  2 hunks, 2 lines changed
  examine changes to 'bar'?
  (enter ? for help) [Ynesfdaq?] f
  
  diff --git a/foo b/foo
  1 hunks, 1 lines changed
  examine changes to 'foo'?
  (enter ? for help) [Ynesfdaq?] n
  
  EDITOR: HG: Splitting dd3c45017cbf. Write commit message for the first split changeset.
  EDITOR: splitme
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed bar
  created new head
  diff --git a/foo b/foo
  1 hunks, 1 lines changed
  examine changes to 'foo'?
  (enter ? for help) [Ynesfdaq?] f
  
  EDITOR: HG: Splitting dd3c45017cbf. So far it has been split into:
  EDITOR: HG: - 2:f205aea1c624 tip "split 1"
  EDITOR: HG: Write commit message for the next split changeset.
  EDITOR: splitme
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed foo
  saved backup bundle to $TESTTMP/f/a/.hg/strip-backup/dd3c45017cbf-463441b5-split.hg (obsstore-off !)

Let's try that again, with a slightly different set of patches, to ensure that
the ignoreblanklines thing isn't somehow position dependent.

  $ hg init $TESTTMP/f/b
  $ cd $TESTTMP/f/b
  $ printf '1\n2\n3\n4\n5\n' > foo
  $ cp foo bar
  $ hg ci -qAm initial
  $ printf '1\n2\n3\ntest\n4\n5\n' > bar
  $ printf '1\n2\n3\ntest\n4\n\n5\n' > foo
  $ hg ci -qm splitme
  $ cat > $TESTTMP/messages <<EOF
  > split 1
  > --
  > split 2
  > EOF
  $ printf 'f\nn\nf\n' | hg --config extensions.split= --config diff.ignoreblanklines=1 split
  diff --git a/bar b/bar
  1 hunks, 1 lines changed
  examine changes to 'bar'?
  (enter ? for help) [Ynesfdaq?] f
  
  diff --git a/foo b/foo
  2 hunks, 2 lines changed
  examine changes to 'foo'?
  (enter ? for help) [Ynesfdaq?] n
  
  EDITOR: HG: Splitting 904c80b40a4a. Write commit message for the first split changeset.
  EDITOR: splitme
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed bar
  created new head
  diff --git a/foo b/foo
  2 hunks, 2 lines changed
  examine changes to 'foo'?
  (enter ? for help) [Ynesfdaq?] f
  
  EDITOR: HG: Splitting 904c80b40a4a. So far it has been split into:
  EDITOR: HG: - 2:ffecf40fa954 tip "split 1"
  EDITOR: HG: Write commit message for the next split changeset.
  EDITOR: splitme
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed foo
  saved backup bundle to $TESTTMP/f/b/.hg/strip-backup/904c80b40a4a-47fb907f-split.hg (obsstore-off !)


Testing the case in split when commiting flag-only file changes (issue5864)
---------------------------------------------------------------------------
  $ hg init $TESTTMP/issue5864
  $ cd $TESTTMP/issue5864
  $ echo foo > foo
  $ hg add foo
  $ hg ci -m "initial"
  $ hg import -q --bypass -m "make executable" - <<EOF
  > diff --git a/foo b/foo
  > old mode 100644
  > new mode 100755
  > EOF
  $ hg up -q

  $ hg glog
  @  1:3a2125f0f4cb make executable
  |
  o  0:51f273a58d82 initial
  

#if no-windows
  $ cat > $TESTTMP/messages <<EOF
  > split 1
  > EOF
  $ printf 'y\n' | hg split
  diff --git a/foo b/foo
  old mode 100644
  new mode 100755
  examine changes to 'foo'?
  (enter ? for help) [Ynesfdaq?] y
  
  EDITOR: HG: Splitting 3a2125f0f4cb. Write commit message for the first split changeset.
  EDITOR: make executable
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed foo
  created new head
  saved backup bundle to $TESTTMP/issue5864/.hg/strip-backup/3a2125f0f4cb-629e4432-split.hg (obsstore-off !)

  $ hg log -G -T "{node|short} {desc}\n"
  @  b154670c87da split 1
  |
  o  51f273a58d82 initial
  
#else

TODO: Fix this on Windows. See issue 2020 and 5883

  $ printf 'y\ny\ny\n' | hg split
  abort: cannot split an empty revision
  [10]
#endif

Test that splitting moves works properly (issue5723)
----------------------------------------------------

  $ hg init $TESTTMP/issue5723-mv
  $ cd $TESTTMP/issue5723-mv
  $ printf '1\n2\n' > file
  $ hg ci -qAm initial
  $ hg mv file file2
  $ printf 'a\nb\n1\n2\n3\n4\n' > file2
  $ cat > $TESTTMP/messages <<EOF
  > split1, keeping only the numbered lines
  > --
  > split2, keeping the lettered lines
  > EOF
  $ hg ci -m 'move and modify'
  $ printf 'y\nn\na\na\n' | hg split
  diff --git a/file b/file2
  rename from file
  rename to file2
  2 hunks, 4 lines changed
  examine changes to 'file' and 'file2'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -0,0 +1,2 @@
  +a
  +b
  record change 1/2 to 'file2'?
  (enter ? for help) [Ynesfdaq?] n
  
  @@ -2,0 +5,2 @@ 2
  +3
  +4
  record change 2/2 to 'file2'?
  (enter ? for help) [Ynesfdaq?] a
  
  EDITOR: HG: Splitting 8c42fa635116. Write commit message for the first split changeset.
  EDITOR: move and modify
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: added file2
  EDITOR: HG: removed file
  created new head
  diff --git a/file2 b/file2
  1 hunks, 2 lines changed
  examine changes to 'file2'?
  (enter ? for help) [Ynesfdaq?] a
  
  EDITOR: HG: Splitting 8c42fa635116. So far it has been split into:
  EDITOR: HG: - 2:478be2a70c27 tip "split1, keeping only the numbered lines"
  EDITOR: HG: Write commit message for the next split changeset.
  EDITOR: move and modify
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed file2
  saved backup bundle to $TESTTMP/issue5723-mv/.hg/strip-backup/8c42fa635116-a38044d4-split.hg (obsstore-off !)
  $ hg log -T '{desc}: {files%"{file} "}\n'
  split2, keeping the lettered lines: file2 
  split1, keeping only the numbered lines: file file2 
  initial: file 
  $ cat file2
  a
  b
  1
  2
  3
  4
  $ hg cat -r ".^" file2
  1
  2
  3
  4
  $ hg cat -r . file2
  a
  b
  1
  2
  3
  4


Test that splitting copies works properly (issue5723)
----------------------------------------------------

  $ hg init $TESTTMP/issue5723-cp
  $ cd $TESTTMP/issue5723-cp
  $ printf '1\n2\n' > file
  $ hg ci -qAm initial
  $ hg cp file file2
  $ printf 'a\nb\n1\n2\n3\n4\n' > file2
Also modify 'file' to prove that the changes aren't being pulled in
accidentally.
  $ printf 'this is the new contents of "file"' > file
  $ cat > $TESTTMP/messages <<EOF
  > split1, keeping "file" and only the numbered lines in file2
  > --
  > split2, keeping the lettered lines in file2
  > EOF
  $ hg ci -m 'copy file->file2, modify both'
  $ printf 'f\ny\nn\na\na\n' | hg split
  diff --git a/file b/file
  1 hunks, 2 lines changed
  examine changes to 'file'?
  (enter ? for help) [Ynesfdaq?] f
  
  diff --git a/file b/file2
  copy from file
  copy to file2
  2 hunks, 4 lines changed
  examine changes to 'file' and 'file2'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -0,0 +1,2 @@
  +a
  +b
  record change 2/3 to 'file2'?
  (enter ? for help) [Ynesfdaq?] n
  
  @@ -2,0 +5,2 @@ 2
  +3
  +4
  record change 3/3 to 'file2'?
  (enter ? for help) [Ynesfdaq?] a
  
  EDITOR: HG: Splitting 41c861dfa61e. Write commit message for the first split changeset.
  EDITOR: copy file->file2, modify both
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: added file2
  EDITOR: HG: changed file
  created new head
  diff --git a/file2 b/file2
  1 hunks, 2 lines changed
  examine changes to 'file2'?
  (enter ? for help) [Ynesfdaq?] a
  
  EDITOR: HG: Splitting 41c861dfa61e. So far it has been split into:
  EDITOR: HG: - 2:4b19e06610eb tip "split1, keeping "file" and only the numbered lines in file2"
  EDITOR: HG: Write commit message for the next split changeset.
  EDITOR: copy file->file2, modify both
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed file2
  saved backup bundle to $TESTTMP/issue5723-cp/.hg/strip-backup/41c861dfa61e-467e8d3c-split.hg (obsstore-off !)
  $ hg log -T '{desc}: {files%"{file} "}\n'
  split2, keeping the lettered lines in file2: file2 
  split1, keeping "file" and only the numbered lines in file2: file file2 
  initial: file 
  $ cat file2
  a
  b
  1
  2
  3
  4
  $ hg cat -r ".^" file2
  1
  2
  3
  4
  $ hg cat -r . file2
  a
  b
  1
  2
  3
  4

Test that color codes don't end up in the commit message template
----------------------------------------------------

  $ hg init $TESTTMP/colorless
  $ cd $TESTTMP/colorless
  $ echo 1 > file1
  $ echo 1 > file2
  $ hg ci -qAm initial
  $ echo 2 > file1
  $ echo 2 > file2
  $ cat > $TESTTMP/messages <<EOF
  > split1, modifying file1
  > --
  > split2, modifying file2
  > EOF
  $ hg ci
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed file1
  EDITOR: HG: changed file2
  $ printf 'f\nn\na\n' | hg split --color=debug \
  > --config command-templates.oneline-summary='{label("rev", rev)} {desc}'
  [diff.diffline|diff --git a/file1 b/file1]
  1 hunks, 1 lines changed
  [ ui.prompt|examine changes to 'file1'?
  (enter ? for help) [Ynesfdaq?]] [ ui.promptecho|f]
  
  [diff.diffline|diff --git a/file2 b/file2]
  1 hunks, 1 lines changed
  [ ui.prompt|examine changes to 'file2'?
  (enter ? for help) [Ynesfdaq?]] [ ui.promptecho|n]
  
  EDITOR: HG: Splitting 6432c65c3078. Write commit message for the first split changeset.
  EDITOR: split1, modifying file1
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed file1
  [ ui.status|created new head]
  [diff.diffline|diff --git a/file2 b/file2]
  1 hunks, 1 lines changed
  [ ui.prompt|examine changes to 'file2'?
  (enter ? for help) [Ynesfdaq?]] [ ui.promptecho|a]
  
  EDITOR: HG: Splitting 6432c65c3078. So far it has been split into:
  EDITOR: HG: - 2 split2, modifying file2
  EDITOR: HG: Write commit message for the next split changeset.
  EDITOR: split1, modifying file1
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: changed file2
  [ ui.warning|transaction abort!]
  [ ui.warning|rollback completed]
  [ ui.error|abort: empty commit message]
  [10]

Test that creating an empty split or "no-op"
(identical to original) commit doesn't cause chaos
--------------------------------------------------

  $ hg init $TESTTMP/noop
  $ cd $TESTTMP/noop
  $ echo r0 > r0
  $ hg ci -qAm r0
  $ hg phase -p
  $ echo foo > foo
  $ hg ci -qAm foo
  $ hg log -G -T'{phase} {rev}:{node|short} {desc}'
  @  draft 1:ae694b2901bb foo
  |
  o  public 0:222799e2f90b r0
  
  $ printf 'd\na\n' | HGEDITOR=cat hg split || true
  diff --git a/foo b/foo
  new file mode 100644
  examine changes to 'foo'?
  (enter ? for help) [Ynesfdaq?] d
  
  no changes to record
  diff --git a/foo b/foo
  new file mode 100644
  examine changes to 'foo'?
  (enter ? for help) [Ynesfdaq?] a
  
  HG: Splitting ae694b2901bb. Write commit message for the first split changeset.
  foo
  
  
  HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  HG: Leave message empty to abort commit.
  HG: --
  HG: user: test
  HG: branch 'default'
  HG: added foo
  warning: commit already existed in the repository!
  $ hg log -G -T'{phase} {rev}:{node|short} {desc}'
  @  draft 1:ae694b2901bb foo
  |
  o  public 0:222799e2f90b r0
  

Now try the same thing but modifying the message so we don't trigger the
identical changeset failures

  $ hg init $TESTTMP/noop2
  $ cd $TESTTMP/noop2
  $ echo r0 > r0
  $ hg ci -qAm r0
  $ hg phase -p
  $ echo foo > foo
  $ hg ci -qAm foo
  $ hg log -G -T'{phase} {rev}:{node|short} {desc}'
  @  draft 1:ae694b2901bb foo
  |
  o  public 0:222799e2f90b r0
  
  $ cat > $TESTTMP/messages <<EOF
  > message1
  > EOF
  $ printf 'd\na\n' | HGEDITOR="\"$PYTHON\" $TESTTMP/editor.py" hg split
  diff --git a/foo b/foo
  new file mode 100644
  examine changes to 'foo'?
  (enter ? for help) [Ynesfdaq?] d
  
  no changes to record
  diff --git a/foo b/foo
  new file mode 100644
  examine changes to 'foo'?
  (enter ? for help) [Ynesfdaq?] a
  
  EDITOR: HG: Splitting ae694b2901bb. Write commit message for the first split changeset.
  EDITOR: foo
  EDITOR: 
  EDITOR: 
  EDITOR: HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  EDITOR: HG: Leave message empty to abort commit.
  EDITOR: HG: --
  EDITOR: HG: user: test
  EDITOR: HG: branch 'default'
  EDITOR: HG: added foo
  created new head
  saved backup bundle to $TESTTMP/noop2/.hg/strip-backup/ae694b2901bb-28e0b457-split.hg (obsstore-off !)
  $ hg log -G -T'{phase} {rev}:{node|short} {desc}'
  @  draft 1:de675559d3f9 message1 (obsstore-off !)
  @  draft 2:de675559d3f9 message1 (obsstore-on !)
  |
  o  public 0:222799e2f90b r0
  
#if obsstore-on
  $ hg debugobsolete
  ae694b2901bb8b0f8c4b5e075ddec0d63468d57a de675559d3f93ffc822c6eb7490e5c73033f17c7 0 * (glob)
#endif

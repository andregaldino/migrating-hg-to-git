#require curses

Set up a repo

  $ cp $HGRCPATH $HGRCPATH.pretest
  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interactive = true
  > interface = curses
  > [experimental]
  > crecordtest = testModeCommands
  > EOF

Record with noeol at eof (issue5268)
  $ hg init noeol
  $ cd noeol
  $ printf '0' > a
  $ printf '0\n' > b
  $ hg ci -Aqm initial
  $ printf '1\n0' > a
  $ printf '1\n0\n' > b
  $ cat <<EOF >testModeCommands
  > c
  > EOF
  $ HGEDITOR="\"sh\" \"`pwd`/editor.sh\"" hg commit  -i -m "add hunks" -d "0 0"
  $ cd ..

Normal repo
  $ hg init a
  $ cd a

Committing some changes but stopping on the way

  $ echo "a" > a
  $ hg add a
  $ cat <<EOF >testModeCommands
  > x
  > c
  > EOF
  $ hg commit -i  -m "a" -d "0 0"
  no changes to record
  [1]
  $ hg tip
  changeset:   -1:000000000000
  tag:         tip
  user:        
  date:        Thu Jan 01 00:00:00 1970 +0000
  

Committing some changes

  $ cat <<EOF >testModeCommands
  > c
  > EOF
  $ hg commit -i  -m "a" -d "0 0"
  $ hg tip
  changeset:   0:cb9a9f314b8b
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     a
  
Check that commit -i works with no changes
  $ hg commit -i
  no changes to record
  [1]

Committing only one file

  $ echo "a" >> a
  >>> open('b', 'wb').write(b"1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n") and None
  $ hg add b
  $ cat <<EOF >testModeCommands
  > x
  > KEY_DOWN
  > c
  > EOF
  $ hg commit -i  -m "one file" -d "0 0"
  $ hg tip
  changeset:   1:fb2705a663ea
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     one file
  
  $ hg cat -r tip a
  a
  $ cat a
  a
  a

Committing only one hunk while aborting edition of hunk

- Untoggle all the hunks, go down to the second file
- unfold it
- go down to second hunk (1 for the first hunk, 1 for the first hunkline, 1 for the second hunk, 1 for the second hunklike)
- toggle the second hunk
- toggle all lines twice (to check that it does nothing)
- edit the hunk and quit the editor immediately with non-zero status
- commit

  $ printf "printf 'editor ran\n'; exit 1" > editor.sh
  $ echo "x" > c
  $ cat b >> c
  $ echo "y" >> c
  $ mv c b
  $ cat <<EOF >testModeCommands
  > A
  > KEY_DOWN
  > f
  > KEY_DOWN
  > KEY_DOWN
  > KEY_DOWN
  > KEY_DOWN
  > x
  > a
  > a
  > e
  > c
  > EOF
  $ HGEDITOR="\"sh\" \"`pwd`/editor.sh\"" hg commit -i  -m "one hunk" -d "0 0"
  editor ran
  $ rm editor.sh
  $ hg tip
  changeset:   2:7d10dfe755a8
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     one hunk
  
  $ hg cat -r tip b
  1
  2
  3
  4
  5
  6
  7
  8
  9
  10
  y
  $ cat b
  x
  1
  2
  3
  4
  5
  6
  7
  8
  9
  10
  y
  $ hg commit -m "other hunks"
  $ hg tip
  changeset:   3:a6735021574d
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     other hunks
  
  $ hg cat -r tip b
  x
  1
  2
  3
  4
  5
  6
  7
  8
  9
  10
  y

Newly added files can be selected with the curses interface

  $ hg update -C .
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo "hello" > x
  $ hg add x
  $ cat <<EOF >testModeCommands
  > x
  > x
  > c
  > EOF
  $ hg st
  A x
  ? testModeCommands
  $ hg commit -i  -m "newly added file" -d "0 0"
  $ hg st
  ? testModeCommands

Test toggling all selections works

- Change one line
- Add an extra line at the end
- Unselect all
- Select the extra line at the end
- Toggle all selections (so the extra line at the is unselected and the modified line is selected)
- Commit

  $ echo "hello world" > x
  $ echo "goodbye world" >> x
  $ hg diff
  diff -r 2b0e9be4d336 x
  --- a/x	Thu Jan 01 00:00:00 1970 +0000
  +++ b/x	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,2 @@
  -hello
  +hello world
  +goodbye world
  $ cat <<EOF >testModeCommands
  > f
  > j
  > x
  > j
  > j
  > j
  > x
  > a
  > c
  > EOF
  $ hg commit -i --amend  -m "newly added file" -d "0 0" x
  saved backup bundle to $TESTTMP/a/.hg/strip-backup/2b0e9be4d336-3cf0bc8c-amend.hg
  $ hg rev x --no-backup
  $ hg diff -c .
  diff -r a6735021574d -r c1d239d165ae x
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/x	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +hello world

Make file empty
  $ printf "" > x
  $ cat <<EOF >testModeCommands
  > c
  > EOF
  $ hg ci -i -m emptify -d "0 0"
  $ hg update -C '.^' -q

Editing a hunk puts you back on that hunk when done editing (issue5041)
To do that, we change two lines in a file, pretend to edit the second line,
exit, toggle the line selected at the end of the edit and commit.
The first line should be recorded if we were put on the second line at the end
of the edit.

  $ hg update -C .
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo "foo" > x
  $ echo "hello world" >> x
  $ echo "bar" >> x
  $ cat <<EOF >testModeCommands
  > f
  > KEY_DOWN
  > KEY_DOWN
  > KEY_DOWN
  > KEY_DOWN
  > e
  > x
  > c
  > EOF
  $ printf "printf 'editor ran\n'; exit 0" > editor.sh
  $ HGEDITOR="\"sh\" \"`pwd`/editor.sh\"" hg commit  -i -m "edit hunk" -d "0 0" -q
  editor ran
  $ hg cat -r . x
  foo
  hello world

Testing the review option. The entire final filtered patch should show
up in the editor and be editable. We will unselect the second file and
the first hunk of the third file. During review, we will decide that
"lower" sounds better than "bottom", and the final commit should
reflect this edition.

  $ hg update -C .
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo "top" > c
  $ cat x >> c
  $ echo "bottom" >> c
  $ mv c x
  $ echo "third a" >> a
  $ echo "we will unselect this" >> b

  $ cat > editor.sh <<EOF
  > cat "\$1"
  > cat "\$1" | sed s/bottom/lower/ > tmp
  > mv tmp "\$1"
  > EOF
  $ cat > testModeCommands <<EOF
  > KEY_DOWN
  > x
  > KEY_DOWN
  > f
  > KEY_DOWN
  > x
  > R
  > EOF

  $ HGEDITOR="\"sh\" \"`pwd`/editor.sh\"" hg commit  -i -m "review hunks" -d "0 0"
  # To remove '-' lines, make them ' ' lines (context).
  # To remove '+' lines, delete them.
  # Lines starting with # will be removed from the patch.
  #
  # If the patch applies cleanly, the edited patch will immediately
  # be finalised. If it does not apply cleanly, rejects files will be
  # generated. You can use those when you try again.
  diff --git a/a b/a
  --- a/a
  +++ b/a
  @@ -1,2 +1,3 @@
   a
   a
  +third a
  diff --git a/x b/x
  --- a/x
  +++ b/x
  @@ -1,2 +1,3 @@
   foo
   hello world
  +bottom

  $ hg cat -r . a
  a
  a
  third a

  $ hg cat -r . b
  x
  1
  2
  3
  4
  5
  6
  7
  8
  9
  10
  y

  $ hg cat -r . x
  foo
  hello world
  lower

Test range select: unselect 3, 5, and 6, reselect 5, then go back up to 2 and
press 'X', unselecting (because 2 is currently selected) 5 (because it's the
start of the range) and 4, leaving 3 unselected.

  $ hg init $TESTTMP/range_select
  $ cd $TESTTMP/range_select
  >>> open('range_select', 'wb').write(b"1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n") and None
  $ hg add range_select
  $ cat <<EOF >testModeCommands
  > KEY_RIGHT
  > KEY_RIGHT
  > KEY_DOWN
  > KEY_DOWN
  > KEY_ENTER
  > KEY_DOWN
  > KEY_ENTER
  > x
  > KEY_UP
  > x
  > KEY_UP
  > KEY_UP
  > KEY_UP
  > X
  > c
  > EOF
  $ hg commit -i -m "range_select" -d "0 0"
  $ hg cat -r tip range_select
  1
  7
  8
  9
  10
  $ cat range_select
  1
  2
  3
  4
  5
  6
  7
  8
  9
  10

Check ui.interface logic for the chunkselector

The default interface is text
  $ cp $HGRCPATH.pretest $HGRCPATH
  $ chunkselectorinterface() {
  > "$PYTHON" <<EOF
  > from mercurial import hg, pycompat, ui;\
  > repo = hg.repository(ui.ui.load(), b".");\
  > print(pycompat.sysstr(repo.ui.interface(b"chunkselector")))
  > EOF
  > }
  $ chunkselectorinterface
  text

If only the default is set, we'll use that for the feature, too
  $ cp $HGRCPATH.pretest $HGRCPATH
  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interface = curses
  > EOF
  $ chunkselectorinterface
  curses

If TERM=dumb, we use text, even if the config says curses
  $ chunkselectorinterface
  curses
  $ TERM=dumb chunkselectorinterface
  text
(Something is keeping TERM=dumb in the environment unless I do this, it's not
scoped to just that previous command like in many shells)
  $ TERM=xterm chunkselectorinterface
  curses

It is possible to override the default interface with a feature specific
interface
  $ cp $HGRCPATH.pretest $HGRCPATH
  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interface = text
  > interface.chunkselector = curses
  > EOF

  $ chunkselectorinterface
  curses

  $ cp $HGRCPATH.pretest $HGRCPATH
  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interface = curses
  > interface.chunkselector = text
  > EOF

  $ chunkselectorinterface
  text

If a bad interface name is given, we use the default value (with a nice
error message to suggest that the configuration needs to be fixed)

  $ cp $HGRCPATH.pretest $HGRCPATH
  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interface = blah
  > EOF
  $ chunkselectorinterface
  invalid value for ui.interface: blah (using text)
  text

  $ cp $HGRCPATH.pretest $HGRCPATH
  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interface = curses
  > interface.chunkselector = blah
  > EOF
  $ chunkselectorinterface
  invalid value for ui.interface.chunkselector: blah (using curses)
  curses

  $ cp $HGRCPATH.pretest $HGRCPATH
  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interface = blah
  > interface.chunkselector = curses
  > EOF
  $ chunkselectorinterface
  invalid value for ui.interface: blah
  curses

  $ cp $HGRCPATH.pretest $HGRCPATH
  $ cat <<EOF >> $HGRCPATH
  > [ui]
  > interface = blah
  > interface.chunkselector = blah
  > EOF
  $ chunkselectorinterface
  invalid value for ui.interface: blah
  invalid value for ui.interface.chunkselector: blah (using text)
  text

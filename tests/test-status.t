#testcases dirstate-v1 dirstate-v2

#if dirstate-v2
  $ cat >> $HGRCPATH << EOF
  > [format]
  > exp-rc-dirstate-v2=1
  > [storage]
  > dirstate-v2.slow-path=allow
  > EOF
#endif

TODO: fix rhg bugs that make this test fail when status is enabled
  $ unset RHG_STATUS


  $ hg init repo1
  $ cd repo1
  $ mkdir a b a/1 b/1 b/2
  $ touch in_root a/in_a b/in_b a/1/in_a_1 b/1/in_b_1 b/2/in_b_2

hg status in repo root:

  $ hg status
  ? a/1/in_a_1
  ? a/in_a
  ? b/1/in_b_1
  ? b/2/in_b_2
  ? b/in_b
  ? in_root

hg status . in repo root:

  $ hg status .
  ? a/1/in_a_1
  ? a/in_a
  ? b/1/in_b_1
  ? b/2/in_b_2
  ? b/in_b
  ? in_root

  $ hg status --cwd a
  ? a/1/in_a_1
  ? a/in_a
  ? b/1/in_b_1
  ? b/2/in_b_2
  ? b/in_b
  ? in_root
  $ hg status --cwd a .
  ? 1/in_a_1
  ? in_a
  $ hg status --cwd a ..
  ? 1/in_a_1
  ? in_a
  ? ../b/1/in_b_1
  ? ../b/2/in_b_2
  ? ../b/in_b
  ? ../in_root

  $ hg status --cwd b
  ? a/1/in_a_1
  ? a/in_a
  ? b/1/in_b_1
  ? b/2/in_b_2
  ? b/in_b
  ? in_root
  $ hg status --cwd b .
  ? 1/in_b_1
  ? 2/in_b_2
  ? in_b
  $ hg status --cwd b ..
  ? ../a/1/in_a_1
  ? ../a/in_a
  ? 1/in_b_1
  ? 2/in_b_2
  ? in_b
  ? ../in_root

  $ hg status --cwd a/1
  ? a/1/in_a_1
  ? a/in_a
  ? b/1/in_b_1
  ? b/2/in_b_2
  ? b/in_b
  ? in_root
  $ hg status --cwd a/1 .
  ? in_a_1
  $ hg status --cwd a/1 ..
  ? in_a_1
  ? ../in_a

  $ hg status --cwd b/1
  ? a/1/in_a_1
  ? a/in_a
  ? b/1/in_b_1
  ? b/2/in_b_2
  ? b/in_b
  ? in_root
  $ hg status --cwd b/1 .
  ? in_b_1
  $ hg status --cwd b/1 ..
  ? in_b_1
  ? ../2/in_b_2
  ? ../in_b

  $ hg status --cwd b/2
  ? a/1/in_a_1
  ? a/in_a
  ? b/1/in_b_1
  ? b/2/in_b_2
  ? b/in_b
  ? in_root
  $ hg status --cwd b/2 .
  ? in_b_2
  $ hg status --cwd b/2 ..
  ? ../1/in_b_1
  ? in_b_2
  ? ../in_b

combining patterns with root and patterns without a root works

  $ hg st a/in_a re:.*b$
  ? a/in_a
  ? b/in_b

tweaking defaults works
  $ hg status --cwd a --config ui.tweakdefaults=yes
  ? 1/in_a_1
  ? in_a
  ? ../b/1/in_b_1
  ? ../b/2/in_b_2
  ? ../b/in_b
  ? ../in_root
  $ HGPLAIN=1 hg status --cwd a --config ui.tweakdefaults=yes
  ? a/1/in_a_1 (glob)
  ? a/in_a (glob)
  ? b/1/in_b_1 (glob)
  ? b/2/in_b_2 (glob)
  ? b/in_b (glob)
  ? in_root
  $ HGPLAINEXCEPT=tweakdefaults hg status --cwd a --config ui.tweakdefaults=yes
  ? 1/in_a_1
  ? in_a
  ? ../b/1/in_b_1
  ? ../b/2/in_b_2
  ? ../b/in_b
  ? ../in_root (glob)

relative paths can be requested

  $ hg status --cwd a --config ui.relative-paths=yes
  ? 1/in_a_1
  ? in_a
  ? ../b/1/in_b_1
  ? ../b/2/in_b_2
  ? ../b/in_b
  ? ../in_root

  $ hg status --cwd a . --config ui.relative-paths=legacy
  ? 1/in_a_1
  ? in_a
  $ hg status --cwd a . --config ui.relative-paths=no
  ? a/1/in_a_1
  ? a/in_a

commands.status.relative overrides ui.relative-paths

  $ cat >> $HGRCPATH <<EOF
  > [ui]
  > relative-paths = False
  > [commands]
  > status.relative = True
  > EOF
  $ hg status --cwd a
  ? 1/in_a_1
  ? in_a
  ? ../b/1/in_b_1
  ? ../b/2/in_b_2
  ? ../b/in_b
  ? ../in_root
  $ HGPLAIN=1 hg status --cwd a
  ? a/1/in_a_1 (glob)
  ? a/in_a (glob)
  ? b/1/in_b_1 (glob)
  ? b/2/in_b_2 (glob)
  ? b/in_b (glob)
  ? in_root

if relative paths are explicitly off, tweakdefaults doesn't change it
  $ cat >> $HGRCPATH <<EOF
  > [commands]
  > status.relative = False
  > EOF
  $ hg status --cwd a --config ui.tweakdefaults=yes
  ? a/1/in_a_1
  ? a/in_a
  ? b/1/in_b_1
  ? b/2/in_b_2
  ? b/in_b
  ? in_root

  $ cd ..

  $ hg init repo2
  $ cd repo2
  $ touch modified removed deleted ignored
  $ echo "^ignored$" > .hgignore
  $ hg ci -A -m 'initial checkin'
  adding .hgignore
  adding deleted
  adding modified
  adding removed
  $ touch modified added unknown ignored
  $ hg add added
  $ hg remove removed
  $ rm deleted

hg status:

  $ hg status
  A added
  R removed
  ! deleted
  ? unknown

hg status modified added removed deleted unknown never-existed ignored:

  $ hg status modified added removed deleted unknown never-existed ignored
  never-existed: * (glob)
  A added
  R removed
  ! deleted
  ? unknown

  $ hg copy modified copied

hg status -C:

  $ hg status -C
  A added
  A copied
    modified
  R removed
  ! deleted
  ? unknown

hg status -A:

  $ hg status -A
  A added
  A copied
    modified
  R removed
  ! deleted
  ? unknown
  I ignored
  C .hgignore
  C modified

  $ hg status -A -T '{status} {path} {node|shortest}\n'
  A added ffff
  A copied ffff
  R removed ffff
  ! deleted ffff
  ? unknown ffff
  I ignored ffff
  C .hgignore ffff
  C modified ffff

  $ hg status -A -Tjson
  [
   {
    "itemtype": "file",
    "path": "added",
    "status": "A"
   },
   {
    "itemtype": "file",
    "path": "copied",
    "source": "modified",
    "status": "A"
   },
   {
    "itemtype": "file",
    "path": "removed",
    "status": "R"
   },
   {
    "itemtype": "file",
    "path": "deleted",
    "status": "!"
   },
   {
    "itemtype": "file",
    "path": "unknown",
    "status": "?"
   },
   {
    "itemtype": "file",
    "path": "ignored",
    "status": "I"
   },
   {
    "itemtype": "file",
    "path": ".hgignore",
    "status": "C"
   },
   {
    "itemtype": "file",
    "path": "modified",
    "status": "C"
   }
  ]

  $ hg status -A -Tpickle > pickle
  >>> from __future__ import print_function
  >>> from mercurial import util
  >>> pickle = util.pickle
  >>> data = sorted((x[b'status'].decode(), x[b'path'].decode()) for x in pickle.load(open("pickle", r"rb")))
  >>> for s, p in data: print("%s %s" % (s, p))
  ! deleted
  ? pickle
  ? unknown
  A added
  A copied
  C .hgignore
  C modified
  I ignored
  R removed
  $ rm pickle

  $ echo "^ignoreddir$" > .hgignore
  $ mkdir ignoreddir
  $ touch ignoreddir/file

Test templater support:

  $ hg status -AT "[{status}]\t{if(source, '{source} -> ')}{path}\n"
  [M]	.hgignore
  [A]	added
  [A]	modified -> copied
  [R]	removed
  [!]	deleted
  [?]	ignored
  [?]	unknown
  [I]	ignoreddir/file
  [C]	modified
  $ hg status -AT default
  M .hgignore
  A added
  A copied
    modified
  R removed
  ! deleted
  ? ignored
  ? unknown
  I ignoreddir/file
  C modified
  $ hg status -T compact
  abort: "status" not in template map
  [255]

hg status ignoreddir/file:

  $ hg status ignoreddir/file

hg status -i ignoreddir/file:

  $ hg status -i ignoreddir/file
  I ignoreddir/file
  $ cd ..

Check 'status -q' and some combinations

  $ hg init repo3
  $ cd repo3
  $ touch modified removed deleted ignored
  $ echo "^ignored$" > .hgignore
  $ hg commit -A -m 'initial checkin'
  adding .hgignore
  adding deleted
  adding modified
  adding removed
  $ touch added unknown ignored
  $ hg add added
  $ echo "test" >> modified
  $ hg remove removed
  $ rm deleted
  $ hg copy modified copied

Specify working directory revision explicitly, that should be the same as
"hg status"

  $ hg status --change "wdir()"
  M modified
  A added
  A copied
  R removed
  ! deleted
  ? unknown

Run status with 2 different flags.
Check if result is the same or different.
If result is not as expected, raise error

  $ assert() {
  >     hg status $1 > ../a
  >     hg status $2 > ../b
  >     if diff ../a ../b > /dev/null; then
  >         out=0
  >     else
  >         out=1
  >     fi
  >     if [ $3 -eq 0 ]; then
  >         df="same"
  >     else
  >         df="different"
  >     fi
  >     if [ $out -ne $3 ]; then
  >         echo "Error on $1 and $2, should be $df."
  >     fi
  > }

Assert flag1 flag2 [0-same | 1-different]

  $ assert "-q" "-mard"      0
  $ assert "-A" "-marduicC"  0
  $ assert "-qA" "-mardcC"   0
  $ assert "-qAui" "-A"      0
  $ assert "-qAu" "-marducC" 0
  $ assert "-qAi" "-mardicC" 0
  $ assert "-qu" "-u"        0
  $ assert "-q" "-u"         1
  $ assert "-m" "-a"         1
  $ assert "-r" "-d"         1
  $ cd ..

  $ hg init repo4
  $ cd repo4
  $ touch modified removed deleted
  $ hg ci -q -A -m 'initial checkin'
  $ touch added unknown
  $ hg add added
  $ hg remove removed
  $ rm deleted
  $ echo x > modified
  $ hg copy modified copied
  $ hg ci -m 'test checkin' -d "1000001 0"
  $ rm *
  $ touch unrelated
  $ hg ci -q -A -m 'unrelated checkin' -d "1000002 0"

hg status --change 1:

  $ hg status --change 1
  M modified
  A added
  A copied
  R removed

hg status --change 1 unrelated:

  $ hg status --change 1 unrelated

hg status -C --change 1 added modified copied removed deleted:

  $ hg status -C --change 1 added modified copied removed deleted
  M modified
  A added
  A copied
    modified
  R removed

hg status -A --change 1 and revset:

  $ hg status -A --change '1|1'
  M modified
  A added
  A copied
    modified
  R removed
  C deleted

  $ cd ..

hg status with --rev and reverted changes:

  $ hg init reverted-changes-repo
  $ cd reverted-changes-repo
  $ echo a > file
  $ hg add file
  $ hg ci -m a
  $ echo b > file
  $ hg ci -m b

reverted file should appear clean

  $ hg revert -r 0 .
  reverting file
  $ hg status -A --rev 0
  C file

#if execbit
reverted file with changed flag should appear modified

  $ chmod +x file
  $ hg status -A --rev 0
  M file

  $ hg revert -r 0 .
  reverting file

reverted and committed file with changed flag should appear modified

  $ hg co -C .
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ chmod +x file
  $ hg ci -m 'change flag'
  $ hg status -A --rev 1 --rev 2
  M file
  $ hg diff -r 1 -r 2

#endif

  $ cd ..

hg status of binary file starting with '\1\n', a separator for metadata:

  $ hg init repo5
  $ cd repo5
  >>> open("010a", r"wb").write(b"\1\nfoo") and None
  $ hg ci -q -A -m 'initial checkin'
  $ hg status -A
  C 010a

  >>> open("010a", r"wb").write(b"\1\nbar") and None
  $ hg status -A
  M 010a
  $ hg ci -q -m 'modify 010a'
  $ hg status -A --rev 0:1
  M 010a

  $ touch empty
  $ hg ci -q -A -m 'add another file'
  $ hg status -A --rev 1:2 010a
  C 010a

  $ cd ..

test "hg status" with "directory pattern" which matches against files
only known on target revision.

  $ hg init repo6
  $ cd repo6

  $ echo a > a.txt
  $ hg add a.txt
  $ hg commit -m '#0'
  $ mkdir -p 1/2/3/4/5
  $ echo b > 1/2/3/4/5/b.txt
  $ hg add 1/2/3/4/5/b.txt
  $ hg commit -m '#1'

  $ hg update -C 0 > /dev/null
  $ hg status -A
  C a.txt

the directory matching against specified pattern should be removed,
because directory existence prevents 'dirstate.walk()' from showing
warning message about such pattern.

  $ test ! -d 1
  $ hg status -A --rev 1 1/2/3/4/5/b.txt
  R 1/2/3/4/5/b.txt
  $ hg status -A --rev 1 1/2/3/4/5
  R 1/2/3/4/5/b.txt
  $ hg status -A --rev 1 1/2/3
  R 1/2/3/4/5/b.txt
  $ hg status -A --rev 1 1
  R 1/2/3/4/5/b.txt

  $ hg status --config ui.formatdebug=True --rev 1 1
  status = [
      {
          'itemtype': 'file',
          'path': '1/2/3/4/5/b.txt',
          'status': 'R'
      },
  ]

#if windows
  $ hg --config ui.slash=false status -A --rev 1 1
  R 1\2\3\4\5\b.txt
#endif

  $ cd ..

Status after move overwriting a file (issue4458)
=================================================


  $ hg init issue4458
  $ cd issue4458
  $ echo a > a
  $ echo b > b
  $ hg commit -Am base
  adding a
  adding b


with --force

  $ hg mv b --force a
  $ hg st --copies
  M a
    b
  R b
  $ hg revert --all
  reverting a
  undeleting b
  $ rm *.orig

without force

  $ hg rm a
  $ hg st --copies
  R a
  $ hg mv b a
  $ hg st --copies
  M a
    b
  R b

using ui.statuscopies setting
  $ hg st --config ui.statuscopies=true
  M a
    b
  R b
  $ hg st --config ui.statuscopies=false
  M a
  R b
  $ hg st --config ui.tweakdefaults=yes
  M a
    b
  R b

using log status template (issue5155)
  $ hg log -Tstatus -r 'wdir()' -C
  changeset:   2147483647:ffffffffffff
  parent:      0:8c55c58b4c0e
  user:        test
  date:        * (glob)
  files:
  M a
    b
  R b
  
  $ hg log -GTstatus -r 'wdir()' -C
  o  changeset:   2147483647:ffffffffffff
  |  parent:      0:8c55c58b4c0e
  ~  user:        test
     date:        * (glob)
     files:
     M a
       b
     R b
  

Other "bug" highlight, the revision status does not report the copy information.
This is buggy behavior.

  $ hg commit -m 'blah'
  $ hg st --copies --change .
  M a
  R b

using log status template, the copy information is displayed correctly.
  $ hg log -Tstatus -r. -C
  changeset:   1:6685fde43d21
  tag:         tip
  user:        test
  date:        * (glob)
  summary:     blah
  files:
  M a
    b
  R b
  

  $ cd ..

Make sure .hg doesn't show up even as a symlink

  $ hg init repo0
  $ mkdir symlink-repo0
  $ cd symlink-repo0
  $ ln -s ../repo0/.hg
  $ hg status

If the size hasn’t changed but mtime has, status needs to read the contents
of the file to check whether it has changed

  $ echo 1 > a
  $ echo 1 > b
  $ touch -t 200102030000 a b
  $ hg commit -Aqm '#0'
  $ echo 2 > a
  $ touch -t 200102040000 a b
  $ hg status
  M a

Asking specifically for the status of a deleted/removed file

  $ rm a
  $ rm b
  $ hg status a
  ! a
  $ hg rm a
  $ hg rm b
  $ hg status a
  R a
  $ hg commit -qm '#1'
  $ hg status a
  a: $ENOENT$

Check using include flag with pattern when status does not need to traverse
the working directory (issue6483)

  $ cd ..
  $ hg init issue6483
  $ cd issue6483
  $ touch a.py b.rs
  $ hg add a.py b.rs
  $ hg st -aI "*.py"
  A a.py

Also check exclude pattern

  $ hg st -aX "*.rs"
  A a.py

issue6335
When a directory containing a tracked file gets symlinked, as of 5.8
`hg st` only gives the correct answer about clean (or deleted) files
if also listing unknowns.
The tree-based dirstate and status algorithm fix this:

#if symlink no-dirstate-v1 rust

  $ cd ..
  $ hg init issue6335
  $ cd issue6335
  $ mkdir foo
  $ touch foo/a
  $ hg ci -Ama
  adding foo/a
  $ mv foo bar
  $ ln -s bar foo
  $ hg status
  ! foo/a
  ? bar/a
  ? foo

  $ hg status -c  # incorrect output without the Rust implementation
  $ hg status -cu
  ? bar/a
  ? foo
  $ hg status -d  # incorrect output without the Rust implementation
  ! foo/a
  $ hg status -du
  ! foo/a
  ? bar/a
  ? foo

#endif


Create a repo with files in each possible status

  $ cd ..
  $ hg init repo7
  $ cd repo7
  $ mkdir subdir
  $ touch clean modified deleted removed
  $ touch subdir/clean subdir/modified subdir/deleted subdir/removed
  $ echo ignored > .hgignore
  $ hg ci -Aqm '#0'
  $ echo 1 > modified
  $ echo 1 > subdir/modified
  $ rm deleted
  $ rm subdir/deleted
  $ hg rm removed
  $ hg rm subdir/removed
  $ touch unknown ignored
  $ touch subdir/unknown subdir/ignored

Check the output

  $ hg status
  M modified
  M subdir/modified
  R removed
  R subdir/removed
  ! deleted
  ! subdir/deleted
  ? subdir/unknown
  ? unknown

  $ hg status -mard
  M modified
  M subdir/modified
  R removed
  R subdir/removed
  ! deleted
  ! subdir/deleted

  $ hg status -A
  M modified
  M subdir/modified
  R removed
  R subdir/removed
  ! deleted
  ! subdir/deleted
  ? subdir/unknown
  ? unknown
  I ignored
  I subdir/ignored
  C .hgignore
  C clean
  C subdir/clean

Note: `hg status some-name` creates a patternmatcher which is not supported
yet by the Rust implementation of status, but includematcher is supported.
--include is used below for that reason

#if unix-permissions

Not having permission to read a directory that contains tracked files makes
status emit a warning then behave as if the directory was empty or removed
entirely:

  $ chmod 0 subdir
  $ hg status --include subdir
  subdir: Permission denied
  R subdir/removed
  ! subdir/clean
  ! subdir/deleted
  ! subdir/modified
  $ chmod 755 subdir

#endif

Remove a directory that contains tracked files

  $ rm -r subdir
  $ hg status --include subdir
  R subdir/removed
  ! subdir/clean
  ! subdir/deleted
  ! subdir/modified

… and replace it by a file

  $ touch subdir
  $ hg status --include subdir
  R subdir/removed
  ! subdir/clean
  ! subdir/deleted
  ! subdir/modified
  ? subdir

Replaced a deleted or removed file with a directory

  $ mkdir deleted removed
  $ touch deleted/1 removed/1
  $ hg status --include deleted --include removed
  R removed
  ! deleted
  ? deleted/1
  ? removed/1
  $ hg add removed/1
  $ hg status --include deleted --include removed
  A removed/1
  R removed
  ! deleted
  ? deleted/1

Deeply nested files in an ignored directory are still listed on request

  $ echo ignored-dir >> .hgignore
  $ mkdir ignored-dir
  $ mkdir ignored-dir/subdir
  $ touch ignored-dir/subdir/1
  $ hg status --ignored
  I ignored
  I ignored-dir/subdir/1

Check using include flag while listing ignored composes correctly (issue6514)

  $ cd ..
  $ hg init issue6514
  $ cd issue6514
  $ mkdir ignored-folder
  $ touch A.hs B.hs C.hs ignored-folder/other.txt ignored-folder/ctest.hs
  $ cat >.hgignore <<EOF
  > A.hs
  > B.hs
  > ignored-folder/
  > EOF
  $ hg st -i -I 're:.*\.hs$'
  I A.hs
  I B.hs
  I ignored-folder/ctest.hs

#if rust dirstate-v2

Check read_dir caching

  $ cd ..
  $ hg init repo8
  $ cd repo8
  $ mkdir subdir
  $ touch subdir/a subdir/b
  $ hg ci -Aqm '#0'

The cached mtime is initially unset

  $ hg debugdirstate --all --no-dates | grep '^ '
      0         -1 unset               subdir

It is still not set when there are unknown files

  $ touch subdir/unknown
  $ hg status
  ? subdir/unknown
  $ hg debugdirstate --all --no-dates | grep '^ '
      0         -1 unset               subdir

Now the directory is eligible for caching, so its mtime is save in the dirstate

  $ rm subdir/unknown
  $ hg status
  $ hg debugdirstate --all --no-dates | grep '^ '
      0         -1 set                 subdir

This time the command should be ever so slightly faster since it does not need `read_dir("subdir")`

  $ hg status

Creating a new file changes the directory’s mtime, invalidating the cache

  $ touch subdir/unknown
  $ hg status
  ? subdir/unknown

  $ rm subdir/unknown
  $ hg status

Removing a node from the dirstate resets the cache for its parent directory

  $ hg forget subdir/a
  $ hg debugdirstate --all --no-dates | grep '^ '
      0         -1 set                 subdir
  $ hg ci -qm '#1'
  $ hg debugdirstate --all --no-dates | grep '^ '
      0         -1 unset               subdir
  $ hg status
  ? subdir/a

#endif

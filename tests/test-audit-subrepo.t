Test illegal name
-----------------

on commit:

  $ hg init hgname
  $ cd hgname
  $ mkdir sub
  $ hg init sub/.hg
  $ echo 'sub/.hg = sub/.hg' >> .hgsub
  $ hg ci -qAm 'add subrepo "sub/.hg"'
  abort: path 'sub/.hg' is inside nested repo 'sub'
  [10]

prepare tampered repo (including the commit above):

  $ hg import --bypass -qm 'add subrepo "sub/.hg"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +sub/.hg = sub/.hg
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 sub/.hg
  > EOF
  $ cd ..

on clone (and update):

  $ hg clone -q hgname hgname2
  abort: path 'sub/.hg' is inside nested repo 'sub'
  [10]

Test absolute path
------------------

on commit:

  $ hg init absolutepath
  $ cd absolutepath
  $ hg init sub
  $ echo '/sub = sub' >> .hgsub
  $ hg ci -qAm 'add subrepo "/sub"'
  abort: path contains illegal component: /sub
  [10]

prepare tampered repo (including the commit above):

  $ hg import --bypass -qm 'add subrepo "/sub"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +/sub = sub
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 /sub
  > EOF
  $ cd ..

on clone (and update):

  $ hg clone -q absolutepath absolutepath2
  abort: path contains illegal component: /sub
  [10]

Test root path
--------------

on commit:

  $ hg init rootpath
  $ cd rootpath
  $ hg init sub
  $ echo '/ = sub' >> .hgsub
  $ hg ci -qAm 'add subrepo "/"'
  abort: path ends in directory separator: /
  [10]

prepare tampered repo (including the commit above):

  $ hg import --bypass -qm 'add subrepo "/"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +/ = sub
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 /
  > EOF
  $ cd ..

on clone (and update):

  $ hg clone -q rootpath rootpath2
  abort: path ends in directory separator: /
  [10]

Test empty path
---------------

on commit:

  $ hg init emptypath
  $ cd emptypath
  $ hg init sub
  $ echo '= sub' >> .hgsub
  $ hg ci -qAm 'add subrepo ""'
  config error at .hgsub:1: = sub
  [30]

prepare tampered repo (including the commit above):

  $ hg import --bypass -qm 'add subrepo ""' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > += sub
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000
  > EOF
  $ cd ..

on clone (and update):

  $ hg clone -q emptypath emptypath2
  config error at .hgsub:1: = sub
  [30]

Test current path
-----------------

on commit:

  $ hg init currentpath
  $ cd currentpath
  $ hg init sub
  $ echo '. = sub' >> .hgsub
  $ hg ci -qAm 'add subrepo "."'
  abort: subrepo path contains illegal component: .
  [255]

prepare tampered repo (including the commit above):

  $ hg import --bypass -qm 'add subrepo "."' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +.= sub
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 .
  > EOF
  $ cd ..

on clone (and update):

  $ hg clone -q currentpath currentpath2
  abort: subrepo path contains illegal component: .
  [255]

Test outer path
---------------

on commit:

  $ mkdir outerpath
  $ cd outerpath
  $ hg init main
  $ cd main
  $ hg init ../sub
  $ echo '../sub = ../sub' >> .hgsub
  $ hg ci -qAm 'add subrepo "../sub"'
  abort: path contains illegal component: ../sub
  [10]

prepare tampered repo (including the commit above):

  $ hg import --bypass -qm 'add subrepo "../sub"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +../sub = ../sub
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 ../sub
  > EOF
  $ cd ..

on clone (and update):

  $ hg clone -q main main2
  abort: path contains illegal component: ../sub
  [10]
  $ cd ..

Test variable expansion
-----------------------

Subrepository paths shouldn't be expanded, but we fail to handle them
properly. Any local repository paths are expanded.

on commit:

  $ mkdir envvar
  $ cd envvar
  $ hg init main
  $ cd main
  $ hg init sub1
  $ cat <<'EOF' > sub1/hgrc
  > [hooks]
  > log = echo pwned
  > EOF
  $ hg -R sub1 ci -qAm 'add sub1 files'
  $ hg -R sub1 log -r. -T '{node}\n'
  39eb4b4d3e096527668784893a9280578a8f38b8
  $ echo '$SUB = sub1' >> .hgsub
  $ SUB=sub1 hg ci -qAm 'add subrepo "$SUB"'
  abort: subrepo path contains illegal component: $SUB
  [255]

prepare tampered repo (including the changes above as two commits):

  $ hg import --bypass -qm 'add subrepo "$SUB"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +$SUB = sub1
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 $SUB
  > EOF
  $ hg debugsetparents 0
  $ hg import --bypass -qm 'update subrepo "$SUB"' - <<'EOF'
  > diff --git a/.hgsubstate b/.hgsubstate
  > --- a/.hgsubstate
  > +++ b/.hgsubstate
  > @@ -1,1 +1,1 @@
  > -0000000000000000000000000000000000000000 $SUB
  > +39eb4b4d3e096527668784893a9280578a8f38b8 $SUB
  > EOF
  $ cd ..

on clone (and update) with various substitutions:

  $ hg clone -q main main2
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A main2
  .hg
  .hgsub
  .hgsubstate

  $ SUB=sub1 hg clone -q main main3
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A main3
  .hg
  .hgsub
  .hgsubstate

  $ SUB=sub2 hg clone -q main main4
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A main4
  .hg
  .hgsub
  .hgsubstate

on clone empty subrepo into .hg, then pull (and update), which at least fails:

  $ SUB=.hg hg clone -qr0 main main5
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A main5
  .hg
  .hgsub
  .hgsubstate
  $ test -d main5/.hg/.hg
  [1]
  $ SUB=.hg hg -R main5 pull -u
  pulling from $TESTTMP/envvar/main
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 7a2f0e59146f
  .hgsubstate: untracked file differs
  abort: untracked files in working directory differ from files in requested revision
  [20]
  $ cat main5/.hg/hgrc | grep pwned
  [1]

on clone (and update) into .hg, which at least fails:

  $ SUB=.hg hg clone -q main main6
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A main6
  .hg
  .hgsub
  .hgsubstate
  $ cat main6/.hg/hgrc | grep pwned
  [1]

on clone (and update) into .hg/* subdir:

  $ SUB=.hg/foo hg clone -q main main7
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A main7
  .hg
  .hgsub
  .hgsubstate
  $ test -d main7/.hg/.hg
  [1]

on clone (and update) into outer tree:

  $ SUB=../out-of-tree-write hg clone -q main main8
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A main8
  .hg
  .hgsub
  .hgsubstate

on clone (and update) into e.g. $HOME, which doesn't work since subrepo paths
are concatenated prior to variable expansion:

  $ SUB="$TESTTMP/envvar/fakehome" hg clone -q main main9
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A main9 | wc -l
  \s*3 (re)

  $ ls
  main
  main2
  main3
  main4
  main5
  main6
  main7
  main8
  main9
  $ cd ..

Test tilde
----------

The leading tilde may be expanded to $HOME, but it can be a valid subrepo
path in theory. However, we want to prohibit it as there might be unsafe
handling of such paths.

on commit:

  $ hg init tilde
  $ cd tilde
  $ hg init './~'
  $ echo '~ = ~' >> .hgsub
  $ hg ci -qAm 'add subrepo "~"'
  abort: subrepo path contains illegal component: ~
  [255]

prepare tampered repo (including the commit above):

  $ hg import --bypass -qm 'add subrepo "~"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +~ = ~
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 ~
  > EOF
  $ cd ..

on clone (and update):

  $ hg clone -q tilde tilde2
  abort: subrepo path contains illegal component: ~
  [255]

Test direct symlink traversal
-----------------------------

#if symlink

on commit:

  $ mkdir hgsymdir
  $ hg init hgsymdir/root
  $ cd hgsymdir/root
  $ ln -s ../out
  $ hg ci -qAm 'add symlink "out"'
  $ hg init ../out
  $ echo 'out = out' >> .hgsub
  $ hg ci -qAm 'add subrepo "out"'
  abort: subrepo 'out' traverses symbolic link
  [255]

prepare tampered repo (including the commit above):

  $ hg import --bypass -qm 'add subrepo "out"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +out = out
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 out
  > EOF
  $ cd ../..

on clone (and update):

  $ mkdir hgsymdir2
  $ hg clone -q hgsymdir/root hgsymdir2/root
  abort: subrepo 'out' traverses symbolic link
  [255]
  $ ls hgsymdir2
  root

#endif

Test indirect symlink traversal
-------------------------------

#if symlink

on commit:

  $ mkdir hgsymin
  $ hg init hgsymin/root
  $ cd hgsymin/root
  $ ln -s ../out
  $ hg ci -qAm 'add symlink "out"'
  $ mkdir ../out
  $ hg init ../out/sub
  $ echo 'out/sub = out/sub' >> .hgsub
  $ hg ci -qAm 'add subrepo "out/sub"'
  abort: path 'out/sub' traverses symbolic link 'out'
  [255]

prepare tampered repo (including the commit above):

  $ hg import --bypass -qm 'add subrepo "out/sub"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +out/sub = out/sub
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 out/sub
  > EOF
  $ cd ../..

on clone (and update):

  $ mkdir hgsymin2
  $ hg clone -q hgsymin/root hgsymin2/root
  abort: path 'out/sub' traverses symbolic link 'out'
  [255]
  $ ls hgsymin2
  root

#endif

Test symlink traversal by variable expansion
--------------------------------------------

#if symlink

  $ FAKEHOME="$TESTTMP/envvarsym/fakehome"

on commit:

  $ mkdir envvarsym
  $ cd envvarsym
  $ hg init main
  $ cd main
  $ ln -s "`echo "$FAKEHOME" | sed 's|\(.\)/.*|\1|'`"
  $ hg ci -qAm 'add symlink to top-level system directory'

  $ hg init sub1
  $ echo pwned > sub1/pwned
  $ hg -R sub1 ci -qAm 'add sub1 files'
  $ hg -R sub1 log -r. -T '{node}\n'
  f40c9134ba1b6961e12f250868823f0092fb68a8
  $ echo '$SUB = sub1' >> .hgsub
  $ SUB="$FAKEHOME" hg ci -qAm 'add subrepo "$SUB"'
  abort: subrepo path contains illegal component: $SUB
  [255]

prepare tampered repo (including the changes above as two commits):

  $ hg import --bypass -qm 'add subrepo "$SUB"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +$SUB = sub1
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 $SUB
  > EOF
  $ hg debugsetparents 1
  $ hg import --bypass -qm 'update subrepo "$SUB"' - <<'EOF'
  > diff --git a/.hgsubstate b/.hgsubstate
  > --- a/.hgsubstate
  > +++ b/.hgsubstate
  > @@ -1,1 +1,1 @@
  > -0000000000000000000000000000000000000000 $SUB
  > +f40c9134ba1b6961e12f250868823f0092fb68a8 $SUB
  > EOF
  $ cd ..

on clone (and update) without fakehome directory:

  $ rm -fR "$FAKEHOME"
  $ SUB="$FAKEHOME" hg clone -q main main2
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ test -d "$FAKEHOME"
  [1]

on clone (and update) with empty fakehome directory:

  $ rm -fR "$FAKEHOME"
  $ mkdir "$FAKEHOME"
  $ SUB="$FAKEHOME" hg clone -q main main3
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls "$FAKEHOME"

on clone (and update) with non-empty fakehome directory:

  $ rm -fR "$FAKEHOME"
  $ mkdir "$FAKEHOME"
  $ touch "$FAKEHOME/a"
  $ SUB="$FAKEHOME" hg clone -q main main4
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls "$FAKEHOME"
  a

on clone empty subrepo with non-empty fakehome directory,
then pull (and update):

  $ rm -fR "$FAKEHOME"
  $ mkdir "$FAKEHOME"
  $ touch "$FAKEHOME/a"
  $ SUB="$FAKEHOME" hg clone -qr1 main main5
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls "$FAKEHOME"
  a
  $ test -d "$FAKEHOME/.hg"
  [1]
  $ SUB="$FAKEHOME" hg -R main5 pull -u
  pulling from $TESTTMP/envvarsym/main
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets * (glob)
  .hgsubstate: untracked file differs
  abort: untracked files in working directory differ from files in requested revision
  [20]
  $ ls "$FAKEHOME"
  a
  $ test -d "$FAKEHOME/.hg"
  [1]

on clone empty subrepo with hg-managed fakehome directory,
then pull (and update):

  $ rm -fR "$FAKEHOME"
  $ hg init "$FAKEHOME"
  $ touch "$FAKEHOME/a"
  $ hg -R "$FAKEHOME" ci -qAm 'add fakehome file'
  $ SUB="$FAKEHOME" hg clone -qr1 main main6
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A "$FAKEHOME"
  .hg
  a
  $ SUB="$FAKEHOME" hg -R main6 pull -u
  pulling from $TESTTMP/envvarsym/main
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets * (glob)
  .hgsubstate: untracked file differs
  abort: untracked files in working directory differ from files in requested revision
  [20]
  $ ls -A "$FAKEHOME"
  .hg
  a

on clone only symlink with hg-managed fakehome directory,
then pull (and update):

  $ rm -fR "$FAKEHOME"
  $ hg init "$FAKEHOME"
  $ touch "$FAKEHOME/a"
  $ hg -R "$FAKEHOME" ci -qAm 'add fakehome file'
  $ SUB="$FAKEHOME" hg clone -qr0 main main7
  $ ls -A "$FAKEHOME"
  .hg
  a
  $ SUB="$FAKEHOME" hg -R main7 pull -uf
  pulling from $TESTTMP/envvarsym/main
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 3 changes to 2 files
  new changesets * (glob)
  abort: subrepo path contains illegal component: $SUB
  [255]
  $ ls -A "$FAKEHOME"
  .hg
  a

  $ cd ..

#endif

Test drive letter
-----------------

Windows has a weird relative path that can change the drive letter, which
should also be prohibited on Windows.

prepare tampered repo:

  $ hg init driveletter
  $ cd driveletter
  $ hg import --bypass -qm 'add subrepo "X:"' - <<'EOF'
  > diff --git a/.hgsub b/.hgsub
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsub
  > @@ -0,0 +1,1 @@
  > +X: = foo
  > diff --git a/.hgsubstate b/.hgsubstate
  > new file mode 100644
  > --- /dev/null
  > +++ b/.hgsubstate
  > @@ -0,0 +1,1 @@
  > +0000000000000000000000000000000000000000 X:
  > EOF
  $ cd ..

on clone (and update):

#if windows

  $ hg clone -q driveletter driveletter2
  abort: path contains illegal component: X:
  [10]

#else

  $ hg clone -q driveletter driveletter2
  $ ls -A driveletter2
  .hg
  .hgsub
  .hgsubstate
  X:

#endif

#require bzr

  $ . "$TESTDIR/bzr-definitions"

Work around https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=944379
  $ mkdir -p "${HOME}/.config/breezy"

empty directory

  $ mkdir test-empty
  $ cd test-empty
  $ brz init -q source
  $ cd source
  $ echo content > a
  $ brz add -q a
  $ brz commit -q -m 'Initial add'
  $ mkdir empty
  $ brz add -q empty
  $ brz commit -q -m 'Empty directory added'
  $ echo content > empty/something
  $ brz add -q empty/something
  $ brz commit -q -m 'Added file into directory'
  $ cd ..
  $ hg convert source source-hg
  initializing destination source-hg repository
  scanning source...
  sorting...
  converting...
  2 Initial add
  1 Empty directory added
  0 Added file into directory
  $ manifest source-hg 1
  % manifest of 1
  644   a
  $ manifest source-hg tip
  % manifest of tip
  644   a
  644   empty/something
  $ cd ..

directory renames

  $ mkdir test-dir-rename
  $ cd test-dir-rename
  $ brz init -q source
  $ cd source
  $ mkdir tpyo
  $ echo content > tpyo/something
  $ brz add -q tpyo
  $ brz commit -q -m 'Added directory'
  $ brz mv tpyo typo
  tpyo => typo
  $ brz commit -q -m 'Oops, typo'
  $ cd ..
  $ hg convert source source-hg
  initializing destination source-hg repository
  scanning source...
  sorting...
  converting...
  1 Added directory
  0 Oops, typo
  $ manifest source-hg 0
  % manifest of 0
  644   tpyo/something
  $ manifest source-hg tip
  % manifest of tip
  644   typo/something
  $ cd ..

nested directory renames

  $ mkdir test-nested-dir-rename
  $ cd test-nested-dir-rename
  $ brz init -q source
  $ cd source
  $ mkdir -p firstlevel/secondlevel/thirdlevel
  $ echo content > firstlevel/secondlevel/file
  $ echo this_needs_to_be_there_too > firstlevel/secondlevel/thirdlevel/stuff
  $ brz add -q firstlevel
  $ brz commit -q -m 'Added nested directories'
  $ brz mv firstlevel/secondlevel secondlevel
  firstlevel/secondlevel => secondlevel
  $ brz commit -q -m 'Moved secondlevel one level up'
  $ cd ..
  $ hg convert source source-hg
  initializing destination source-hg repository
  scanning source...
  sorting...
  converting...
  1 Added nested directories
  0 Moved secondlevel one level up
  $ manifest source-hg tip
  % manifest of tip
  644   secondlevel/file
  644   secondlevel/thirdlevel/stuff
  $ cd ..

directory remove

  $ mkdir test-dir-remove
  $ cd test-dir-remove
  $ brz init -q source
  $ cd source
  $ mkdir src
  $ echo content > src/sourcecode
  $ brz add -q src
  $ brz commit -q -m 'Added directory'
  $ brz rm -q src
  $ brz commit -q -m 'Removed directory'
  $ cd ..
  $ hg convert source source-hg
  initializing destination source-hg repository
  scanning source...
  sorting...
  converting...
  1 Added directory
  0 Removed directory
  $ manifest source-hg 0
  % manifest of 0
  644   src/sourcecode
  $ manifest source-hg tip
  % manifest of tip
  $ cd ..

directory replace

  $ mkdir test-dir-replace
  $ cd test-dir-replace
  $ brz init -q source
  $ cd source
  $ mkdir first second
  $ echo content > first/file
  $ echo morecontent > first/dummy
  $ echo othercontent > second/something
  $ brz add -q first second
  $ brz commit -q -m 'Initial layout'
  $ brz mv first/file second/file
  first/file => second/file
  $ brz mv first third
  first => third
  $ brz commit -q -m 'Some conflicting moves'
  $ cd ..
  $ hg convert source source-hg
  initializing destination source-hg repository
  scanning source...
  sorting...
  converting...
  1 Initial layout
  0 Some conflicting moves
  $ manifest source-hg tip
  % manifest of tip
  644   second/file
  644   second/something
  644   third/dummy
  $ cd ..

divergent nested renames (issue3089)

  $ mkdir test-divergent-renames
  $ cd test-divergent-renames
  $ brz init -q source
  $ cd source
  $ mkdir -p a/c
  $ echo a > a/fa
  $ echo c > a/c/fc
  $ brz add -q a
  $ brz commit -q -m 'Initial layout'
  $ brz mv a b
  a => b
  $ mkdir a
  $ brz add a
  add(ed|ing) a (re)
  $ brz mv b/c a/c
  b/c => a/c
  $ brz status
  added:
    a/
  renamed:
    a/? => b/? (re)
    a/c/? => a/c/? (re)
  $ brz commit -q -m 'Divergent renames'
  $ cd ..
  $ hg convert source source-hg
  initializing destination source-hg repository
  scanning source...
  sorting...
  converting...
  1 Initial layout
  0 Divergent renames
  $ hg -R source-hg st -C --change 1
  A b/fa
    a/fa
  R a/fa
  $ hg -R source-hg manifest -r 1
  a/c/fc
  b/fa
  $ cd ..

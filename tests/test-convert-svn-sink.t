#require svn13

  $ svnupanddisplay()
  > {
  >     (
  >        cd $1;
  >        svn up -q;
  >        svn st -v | sed 's/  */ /g' | sort
  >        limit=''
  >        if [ $2 -gt 0 ]; then
  >            limit="--limit=$2"
  >        fi
  >        svn log --xml -v $limit | "$PYTHON" "$TESTDIR/svnxml.py"
  >     )
  > }

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > convert =
  > EOF

  $ hg init a

Add

  $ echo a > a/a
  $ mkdir -p a/d1/d2
  $ echo b > a/d1/d2/b
  $ hg --cwd a ci -d '0 0' -A -m 'add a file'
  adding a
  adding d1/d2/b

Modify

  $ svn-safe-append.py a a/a
  $ hg --cwd a ci -d '1 0' -m 'modify a file'
  $ hg --cwd a tip -q
  1:e0e2b8a9156b

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn repository 'a-hg'
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  1 add a file
  0 modify a file
  $ svnupanddisplay a-hg-wc 2
   2 1 test d1
   2 1 test d1/d2
   2 1 test d1/d2/b
   2 2 test .
   2 2 test a
  revision: 2
  author: test
  date: * (glob)
  msg: modify a file
   M /a
  revision: 1
  author: test
  date: * (glob)
  msg: add a file
   A /a
   A /d1
   A /d1/d2
   A /d1/d2/b
  $ ls a a-hg-wc
  a:
  a
  d1
  
  a-hg-wc:
  a
  d1
  $ cmp a/a a-hg-wc/a

Rename

  $ hg --cwd a mv a b
  $ hg --cwd a ci -d '2 0' -m 'rename a file'
  $ hg --cwd a tip -q
  2:eb5169441d43

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  0 rename a file
  $ svnupanddisplay a-hg-wc 1
   3 1 test d1
   3 1 test d1/d2
   3 1 test d1/d2/b
   3 3 test .
   3 3 test b
  revision: 3
  author: test
  date: * (glob)
  msg: rename a file
   D /a
   A /b (from /a@2)
  $ ls a a-hg-wc
  a:
  b
  d1
  
  a-hg-wc:
  b
  d1

Copy

  $ hg --cwd a cp b c

  $ hg --cwd a ci -d '3 0' -m 'copy a file'
  $ hg --cwd a tip -q
  3:60effef6ab48

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  0 copy a file
  $ svnupanddisplay a-hg-wc 1
   4 1 test d1
   4 1 test d1/d2
   4 1 test d1/d2/b
   4 3 test b
   4 4 test .
   4 4 test c
  revision: 4
  author: test
  date: * (glob)
  msg: copy a file
   A /c (from /b@3)
  $ ls a a-hg-wc
  a:
  b
  c
  d1
  
  a-hg-wc:
  b
  c
  d1

  $ hg --cwd a rm b

Remove

  $ hg --cwd a ci -d '4 0' -m 'remove a file'
  $ hg --cwd a tip -q
  4:87bbe3013fb6

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  0 remove a file
  $ svnupanddisplay a-hg-wc 1
   5 1 test d1
   5 1 test d1/d2
   5 1 test d1/d2/b
   5 4 test c
   5 5 test .
  revision: 5
  author: test
  date: * (glob)
  msg: remove a file
   D /b
  $ ls a a-hg-wc
  a:
  c
  d1
  
  a-hg-wc:
  c
  d1

Executable

#if execbit
  $ chmod +x a/c
#else
  $ echo fake >> a/c
#endif
  $ hg --cwd a ci -d '5 0' -m 'make a file executable'
#if execbit
  $ hg --cwd a tip -q
  5:ff42e473c340
#else
  $ hg --cwd a tip -q
  5:817a700c8cf1
#endif

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  0 make a file executable
  $ svnupanddisplay a-hg-wc 1
   6 1 test d1
   6 1 test d1/d2
   6 1 test d1/d2/b
   6 6 test .
   6 6 test c
  revision: 6
  author: test
  date: * (glob)
  msg: make a file executable
   M /c
#if execbit
  $ test -x a-hg-wc/c
#endif

#if symlink

Symlinks

  $ ln -s a/missing a/link
  $ hg --cwd a commit -Am 'add symlink'
  adding link
  $ hg --cwd a mv link newlink
  $ hg --cwd a commit -m 'move symlink'
  $ hg convert -d svn a a-svnlink
  initializing svn repository 'a-svnlink'
  initializing svn working copy 'a-svnlink-wc'
  scanning source...
  sorting...
  converting...
  7 add a file
  6 modify a file
  5 rename a file
  4 copy a file
  3 remove a file
  2 make a file executable
  1 add symlink
  0 move symlink
  $ svnupanddisplay a-svnlink-wc 1
   8 1 test d1
   8 1 test d1/d2
   8 1 test d1/d2/b
   8 6 test c
   8 8 test .
   8 8 test newlink
  revision: 8
  author: test
  date: * (glob)
  msg: move symlink
   D /link
   A /newlink (from /link@7)

Make sure our changes don't affect the rest of the test cases

  $ hg --cwd a up 5
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg --cwd a --config extensions.strip= strip -r 6
  saved backup bundle to $TESTTMP/a/.hg/strip-backup/bd4f7b7a7067-ed505e42-backup.hg

#endif

Convert with --full adds and removes files that didn't change

  $ touch a/f
  $ hg -R a ci -Aqmf
  $ echo "rename c d" > filemap
  $ hg convert -d svn a --filemap filemap --full
  assuming destination a-hg
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  0 f
  $ svnupanddisplay a-hg-wc 1
   7 7 test .
   7 7 test d
   7 7 test f
  revision: 7
  author: test
  date: * (glob)
  msg: f
   D /c
   A /d
   D /d1
   A /f

  $ rm -rf a a-hg a-hg-wc


Executable in new directory

  $ hg init a

  $ mkdir a/d1
  $ echo a > a/d1/a
#if execbit
  $ chmod +x a/d1/a
#else
  $ echo fake >> a/d1/a
#endif
  $ hg --cwd a ci -d '0 0' -A -m 'add executable file in new directory'
  adding d1/a

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn repository 'a-hg'
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  0 add executable file in new directory
  $ svnupanddisplay a-hg-wc 1
   1 1 test .
   1 1 test d1
   1 1 test d1/a
  revision: 1
  author: test
  date: * (glob)
  msg: add executable file in new directory
   A /d1
   A /d1/a
#if execbit
  $ test -x a-hg-wc/d1/a
#endif

Copy to new directory

  $ mkdir a/d2
  $ hg --cwd a cp d1/a d2/a
  $ hg --cwd a ci -d '1 0' -A -m 'copy file to new directory'

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  0 copy file to new directory
  $ svnupanddisplay a-hg-wc 1
   2 1 test d1
   2 1 test d1/a
   2 2 test .
   2 2 test d2
   2 2 test d2/a
  revision: 2
  author: test
  date: * (glob)
  msg: copy file to new directory
   A /d2
   A /d2/a (from /d1/a@1)

Branchy history

  $ hg init b
  $ echo base > b/b
  $ hg --cwd b ci -d '0 0' -Ambase
  adding b

  $ svn-safe-append.py left-1 b/b
  $ echo left-1 > b/left-1
  $ hg --cwd b ci -d '1 0' -Amleft-1
  adding left-1

  $ svn-safe-append.py left-2 b/b
  $ echo left-2 > b/left-2
  $ hg --cwd b ci -d '2 0' -Amleft-2
  adding left-2

  $ hg --cwd b up 0
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved

  $ svn-safe-append.py right-1 b/b
  $ echo right-1 > b/right-1
  $ hg --cwd b ci -d '3 0' -Amright-1
  adding right-1
  created new head

  $ svn-safe-append.py right-2 b/b
  $ echo right-2 > b/right-2
  $ hg --cwd b ci -d '4 0' -Amright-2
  adding right-2

  $ hg --cwd b up -C 2
  3 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg --cwd b merge
  merging b
  warning: conflicts while merging b! (edit, then use 'hg resolve --mark')
  2 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ hg --cwd b revert -r 2 b
  $ hg --cwd b resolve -m b
  (no more unresolved files)
  $ hg --cwd b ci -d '5 0' -m 'merge'

Expect 4 changes

  $ hg convert -d svn b
  assuming destination b-hg
  initializing svn repository 'b-hg'
  initializing svn working copy 'b-hg-wc'
  scanning source...
  sorting...
  converting...
  5 base
  4 left-1
  3 left-2
  2 right-1
  1 right-2
  0 merge

  $ svnupanddisplay b-hg-wc 0
   4 2 test left-1
   4 3 test b
   4 3 test left-2
   4 4 test .
   4 4 test right-1
   4 4 test right-2
  revision: 4
  author: test
  date: * (glob)
  msg: merge
   A /right-1
   A /right-2
  revision: 3
  author: test
  date: * (glob)
  msg: left-2
   M /b
   A /left-2
  revision: 2
  author: test
  date: * (glob)
  msg: left-1
   M /b
   A /left-1
  revision: 1
  author: test
  date: * (glob)
  msg: base
   A /b

Tags are not supported, but must not break conversion

  $ rm -rf a a-hg a-hg-wc
  $ hg init a
  $ echo a > a/a
  $ hg --cwd a ci -d '0 0' -A -m 'Add file a'
  adding a
  $ hg --cwd a tag -d '1 0' -m 'Tagged as v1.0' v1.0

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn repository 'a-hg'
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  1 Add file a
  0 Tagged as v1.0
  writing Subversion tags is not yet implemented
  $ svnupanddisplay a-hg-wc 2
   2 1 test a
   2 2 test .
   2 2 test .hgtags
  revision: 2
  author: test
  date: * (glob)
  msg: Tagged as v1.0
   A /.hgtags
  revision: 1
  author: test
  date: * (glob)
  msg: Add file a
   A /a
  $ rm -rf a a-hg a-hg-wc

#if execbit

Executable bit removal

  $ hg init a

  $ echo a > a/exec
  $ chmod +x a/exec
  $ hg --cwd a ci -d '1 0' -A -m 'create executable'
  adding exec
  $ chmod -x a/exec
  $ hg --cwd a ci -d '2 0' -A -m 'remove executable bit'

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn repository 'a-hg'
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  1 create executable
  0 remove executable bit
  $ svnupanddisplay a-hg-wc 0
   2 2 test .
   2 2 test exec
  revision: 2
  author: test
  date: * (glob)
  msg: remove executable bit
   M /exec
  revision: 1
  author: test
  date: * (glob)
  msg: create executable
   A /exec
  $ test ! -x a-hg-wc/exec

  $ rm -rf a a-hg a-hg-wc

#endif

Skipping empty commits

  $ hg init a

  $ hg --cwd a --config ui.allowemptycommit=True ci -d '1 0' -m 'Initial empty commit'

  $ echo a > a/a
  $ hg --cwd a ci -d '0 0' -A -m 'Some change'
  adding a
  $ hg --cwd a --config ui.allowemptycommit=True ci -d '2 0' -m 'Empty commit 1'
  $ hg --cwd a --config ui.allowemptycommit=True ci -d '3 0' -m 'Empty commit 2'
  $ echo b > a/b
  $ hg --cwd a ci -d '0 0' -A -m 'Another change'
  adding b

  $ hg convert -d svn a
  assuming destination a-hg
  initializing svn repository 'a-hg'
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  4 Initial empty commit
  3 Some change
  2 Empty commit 1
  1 Empty commit 2
  0 Another change

  $ svnupanddisplay a-hg-wc 0
   2 1 test a
   2 2 test .
   2 2 test b
  revision: 2
  author: test
  date: * (glob)
  msg: Another change
   A /b
  revision: 1
  author: test
  date: * (glob)
  msg: Some change
   A /a

  $ rm -rf a a-hg a-hg-wc

Commit dates convertion

  $ hg init a

  $ echo a >> a/a
  $ hg add a
  adding a/a
  $ hg --cwd a ci -d '1 0' -A -m 'Change 1'

  $ echo a >> a/a
  $ hg --cwd a ci -d '2 0' -m 'Change 2'

  $ echo a >> a/a
  $ hg --cwd a ci -d '2 0' -m 'Change at the same time'

  $ echo a >> a/a
  $ hg --cwd a ci -d '1 0' -m 'Change in the past'

  $ echo a >> a/a
  $ hg --cwd a ci -d '3 0' -m 'Change in the future'

  $ hg convert --config convert.svn.dangerous-set-commit-dates=true -d svn a
  assuming destination a-hg
  initializing svn repository 'a-hg'
  initializing svn working copy 'a-hg-wc'
  scanning source...
  sorting...
  converting...
  4 Change 1
  3 Change 2
  2 Change at the same time
  1 Change in the past
  0 Change in the future
  $ svnupanddisplay a-hg-wc 0
   5 5 test .
   5 5 test a
  revision: 5
  author: test
  date: 1970-01-01T00:00:03.000000Z
  msg: Change in the future
   M /a
  revision: 4
  author: test
  date: 1970-01-01T00:00:01.000000Z
  msg: Change in the past
   M /a
  revision: 3
  author: test
  date: 1970-01-01T00:00:02.000000Z
  msg: Change at the same time
   M /a
  revision: 2
  author: test
  date: 1970-01-01T00:00:02.000000Z
  msg: Change 2
   M /a
  revision: 1
  author: test
  date: 1970-01-01T00:00:01.000000Z
  msg: Change 1
   A /a

  $ rm -rf a a-hg a-hg-wc

#testcases abortcommand abortflag

#if abortflag
  $ cat >> $HGRCPATH <<EOF
  > [alias]
  > abort = graft --abort
  > EOF
#endif


Testing the reading of old format graftstate file with newer mercurial

  $ hg init oldgraft
  $ cd oldgraft
  $ for ch in a b c; do echo foo > $ch; hg add $ch; hg ci -Aqm "added "$ch; done;
  $ hg log -GT "{rev}:{node|short} {desc}\n"
  @  2:8be98ac1a569 added c
  |
  o  1:80e6d2c47cfe added b
  |
  o  0:f7ad41964313 added a
  
  $ hg up 0
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ echo bar > b
  $ hg add b
  $ hg ci -m "bar to b"
  created new head
  $ hg graft -r 1 -r 2
  grafting 1:80e6d2c47cfe "added b"
  merging b
  warning: conflicts while merging b! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

Writing the nodes in old format to graftstate

  $ hg log -r 1 -r 2 -T '{node}\n' > .hg/graftstate
  $ echo foo > b
  $ hg resolve -m
  (no more unresolved files)
  continue: hg graft --continue
  $ hg graft --continue
  grafting 1:80e6d2c47cfe "added b"
  grafting 2:8be98ac1a569 "added c"

Testing that --user is preserved during conflicts and value is reused while
running `hg graft --continue`

  $ hg log -G
  @  changeset:   5:711e9fa999f1
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     added c
  |
  o  changeset:   4:e5ad7353b408
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     added b
  |
  o  changeset:   3:9e887f7a939c
  |  parent:      0:f7ad41964313
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     bar to b
  |
  | o  changeset:   2:8be98ac1a569
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     added c
  | |
  | o  changeset:   1:80e6d2c47cfe
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     added b
  |
  o  changeset:   0:f7ad41964313
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     added a
  

  $ hg up '.^^'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved

  $ hg graft -r 1 -r 2 --user batman
  grafting 1:80e6d2c47cfe "added b"
  merging b
  warning: conflicts while merging b! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ echo wat > b
  $ hg resolve -m
  (no more unresolved files)
  continue: hg graft --continue

  $ hg graft --continue
  grafting 1:80e6d2c47cfe "added b"
  grafting 2:8be98ac1a569 "added c"

  $ hg log -Gr 3::
  @  changeset:   7:11a36ffaacf2
  |  tag:         tip
  |  user:        batman
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     added c
  |
  o  changeset:   6:76803afc6511
  |  parent:      3:9e887f7a939c
  |  user:        batman
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     added b
  |
  | o  changeset:   5:711e9fa999f1
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     added c
  | |
  | o  changeset:   4:e5ad7353b408
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     added b
  |
  o  changeset:   3:9e887f7a939c
  |  parent:      0:f7ad41964313
  ~  user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     bar to b
  
Test that --date is preserved and reused in `hg graft --continue`

  $ hg up '.^^'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg graft -r 1 -r 2 --date '1234560000 120'
  grafting 1:80e6d2c47cfe "added b"
  merging b
  warning: conflicts while merging b! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ echo foobar > b
  $ hg resolve -m
  (no more unresolved files)
  continue: hg graft --continue
  $ hg graft --continue
  grafting 1:80e6d2c47cfe "added b"
  grafting 2:8be98ac1a569 "added c"

  $ hg log -Gr '.^^::.'
  @  changeset:   9:1896b76e007a
  |  tag:         tip
  |  user:        test
  |  date:        Fri Feb 13 21:18:00 2009 -0002
  |  summary:     added c
  |
  o  changeset:   8:ce2b4f1632af
  |  parent:      3:9e887f7a939c
  |  user:        test
  |  date:        Fri Feb 13 21:18:00 2009 -0002
  |  summary:     added b
  |
  o  changeset:   3:9e887f7a939c
  |  parent:      0:f7ad41964313
  ~  user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     bar to b
  
Test that --log is preserved and reused in `hg graft --continue`

  $ hg up '.^^'
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg graft -r 1 -r 2 --log
  grafting 1:80e6d2c47cfe "added b"
  merging b
  warning: conflicts while merging b! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ echo foobar > b
  $ hg resolve -m
  (no more unresolved files)
  continue: hg graft --continue

  $ hg graft --continue
  grafting 1:80e6d2c47cfe "added b"
  grafting 2:8be98ac1a569 "added c"

  $ hg log -GT "{rev}:{node|short} {desc}" -r '.^^::.'
  @  11:30c1050a58b2 added c
  |  (grafted from 8be98ac1a56990c2d9ca6861041b8390af7bd6f3)
  o  10:ec7eda2313e2 added b
  |  (grafted from 80e6d2c47cfe5b3185519568327a17a061c7efb6)
  o  3:9e887f7a939c bar to b
  |
  ~

  $ cd ..

Testing the --stop flag of `hg graft` which stops the interrupted graft

  $ hg init stopgraft
  $ cd stopgraft
  $ for ch in a b c d; do echo $ch > $ch; hg add $ch; hg ci -Aqm "added "$ch; done;

  $ hg log -G
  @  changeset:   3:9150fe93bec6
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     added d
  |
  o  changeset:   2:155349b645be
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     added c
  |
  o  changeset:   1:5f6d8a4bf34a
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     added b
  |
  o  changeset:   0:9092f1db7931
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     added a
  
  $ hg up '.^^'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved

  $ echo foo > d
  $ hg ci -Aqm "added foo to d"

  $ hg graft --stop
  abort: no interrupted graft found
  [20]

  $ hg graft -r 3
  grafting 3:9150fe93bec6 "added d"
  merging d
  warning: conflicts while merging d! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ hg graft --stop --continue
  abort: cannot specify both --stop and --continue
  [10]

  $ hg graft --stop -U
  abort: cannot specify both --stop and --user
  [10]
  $ hg graft --stop --rev 4
  abort: cannot specify both --stop and --rev
  [10]
  $ hg graft --stop --log
  abort: cannot specify both --stop and --log
  [10]

  $ hg graft --stop
  stopped the interrupted graft
  working directory is now at a0deacecd59d

  $ hg diff

  $ hg log -Gr '.'
  @  changeset:   4:a0deacecd59d
  |  tag:         tip
  ~  parent:      1:5f6d8a4bf34a
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     added foo to d
  
  $ hg graft -r 2 -r 3
  grafting 2:155349b645be "added c"
  grafting 3:9150fe93bec6 "added d"
  merging d
  warning: conflicts while merging d! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ hg graft --stop
  stopped the interrupted graft
  working directory is now at 75b447541a9e

  $ hg diff

  $ hg log -G -T "{rev}:{node|short} {desc}"
  @  5:75b447541a9e added c
  |
  o  4:a0deacecd59d added foo to d
  |
  | o  3:9150fe93bec6 added d
  | |
  | o  2:155349b645be added c
  |/
  o  1:5f6d8a4bf34a added b
  |
  o  0:9092f1db7931 added a
  
  $ cd ..

Testing the --abort flag for `hg graft` which aborts and rollback to state
before the graft

  $ hg init abortgraft
  $ cd abortgraft
  $ for ch in a b c d; do echo $ch > $ch; hg add $ch; hg ci -Aqm "added "$ch; done;

  $ hg up '.^^'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved

  $ echo x > x
  $ hg ci -Aqm "added x"
  $ hg up '.^'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo foo > c
  $ hg ci -Aqm "added foo to c"

  $ hg log -GT "{rev}:{node|short} {desc}"
  @  5:36b793615f78 added foo to c
  |
  | o  4:863a25e1a9ea added x
  |/
  | o  3:9150fe93bec6 added d
  | |
  | o  2:155349b645be added c
  |/
  o  1:5f6d8a4bf34a added b
  |
  o  0:9092f1db7931 added a
  
  $ hg up 9150fe93bec6
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ hg abort
  abort: no interrupted graft to abort (abortflag !)
  abort: no operation in progress (abortcommand !)
  [20]

when stripping is required
  $ hg graft -r 4 -r 5
  grafting 4:863a25e1a9ea "added x"
  grafting 5:36b793615f78 "added foo to c" (tip)
  merging c
  warning: conflicts while merging c! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ hg graft --continue --abort
  abort: cannot specify both --abort and --continue
  [10]

  $ hg graft --abort --stop
  abort: cannot specify both --abort and --stop
  [10]

  $ hg graft --abort --currentuser
  abort: cannot specify both --abort and --user
  [10]

  $ hg graft --abort --edit
  abort: cannot specify both --abort and --edit
  [10]

#if abortcommand
when in dry-run mode
  $ hg abort --dry-run
  graft in progress, will be aborted
#endif

  $ hg abort
  graft aborted
  working directory is now at 9150fe93bec6
  $ hg log -GT "{rev}:{node|short} {desc}"
  o  5:36b793615f78 added foo to c
  |
  | o  4:863a25e1a9ea added x
  |/
  | @  3:9150fe93bec6 added d
  | |
  | o  2:155349b645be added c
  |/
  o  1:5f6d8a4bf34a added b
  |
  o  0:9092f1db7931 added a
  
when stripping is not required
  $ hg graft -r 5
  grafting 5:36b793615f78 "added foo to c" (tip)
  merging c
  warning: conflicts while merging c! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ hg abort
  graft aborted
  working directory is now at 9150fe93bec6
  $ hg log -GT "{rev}:{node|short} {desc}"
  o  5:36b793615f78 added foo to c
  |
  | o  4:863a25e1a9ea added x
  |/
  | @  3:9150fe93bec6 added d
  | |
  | o  2:155349b645be added c
  |/
  o  1:5f6d8a4bf34a added b
  |
  o  0:9092f1db7931 added a
  
when some of the changesets became public

  $ hg graft -r 4 -r 5
  grafting 4:863a25e1a9ea "added x"
  grafting 5:36b793615f78 "added foo to c" (tip)
  merging c
  warning: conflicts while merging c! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ hg log -GT "{rev}:{node|short} {desc}"
  @  6:6ec71c037d94 added x
  |
  | %  5:36b793615f78 added foo to c
  | |
  | | o  4:863a25e1a9ea added x
  | |/
  o |  3:9150fe93bec6 added d
  | |
  o |  2:155349b645be added c
  |/
  o  1:5f6d8a4bf34a added b
  |
  o  0:9092f1db7931 added a
  
  $ hg phase -r 6 --public

  $ hg abort
  cannot clean up public changesets 6ec71c037d94
  graft aborted
  working directory is now at 6ec71c037d94

when we created new changesets on top of existing one

  $ hg up '.^^'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ echo y > y
  $ hg ci -Aqm "added y"
  $ echo z > z
  $ hg ci -Aqm "added z"

  $ hg up 3
  1 files updated, 0 files merged, 3 files removed, 0 files unresolved
  $ hg log -GT "{rev}:{node|short} {desc}"
  o  8:637f9e9bbfd4 added z
  |
  o  7:123221671fd4 added y
  |
  | o  6:6ec71c037d94 added x
  | |
  | | o  5:36b793615f78 added foo to c
  | | |
  | | | o  4:863a25e1a9ea added x
  | | |/
  | @ |  3:9150fe93bec6 added d
  |/ /
  o /  2:155349b645be added c
  |/
  o  1:5f6d8a4bf34a added b
  |
  o  0:9092f1db7931 added a
  
  $ hg graft -r 8 -r 7 -r 5
  grafting 8:637f9e9bbfd4 "added z" (tip)
  grafting 7:123221671fd4 "added y"
  grafting 5:36b793615f78 "added foo to c"
  merging c
  warning: conflicts while merging c! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ cd ..
  $ hg init pullrepo
  $ cd pullrepo
  $ cat >> .hg/hgrc <<EOF
  > [phases]
  > publish=False
  > EOF
  $ hg pull ../abortgraft --config phases.publish=False
  pulling from ../abortgraft
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 11 changesets with 9 changes to 8 files (+4 heads)
  new changesets 9092f1db7931:6b98ff0062dd (6 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg up 9
  5 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo w > w
  $ hg ci -Aqm "added w" --config phases.publish=False

  $ cd ../abortgraft
  $ hg pull ../pullrepo
  pulling from ../pullrepo
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)
  new changesets 311dfc6cf3bf (1 drafts)
  (run 'hg heads .' to see heads, 'hg merge' to merge)

  $ hg abort
  new changesets detected on destination branch, can't strip
  graft aborted
  working directory is now at 6b98ff0062dd

  $ cd ..

============================
Testing --no-commit option:|
============================

  $ hg init nocommit
  $ cd nocommit
  $ echo a > a
  $ hg ci -qAma
  $ echo b > b
  $ hg ci -qAmb
  $ hg up -q 0
  $ echo c > c
  $ hg ci -qAmc
  $ hg log -GT "{rev}:{node|short} {desc}\n"
  @  2:d36c0562f908 c
  |
  | o  1:d2ae7f538514 b
  |/
  o  0:cb9a9f314b8b a
  

Check reporting when --no-commit used with non-applicable options:

  $ hg graft 1 --no-commit -e
  abort: cannot specify both --no-commit and --edit
  [10]

  $ hg graft 1 --no-commit --log
  abort: cannot specify both --no-commit and --log
  [10]

  $ hg graft 1 --no-commit -D
  abort: cannot specify both --no-commit and --currentdate
  [10]

Test --no-commit is working:
  $ hg graft 1 --no-commit
  grafting 1:d2ae7f538514 "b"

  $ hg log -GT "{rev}:{node|short} {desc}\n"
  @  2:d36c0562f908 c
  |
  | o  1:d2ae7f538514 b
  |/
  o  0:cb9a9f314b8b a
  

  $ hg diff
  diff -r d36c0562f908 b
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/b	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +b

Prepare wrdir to check --no-commit is resepected after --continue:

  $ hg up -qC
  $ echo A>a
  $ hg ci -qm "A in file a"
  $ hg up -q 1
  $ echo B>a
  $ hg ci -qm "B in file a"
  $ hg log -GT "{rev}:{node|short} {desc}\n"
  @  4:2aa9ad1006ff B in file a
  |
  | o  3:09e253b87e17 A in file a
  | |
  | o  2:d36c0562f908 c
  | |
  o |  1:d2ae7f538514 b
  |/
  o  0:cb9a9f314b8b a
  

  $ hg graft 3 --no-commit
  grafting 3:09e253b87e17 "A in file a"
  merging a
  warning: conflicts while merging a! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

Resolve conflict:
  $ echo A>a
  $ hg resolve --mark
  (no more unresolved files)
  continue: hg graft --continue

  $ hg graft --continue
  grafting 3:09e253b87e17 "A in file a"
  $ hg log -GT "{rev}:{node|short} {desc}\n"
  @  4:2aa9ad1006ff B in file a
  |
  | o  3:09e253b87e17 A in file a
  | |
  | o  2:d36c0562f908 c
  | |
  o |  1:d2ae7f538514 b
  |/
  o  0:cb9a9f314b8b a
  
  $ hg diff
  diff -r 2aa9ad1006ff a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -B
  +A

  $ hg up -qC

Check --no-commit is resepected when passed with --continue:

  $ hg graft 3
  grafting 3:09e253b87e17 "A in file a"
  merging a
  warning: conflicts while merging a! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

Resolve conflict:
  $ echo A>a
  $ hg resolve --mark
  (no more unresolved files)
  continue: hg graft --continue

  $ hg graft --continue --no-commit
  grafting 3:09e253b87e17 "A in file a"
  $ hg diff
  diff -r 2aa9ad1006ff a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -B
  +A

  $ hg log -GT "{rev}:{node|short} {desc}\n"
  @  4:2aa9ad1006ff B in file a
  |
  | o  3:09e253b87e17 A in file a
  | |
  | o  2:d36c0562f908 c
  | |
  o |  1:d2ae7f538514 b
  |/
  o  0:cb9a9f314b8b a
  
  $ hg up -qC

Test --no-commit when graft multiple revisions:
When there is conflict:
  $ hg graft -r "2::3" --no-commit
  grafting 2:d36c0562f908 "c"
  grafting 3:09e253b87e17 "A in file a"
  merging a
  warning: conflicts while merging a! (edit, then use 'hg resolve --mark')
  abort: unresolved conflicts, can't continue
  (use 'hg resolve' and 'hg graft --continue')
  [1]

  $ echo A>a
  $ hg resolve --mark
  (no more unresolved files)
  continue: hg graft --continue
  $ hg graft --continue
  grafting 3:09e253b87e17 "A in file a"
  $ hg diff
  diff -r 2aa9ad1006ff a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -B
  +A
  diff -r 2aa9ad1006ff c
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/c	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +c

  $ hg log -GT "{rev}:{node|short} {desc}\n"
  @  4:2aa9ad1006ff B in file a
  |
  | o  3:09e253b87e17 A in file a
  | |
  | o  2:d36c0562f908 c
  | |
  o |  1:d2ae7f538514 b
  |/
  o  0:cb9a9f314b8b a
  
  $ hg up -qC

When there is no conflict:
  $ echo d>d
  $ hg add d -q
  $ hg ci -qmd
  $ hg up 3 -q
  $ hg log -GT "{rev}:{node|short} {desc}\n"
  o  5:baefa8927fc0 d
  |
  o  4:2aa9ad1006ff B in file a
  |
  | @  3:09e253b87e17 A in file a
  | |
  | o  2:d36c0562f908 c
  | |
  o |  1:d2ae7f538514 b
  |/
  o  0:cb9a9f314b8b a
  

  $ hg graft -r 1 -r 5 --no-commit
  grafting 1:d2ae7f538514 "b"
  grafting 5:baefa8927fc0 "d" (tip)
  $ hg diff
  diff -r 09e253b87e17 b
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/b	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +b
  diff -r 09e253b87e17 d
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/d	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +d
  $ hg log -GT "{rev}:{node|short} {desc}\n"
  o  5:baefa8927fc0 d
  |
  o  4:2aa9ad1006ff B in file a
  |
  | @  3:09e253b87e17 A in file a
  | |
  | o  2:d36c0562f908 c
  | |
  o |  1:d2ae7f538514 b
  |/
  o  0:cb9a9f314b8b a
  
  $ cd ..

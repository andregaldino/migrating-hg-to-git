#testcases dirstate-v1 dirstate-v2

#if dirstate-v2
  $ cat >> $HGRCPATH << EOF
  > [format]
  > use-dirstate-v2=1
  > [storage]
  > dirstate-v2.slow-path=allow
  > EOF
#endif

Checking the size/permissions/file-type of files stored in the
dirstate after an update where the files are changed concurrently
outside of hg's control.

  $ hg init repo
  $ cd repo
  $ echo a > a
  $ hg commit -qAm _
  $ echo aa > a
  $ hg commit -m _
# this sleep is there to ensure current time has -at-least- one second away
# from the current time. It ensure the mtime is not ambiguous. If the test
# "sleep" longer this will be fine.
# It is not used to synchronise parallele operation so it is "fine" to use it.
  $ sleep 1
  $ hg status

  $ hg debugdirstate --no-dates
  n 644          3 (set  |unset)               a (re)

  $ cat >> $TESTTMP/dirstaterace.py << EOF
  > import time
  > from mercurial import (
  >     commit,
  >     extensions,
  >     merge,
  > )
  > def extsetup(ui):
  >     extensions.wrapfunction(merge, 'applyupdates', wrap(0))
  >     extensions.wrapfunction(commit, 'commitctx', wrap(1))
  > def wrap(duration):
  >     def new(orig, *args, **kwargs):
  >         res = orig(*args, **kwargs)
  >         with open("a", "w"):
  >             pass # just truncate the file
  >         time.sleep(duration)
  >         return res
  >     return new
  > EOF

Do an update where file 'a' is changed between hg writing it to disk
and hg writing the dirstate. The dirstate is correct nonetheless, and
so hg status correctly shows a as clean.

  $ hg up -r 0 --config extensions.race=$TESTTMP/dirstaterace.py
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugdirstate --no-dates
  n 644          2 (set  |unset)               a (re)
  $ echo a > a; hg status; hg diff

Do a commit where file 'a' is changed between hg committing its new
revision into the repository, and the writing of the dirstate.

This used to results in a corrupted dirstate (size did not match committed size).

  $ echo aaa > a; hg commit -qm _
  $ hg merge -qr 1; hg resolve -m; rm a.orig
  warning: conflicts while merging a! (edit, then use 'hg resolve --mark')
  (no more unresolved files)
  $ cat a
  <<<<<<< working copy: be46f74ce38d - test: _
  aaa
  =======
  aa
  >>>>>>> merge rev:    eb3fc6c17aa3 - test: _
  $ hg debugdirstate --no-dates
  m   0         -2 (set  |unset)               a (re)
  $ hg commit -m _ --config extensions.race=$TESTTMP/dirstaterace.py
  $ hg debugdirstate --no-dates
  n   0         -1 unset               a
  $ cat a | wc -c
   *0 (re)
  $ hg cat -r . a | wc -c
   *105 (re)
  $ hg status; hg diff --stat
  M a
   a |  5 -----
   1 files changed, 0 insertions(+), 5 deletions(-)

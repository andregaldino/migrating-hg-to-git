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
  > from mercurial import (
  >     extensions,
  >     merge,
  > )
  > def extsetup(ui):
  >     extensions.wrapfunction(merge, 'applyupdates', wrap)
  > def wrap(orig, *args, **kwargs):
  >     res = orig(*args, **kwargs)
  >     with open("a", "w"):
  >         pass # just truncate the file
  >     return res
  > EOF

Do an update where file 'a' is changed between hg writing it to disk
and hg writing the dirstate. The dirstate is correct nonetheless, and
so hg status correctly shows a as clean.

  $ hg up -r 0 --config extensions.race=$TESTTMP/dirstaterace.py
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugdirstate --no-dates
  n 644          2 (set  |unset)               a (re)
  $ echo a > a; hg status; hg diff

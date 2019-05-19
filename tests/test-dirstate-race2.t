Checking the size/permissions/file-type of files stored in the
dirstate after an update where the files are changed concurrently
outside of hg's control.

  $ hg init repo
  $ cd repo
  $ echo a > a
  $ hg commit -qAm _
  $ echo aa > a
  $ hg commit -m _

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
and hg writing the dirstate. It results in a corrupted dirstate, which
stores the wrong size, and thus hg status shows spuriously modified
files.

  $ hg up -r 0 --config extensions.race=$TESTTMP/dirstaterace.py
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugdirstate --no-dates
  n 644          0 (set  |unset)               a (re)
  $ echo a > a; hg status; hg diff
  M a

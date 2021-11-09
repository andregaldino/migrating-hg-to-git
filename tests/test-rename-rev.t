  $ hg init
  $ mkdir d1 d1/d11 d2
  $ echo d1/a > d1/a
  $ echo d1/ba > d1/ba
  $ echo d1/a1 > d1/d11/a1
  $ echo d1/b > d1/b
  $ echo d2/b > d2/b
  $ hg add d1/a d1/b d1/ba d1/d11/a1 d2/b
  $ hg commit -m "intial"


Test single file

# One recorded copy, one copy to record after commit
  $ hg cp d1/b d1/c
  $ cp d1/b d1/d
  $ hg add d1/d
  $ hg ci -m 'copy d1/b to d1/c and d1/d'
  $ hg st -C --change .
  A d1/c
    d1/b
  A d1/d
# Errors out without --after for now
  $ hg cp --at-rev . d1/b d1/d
  abort: --at-rev requires --after
  [10]
# Errors out with non-existent source
  $ hg cp -A --at-rev . d1/non-existent d1/d
  d1/non-existent: no such file in rev 55d1fd85ef0a
  abort: no files to copy
  [10]
# Errors out with non-existent destination
  $ hg cp -A --at-rev . d1/b d1/non-existent
  abort: d1/non-existent: copy destination does not exist in 8a9d70fa20c9
  [10]
# Successful invocation
  $ hg cp -A --at-rev . d1/b d1/d
  saved backup bundle to $TESTTMP/.hg/strip-backup/8a9d70fa20c9-973ae357-copy.hg
# New copy is recorded, and previously recorded copy is also still there
  $ hg st -C --change .
  A d1/c
    d1/b
  A d1/d
    d1/b
# Should get helpful message if we try to copy or rename after commit
  $ hg cp --forget --at-rev . d1/d
  saved backup bundle to $TESTTMP/.hg/strip-backup/3f7c325d3f9e-46f377bb-uncopy.hg
  $ hg cp d1/b d1/d
  d1/d: not overwriting - file already committed
  ('hg copy --at-rev .' to record the copy in the parent of the working copy)
  [1]
  $ hg mv d1/b d1/d
  d1/d: not overwriting - file already committed
  ('hg rename --at-rev .' to record the rename in the parent of the working copy)
  [1]

Test moved file (not copied) using 'hg cp' command

  $ hg co 0
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ mv d1/b d1/d
  $ hg rm -A d1/b
  $ hg add d1/d
  $ hg ci -m 'move d1/b to d1/d'
  created new head
  $ hg cp -A --at-rev . d1/b d1/d
  saved backup bundle to $TESTTMP/.hg/strip-backup/519850c3ea27-153c8fbb-copy.hg
  $ hg st -C --change .
  A d1/d
    d1/b
  R d1/b

Test moved file (not copied) using 'hg mv' command

  $ hg co 0
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ mv d1/b d1/d
  $ hg rm -A d1/b
  $ hg add d1/d
  $ hg ci -m 'move d1/b to d1/d'
  created new head
  $ hg mv -A --at-rev . d1/b d1/d
  saved backup bundle to $TESTTMP/.hg/strip-backup/519850c3ea27-153c8fbb-copy.hg
  $ hg st -C --change .
  A d1/d
    d1/b
  R d1/b

Test moved file (not copied) for which source still exists

  $ hg co 0
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ cp d1/b d1/d
  $ hg add d1/d
  $ hg ci -m 'copy d1/b to d1/d'
  created new head
  $ hg mv -A --at-rev . d1/b d1/d
  saved backup bundle to $TESTTMP/.hg/strip-backup/c8d0f6bcf7ca-1c9bb53e-copy.hg
  $ hg st -C --change .
  A d1/d
    d1/b

Test using directory as destination

  $ hg co 0
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ cp -R d1 d3
  $ hg add d3
  adding d3/a
  adding d3/b
  adding d3/ba
  adding d3/d11/a1
  $ hg ci -m 'copy d1/ to d3/'
  created new head
  $ hg cp -A --at-rev . d1 d3
  abort: d3: --at-rev does not support a directory as destination
  [10]


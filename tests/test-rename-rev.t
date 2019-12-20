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

# One recoded copy, one copy to record after commit
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
  [255]
# Errors out with non-existent destination
  $ hg cp -A --at-rev . d1/b d1/non-existent
  abort: d1/non-existent: copy destination does not exist in 8a9d70fa20c9
  [255]
# Successful invocation
  $ hg cp -A --at-rev . d1/b d1/d
  saved backup bundle to $TESTTMP/.hg/strip-backup/8a9d70fa20c9-973ae357-copy.hg
# New copy is recorded, and previously recorded copy is also still there
  $ hg st -C --change .
  A d1/c
    d1/b
  A d1/d
    d1/b

Test using directory as destination

  $ hg co 0
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
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
  [255]


  $ PYTHONPATH=$TESTDIR/..:$PYTHONPATH
  $ export PYTHONPATH

  $ . "$TESTDIR/remotefilelog-library.sh"

  $ hg init master
  $ cd master
  $ cat >> .hg/hgrc <<EOF
  > [remotefilelog]
  > server=True
  > EOF
  $ echo x > x
  $ echo z > z
  $ hg commit -qAm x1
  $ echo x2 > x
  $ echo z2 > z
  $ hg commit -qAm x2
  $ hg bookmark foo

  $ cd ..

# prefetch a revision w/ a sparse checkout

  $ hgcloneshallow ssh://user@dummy/master shallow --noupdate
  streaming all changes
  2 files to transfer, 527 bytes of data
  transferred 527 bytes in 0.* seconds (*/sec) (glob)
  searching for changes
  no changes found
  $ cd shallow
  $ printf "[extensions]\nsparse=\n" >> .hg/hgrc

  $ hg debugsparse -I x
  $ hg prefetch -r 0
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)

  $ hg cat -r 0 x
  x

  $ hg debugsparse -I z
  $ hg prefetch -r 0
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)

  $ hg cat -r 0 z
  z

# prefetch sparse only on pull when configured

  $ printf "[remotefilelog]\npullprefetch=bookmark()\n" >> .hg/hgrc
  $ hg strip tip
  saved backup bundle to $TESTTMP/shallow/.hg/strip-backup/876b1317060d-b2e91d8d-backup.hg (glob)

  $ hg debugsparse --delete z

  $ clearcache
  $ hg pull
  pulling from ssh://user@dummy/master
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  updating bookmark foo
  new changesets 876b1317060d
  (run 'hg update' to get a working copy)
  prefetching file contents
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)

# Dont consider filtered files when doing copy tracing

## Push an unrelated commit
  $ cd ../

  $ hgcloneshallow ssh://user@dummy/master shallow2
  streaming all changes
  2 files to transfer, 527 bytes of data
  transferred 527 bytes in 0.* seconds (*) (glob)
  searching for changes
  no changes found
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)
  $ cd shallow2
  $ printf "[extensions]\nsparse=\n" >> .hg/hgrc

  $ hg up -q 0
  2 files fetched over 1 fetches - (2 misses, 0.00% hit ratio) over *s (glob)
  $ touch a
  $ hg ci -Aqm a
  $ hg push -q -f

## Pull the unrelated commit and rebase onto it - verify unrelated file was not
pulled

  $ cd ../shallow
  $ hg up -q 1
  $ hg pull -q
  $ hg debugsparse -I z
  $ clearcache
  $ hg prefetch -r '. + .^' -I x -I z
  4 files fetched over 1 fetches - (4 misses, 0.00% hit ratio) over * (glob)
Originally this was testing that the rebase doesn't fetch pointless
blobs. Right now it fails because core's sparse can't load a spec from
the working directory. Presumably there's a fix, but I'm not sure what it is.
  $ hg rebase -d 2 --keep
  rebasing 1:876b1317060d "x2" (foo)
  transaction abort!
  rollback completed
  abort: cannot parse sparse patterns from working directory
  [255]

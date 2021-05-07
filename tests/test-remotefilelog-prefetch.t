#require no-windows

  $ . "$TESTDIR/remotefilelog-library.sh"

  $ hg init master
  $ cd master
  $ cat >> .hg/hgrc <<EOF
  > [remotefilelog]
  > server=True
  > EOF
  $ echo x > x
  $ echo z > z
  $ hg commit -qAm x
  $ echo x2 > x
  $ echo y > y
  $ hg commit -qAm y
  $ hg bookmark foo

  $ cd ..

# prefetch a revision

  $ hgcloneshallow ssh://user@dummy/master shallow --noupdate
  streaming all changes
  2 files to transfer, 528 bytes of data (no-zstd !)
  transferred 528 bytes in * seconds (* */sec) (glob) (no-zstd !)
  2 files to transfer, 532 bytes of data (zstd !)
  transferred 532 bytes in * seconds (* */sec) (glob) (zstd !)
  searching for changes
  no changes found
  $ cd shallow

  $ hg prefetch -r 0
  2 files fetched over 1 fetches - (2 misses, 0.00% hit ratio) over *s (glob)

  $ hg cat -r 0 x
  x

# prefetch with base

  $ clearcache
  $ hg prefetch -r 0::1 -b 0
  2 files fetched over 1 fetches - (2 misses, 0.00% hit ratio) over *s (glob)

  $ hg cat -r 1 x
  x2
  $ hg cat -r 1 y
  y

  $ hg cat -r 0 x
  x
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)

  $ hg cat -r 0 z
  z
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)

  $ hg prefetch -r 0::1 --base 0
  $ hg prefetch -r 0::1 -b 1
  $ hg prefetch -r 0::1

# prefetch a range of revisions

  $ clearcache
  $ hg prefetch -r 0::1
  4 files fetched over 1 fetches - (4 misses, 0.00% hit ratio) over *s (glob)

  $ hg cat -r 0 x
  x
  $ hg cat -r 1 x
  x2

# prefetch certain files

  $ clearcache
  $ hg prefetch -r 1 x
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)

  $ hg cat -r 1 x
  x2

  $ hg cat -r 1 y
  y
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)

# prefetch on pull when configured

  $ printf "[remotefilelog]\npullprefetch=bookmark()\n" >> .hg/hgrc
  $ hg strip tip
  saved backup bundle to $TESTTMP/shallow/.hg/strip-backup/109c3a557a73-3f43405e-backup.hg (glob)
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)

  $ clearcache
  $ hg pull
  pulling from ssh://user@dummy/master
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  updating bookmark foo
  added 1 changesets with 0 changes to 0 files
  new changesets 109c3a557a73
  (run 'hg update' to get a working copy)
  prefetching file contents
  3 files fetched over 1 fetches - (3 misses, 0.00% hit ratio) over *s (glob)

  $ hg up tip
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved

# prefetch only fetches changes not in working copy

  $ hg strip tip
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  saved backup bundle to $TESTTMP/shallow/.hg/strip-backup/109c3a557a73-3f43405e-backup.hg (glob)
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)
  $ clearcache

  $ hg pull
  pulling from ssh://user@dummy/master
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  updating bookmark foo
  added 1 changesets with 0 changes to 0 files
  new changesets 109c3a557a73
  (run 'hg update' to get a working copy)
  prefetching file contents
  2 files fetched over 1 fetches - (2 misses, 0.00% hit ratio) over *s (glob)

# Make some local commits that produce the same file versions as are on the
# server. To simulate a situation where we have local commits that were somehow
# pushed, and we will soon pull.

  $ hg prefetch -r 'all()'
  2 files fetched over 1 fetches - (2 misses, 0.00% hit ratio) over *s (glob)
  $ hg strip -q -r 0
  $ echo x > x
  $ echo z > z
  $ hg commit -qAm x
  $ echo x2 > x
  $ echo y > y
  $ hg commit -qAm y

# prefetch server versions, even if local versions are available

  $ clearcache
  $ hg strip -q tip
  $ hg pull
  pulling from ssh://user@dummy/master
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  updating bookmark foo
  added 1 changesets with 0 changes to 0 files
  new changesets 109c3a557a73
  1 local changesets published (?)
  (run 'hg update' to get a working copy)
  prefetching file contents
  2 files fetched over 1 fetches - (2 misses, 0.00% hit ratio) over *s (glob)

  $ cd ..

# Prefetch unknown files during checkout

  $ hgcloneshallow ssh://user@dummy/master shallow2
  streaming all changes
  2 files to transfer, 528 bytes of data (no-zstd !)
  transferred 528 bytes in * seconds * (glob) (no-zstd !)
  2 files to transfer, 532 bytes of data (zstd !)
  transferred 532 bytes in * seconds (* */sec) (glob) (zstd !)
  searching for changes
  no changes found
  updating to branch default
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over * (glob)
  $ cd shallow2
  $ hg up -q null
  $ echo x > x
  $ echo y > y
  $ echo z > z
  $ clearcache
  $ hg up tip
  x: untracked file differs
  3 files fetched over 1 fetches - (3 misses, 0.00% hit ratio) over * (glob)
  abort: untracked files in working directory differ from files in requested revision
  [20]
  $ hg revert --all

# Test batch fetching of lookup files during hg status
  $ hg up --clean tip
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugrebuilddirstate
  $ clearcache
  $ hg status
  3 files fetched over 1 fetches - (3 misses, 0.00% hit ratio) over * (glob)

# Prefetch during addrename detection
  $ hg up -q --clean tip
  $ hg revert --all
  $ mv x x2
  $ mv y y2
  $ mv z z2
  $ echo a > a
  $ hg add a
  $ rm a
  $ clearcache
  $ hg addremove -s 50 > /dev/null
  3 files fetched over 1 fetches - (3 misses, 0.00% hit ratio) over * (glob)
  $ hg revert --all
  forgetting x2
  forgetting y2
  forgetting z2
  undeleting x
  undeleting y
  undeleting z


# Revert across double renames. Note: the scary "abort", error is because
# https://bz.mercurial-scm.org/5419 .

  $ cd ../master
  $ hg mv z z2
  $ hg commit -m 'move z -> z2'
  $ cd ../shallow2
  $ hg pull -q
  $ clearcache
  $ hg mv y y2
  y2: not overwriting - file exists
  ('hg rename --after' to record the rename)
  [1]
  $ hg mv x x2
  x2: not overwriting - file exists
  ('hg rename --after' to record the rename)
  [1]
  $ hg mv z2 z3
  z2: not copying - file is not managed
  abort: no files to copy
  (maybe you meant to use --after --at-rev=.)
  [10]
  $ find $CACHEDIR -type f | sort
.. The following output line about files fetches is globed because it is
.. flaky, the core the test is checked when checking the cache dir, so
.. hopefully this flakyness is not hiding any actual bug.
  $ hg revert -a -r 1 || true
  ? files fetched over 1 fetches - (? misses, 0.00% hit ratio) over * (glob)
  abort: z2@109c3a557a73: not found in manifest (?)
  $ find $CACHEDIR -type f | sort
  $TESTTMP/hgcache/master/11/f6ad8ec52a2984abaafd7c3b516503785c2072/ef95c5376f34698742fe34f315fd82136f8f68c0
  $TESTTMP/hgcache/master/39/5df8f7c51f007019cb30201c49e884b46b92fa/69a1b67522704ec122181c0890bd16e9d3e7516a
  $TESTTMP/hgcache/master/95/cb0bfd2977c761298d9624e4b4d4c72a39974a/076f5e2225b3ff0400b98c92aa6cdf403ee24cca
  $TESTTMP/hgcache/repos

# warning when we have excess remotefilelog fetching

  $ cat > repeated_fetch.py << EOF
  > import binascii
  > from mercurial import extensions, registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'repeated-fetch', [], b'', inferrepo=True)
  > def repeated_fetch(ui, repo, *args, **opts):
  >     for i in range(20):
  >         try:
  >             hexid = (b'%02x' % (i + 1)) * 20
  >             repo.fileservice.prefetch([(b'somefile.txt', hexid)])
  >         except Exception:
  >             pass
  > EOF

We should only output to the user once. We're ignoring most of the output
because we're not actually fetching anything real here, all the hashes are
bogus, so it's just going to be errors and a final summary of all the misses.
  $ hg --config extensions.repeated_fetch=repeated_fetch.py \
  >    --config remotefilelog.fetchwarning="fetch warning!" \
  >    --config extensions.blackbox= \
  >    repeated-fetch 2>&1 | grep 'fetch warning'
  fetch warning!

We should output to blackbox three times, with a stack trace on each (though
that isn't tested here).
  $ grep 'excess remotefilelog fetching' .hg/blackbox.log
  .* excess remotefilelog fetching: (re)
  .* excess remotefilelog fetching: (re)
  .* excess remotefilelog fetching: (re)

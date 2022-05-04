Make a narrow clone then archive it
  $ . "$TESTDIR/narrow-library.sh"

  $ hg init master
  $ cd master

  $ for x in `$TESTDIR/seq.py 3`; do
  >   echo $x > "f$x"
  >   hg add "f$x"
  >   hg commit -m "Add $x"
  > done
  $ cat >> .hg/hgrc << EOF
  > [narrowacl]
  > default.includes=f1 f2
  > EOF
  $ hg serve -a localhost -p $HGPORT1 -d --pid-file=hg.pid
  $ cat hg.pid >> "$DAEMON_PIDS"

  $ cd ..
  $ hg clone http://localhost:$HGPORT1 narrowclone1
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 2 changes to 2 files
  new changesets * (glob)
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

The clone directory should only contain f1 and f2
  $ ls -A -1 narrowclone1 | sort
  .hg
  f1
  f2

Requirements should contain narrowhg
  $ hg debugrequires -R narrowclone1 | grep narrowhg
  narrowhg-experimental

NarrowHG should track f1 and f2
  $ hg -R narrowclone1 tracked
  I path:f1
  I path:f2

Narrow should not be able to widen to include f3
  $ hg -R narrowclone1 tracked --addinclude f3
  comparing with http://localhost:$HGPORT1/
  searching for changes
  abort: The following includes are not accessible for test: ['path:f3']
  [255]
  $ ls -A -1 narrowclone1 | sort
  .hg
  f1
  f2
  $ hg -R narrowclone1 tracked
  I path:f1
  I path:f2

Narrow should allow widen to include f2
  $ hg -R narrowclone1 tracked --removeinclude f2 > /dev/null
  $ hg -R narrowclone1 tracked
  I path:f1
  $ ls -A -1 narrowclone1 | sort
  .hg
  f1
  $ hg -R narrowclone1 tracked --addinclude f2
  comparing with http://localhost:$HGPORT1/
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 0 changesets with 1 changes to 1 files
  $ hg -R narrowclone1 tracked
  I path:f1
  I path:f2
  $ ls -A -1 narrowclone1 | sort
  .hg
  f1
  f2

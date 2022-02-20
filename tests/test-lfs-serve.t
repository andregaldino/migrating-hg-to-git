#testcases lfsremote-on lfsremote-off
#require serve no-reposimplestore no-chg

This test splits `hg serve` with and without using the extension into separate
tests cases.  The tests are broken down as follows, where "LFS"/"No-LFS"
indicates whether or not there are commits that use an LFS file, and "D"/"E"
indicates whether or not the extension is loaded.  The "X" cases are not tested
individually, because the lfs requirement causes the process to bail early if
the extension is disabled.

.                        Server
.
.                    No-LFS        LFS
.            +----------------------------+
.            |   ||  D  |  E  |  D  |  E  |
.            |---++=======================|
.  C         | D || N/A | #1  |  X  | #4  |
.  l    No   +---++-----------------------|
.  i    LFS  | E || #2  | #2  |  X  | #5  |
.  e         +---++-----------------------|
.  n         | D ||  X  |  X  |  X  |  X  |
.  t    LFS  |---++-----------------------|
.            | E || #3  | #3  |  X  | #6  |
.            |---++-----------------------+

make command server magic visible

#if windows
  $ PYTHONPATH="$TESTDIR/../contrib;$PYTHONPATH"
#else
  $ PYTHONPATH="$TESTDIR/../contrib:$PYTHONPATH"
#endif
  $ export PYTHONPATH

  $ hg init server
  $ SERVER_REQUIRES="$TESTTMP/server/.hg/requires"
  $ SERVER_PATH="$TESTTMP/server/"

  $ cat > $TESTTMP/debugprocessors.py <<EOF
  > from mercurial import (
  >     cmdutil,
  >     commands,
  >     pycompat,
  >     registrar,
  > )
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'debugprocessors', [], b'FILE')
  > def debugprocessors(ui, repo, file_=None, **opts):
  >     opts = pycompat.byteskwargs(opts)
  >     opts[b'changelog'] = False
  >     opts[b'manifest'] = False
  >     opts[b'dir'] = False
  >     rl = cmdutil.openrevlog(repo, b'debugprocessors', file_, opts)
  >     for flag, proc in rl._flagprocessors.items():
  >         ui.status(b"registered processor '%#x'\n" % (flag))
  > EOF

Skip the experimental.changegroup3=True config.  Failure to agree on this comes
first, and causes an "abort: no common changegroup version" if the extension is
only loaded on one side. If that *is* enabled, the subsequent failure is "abort:
missing processor for flag '0x2000'!" if the extension is only loaded on one side
(possibly also masked by the Internal Server Error message).
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > debugprocessors = $TESTTMP/debugprocessors.py
  > [experimental]
  > lfs.disableusercache = True
  > lfs.worker-enable = False
  > [lfs]
  > threshold=10
  > [web]
  > allow_push=*
  > push_ssl=False
  > EOF

  $ cp $HGRCPATH $HGRCPATH.orig

#if lfsremote-on
  $ hg --config extensions.lfs= -R server \
  >    serve -p $HGPORT -d --pid-file=hg.pid --errorlog=$TESTTMP/errors.log
#else
  $ hg --config extensions.lfs=! -R server \
  >    serve -p $HGPORT -d --pid-file=hg.pid --errorlog=$TESTTMP/errors.log
#endif

  $ cat hg.pid >> $DAEMON_PIDS
  $ hg clone -q http://localhost:$HGPORT client
  $ hg debugrequires -R client | grep 'lfs'
  [1]
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  [1]

This trivial repo will force commandserver to load the extension, but not call
reposetup() on another repo actually being operated on.  This gives coverage
that wrapper functions are not assuming reposetup() was called.

  $ hg init $TESTTMP/cmdservelfs
  $ cat >> $TESTTMP/cmdservelfs/.hg/hgrc << EOF
  > [extensions]
  > lfs =
  > EOF

--------------------------------------------------------------------------------
Case #1: client with non-lfs content and the extension disabled; server with
non-lfs content, and the extension enabled.

  $ cd client
  $ echo 'non-lfs' > nonlfs.txt
  >>> from hgclient import check, readchannel, runcommand
  >>> @check
  ... def diff(server):
  ...     readchannel(server)
  ...     # run an arbitrary command in the repo with the extension loaded
  ...     runcommand(server, [b'id', b'-R', b'../cmdservelfs'])
  ...     # now run a command in a repo without the extension to ensure that
  ...     # files are added safely..
  ...     runcommand(server, [b'ci', b'-Aqm', b'non-lfs'])
  ...     # .. and that scmutil.prefetchfiles() safely no-ops..
  ...     runcommand(server, [b'diff', b'-r', b'.~1'])
  ...     # .. and that debugupgraderepo safely no-ops.
  ...     runcommand(server, [b'debugupgraderepo', b'-q', b'--run'])
  *** runcommand id -R ../cmdservelfs
  000000000000 tip
  *** runcommand ci -Aqm non-lfs
  *** runcommand diff -r .~1
  diff -r 000000000000 nonlfs.txt
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/nonlfs.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +non-lfs
  *** runcommand debugupgraderepo -q --run

  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  [1]

#if lfsremote-on

  $ hg push -q
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  [1]

  $ hg clone -q http://localhost:$HGPORT $TESTTMP/client1_clone
  $ hg debugrequires -R $TESTTMP/client1_clone/ | grep 'lfs'
  [1]
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  [1]

  $ hg init $TESTTMP/client1_pull
  $ hg -R $TESTTMP/client1_pull pull -q http://localhost:$HGPORT
  $ hg debugrequires -R $TESTTMP/client1_pull/ | grep 'lfs'
  [1]
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  [1]
  $ hg identify http://localhost:$HGPORT
  d437e1d24fbd

#endif

--------------------------------------------------------------------------------
Case #2: client with non-lfs content and the extension enabled; server with
non-lfs content, and the extension state controlled by #testcases.

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > lfs =
  > EOF
  $ echo 'non-lfs' > nonlfs2.txt
  $ hg ci -Aqm 'non-lfs file with lfs client'

Since no lfs content has been added yet, the push is allowed, even when the
extension is not enabled remotely.

  $ hg push -q
  $ hg debugrequires | grep 'lfs'
  [1]
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  [1]

  $ hg clone -q http://localhost:$HGPORT $TESTTMP/client2_clone
  $ hg debugrequires -R $TESTTMP/client2_clone/ | grep 'lfs'
  [1]
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  [1]

  $ hg init $TESTTMP/client2_pull
  $ hg -R $TESTTMP/client2_pull pull -q http://localhost:$HGPORT
  $ hg debugrequires -R $TESTTMP/client2_pull/ | grep 'lfs'
  [1]
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  [1]

  $ hg identify http://localhost:$HGPORT
  1477875038c6

--------------------------------------------------------------------------------
Case #3: client with lfs content and the extension enabled; server with
non-lfs content, and the extension state controlled by #testcases.  The server
should have an 'lfs' requirement after it picks up its first commit with a blob.

  $ echo 'this is a big lfs file' > lfs.bin
  $ hg ci -Aqm 'lfs'
  $ hg debugrequires | grep 'lfs'
  lfs
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  [1]

#if lfsremote-off
  $ hg push -q
  abort: required features are not supported in the destination: lfs
  (enable the lfs extension on the server)
  [255]
#else
  $ hg push -q
#endif
  $ hg debugrequires | grep 'lfs'
  lfs
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs' || true
  lfs (lfsremote-on !)

  $ hg clone -q http://localhost:$HGPORT $TESTTMP/client3_clone

  $ hg debugrequires -R $TESTTMP/client3_clone/ | grep 'lfs' || true
  lfs (lfsremote-on !)
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs' || true
  lfs (lfsremote-on !)

  $ hg init $TESTTMP/client3_pull
  $ hg -R $TESTTMP/client3_pull pull -q http://localhost:$HGPORT
  $ hg debugrequires -R $TESTTMP/client3_pull/ | grep 'lfs' || true
  lfs (lfsremote-on !)
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs' || true
  lfs (lfsremote-on !)

Test that the commit/changegroup requirement check hook can be run multiple
times.

  $ hg clone -qr 0 http://localhost:$HGPORT $TESTTMP/cmdserve_client3

  $ cd ../cmdserve_client3

  >>> from hgclient import check, readchannel, runcommand
  >>> @check
  ... def addrequirement(server):
  ...     readchannel(server)
  ...     # change the repo in a way that adds the lfs requirement
  ...     runcommand(server, [b'pull', b'-qu'])
  ...     # Now cause the requirement adding hook to fire again, without going
  ...     # through reposetup() again.
  ...     with open('file.txt', 'wb') as fp:
  ...         fp.write(b'data')
  ...     runcommand(server, [b'ci', b'-Aqm', b'non-lfs'])
  *** runcommand pull -qu
  *** runcommand ci -Aqm non-lfs

  $ cd ../client

The difference here is the push failed above when the extension isn't
enabled on the server.
  $ hg identify http://localhost:$HGPORT
  8374dc4052cb (lfsremote-on !)
  1477875038c6 (lfsremote-off !)

Don't bother testing the lfsremote-off cases- the server won't be able
to launch if there's lfs content and the extension is disabled.

#if lfsremote-on

--------------------------------------------------------------------------------
Case #4: client with non-lfs content and the extension disabled; server with
lfs content, and the extension enabled.

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > lfs = !
  > EOF

  $ hg init $TESTTMP/client4
  $ cd $TESTTMP/client4
  $ cat >> .hg/hgrc <<EOF
  > [paths]
  > default = http://localhost:$HGPORT
  > EOF
  $ echo 'non-lfs' > nonlfs2.txt
  $ hg ci -Aqm 'non-lfs'
  $ hg debugrequires -R $SERVER_PATH --config extensions.lfs= | grep 'lfs'
  lfs

  $ hg push -q --force
  warning: repository is unrelated
  $ hg debugrequires -R $SERVER_PATH --config extensions.lfs= | grep 'lfs'
  lfs

  $ hg clone http://localhost:$HGPORT $TESTTMP/client4_clone
  (remote is using large file support (lfs), but it is explicitly disabled in the local configuration)
  abort: repository requires features unknown to this Mercurial: lfs
  (see https://mercurial-scm.org/wiki/MissingRequirement for more information)
  [255]
  $ hg debugrequires -R $TESTTMP/client4_clone/ | grep 'lfs'
  abort: repository $TESTTMP/client4_clone/ not found
  [1]
  $ hg debugrequires -R $SERVER_PATH --config extensions.lfs= | grep 'lfs'
  lfs

TODO: fail more gracefully.

  $ hg init $TESTTMP/client4_pull
  $ hg -R $TESTTMP/client4_pull pull http://localhost:$HGPORT
  pulling from http://localhost:$HGPORT/
  requesting all changes
  remote: abort: no common changegroup version
  abort: pull failed on remote
  [100]
  $ hg debugrequires -R $TESTTMP/client4_pull/ | grep 'lfs'
  [1]
  $ hg debugrequires -R $SERVER_PATH --config extensions.lfs= | grep 'lfs'
  lfs

  $ hg identify http://localhost:$HGPORT
  03b080fa9d93

--------------------------------------------------------------------------------
Case #5: client with non-lfs content and the extension enabled; server with
lfs content, and the extension enabled.

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > lfs =
  > EOF
  $ echo 'non-lfs' > nonlfs3.txt
  $ hg ci -Aqm 'non-lfs file with lfs client'

  $ hg push -q
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  lfs

  $ hg clone -q http://localhost:$HGPORT $TESTTMP/client5_clone
  $ hg debugrequires -R $TESTTMP/client5_clone/ | grep 'lfs'
  lfs
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  lfs

  $ hg init $TESTTMP/client5_pull
  $ hg -R $TESTTMP/client5_pull pull -q http://localhost:$HGPORT
  $ hg debugrequires -R $TESTTMP/client5_pull/ | grep 'lfs'
  lfs
  $ hg debugrequires -R $SERVER_PATH | grep 'lfs'
  lfs

  $ hg identify http://localhost:$HGPORT
  c729025cc5e3

  $ mv $HGRCPATH $HGRCPATH.tmp
  $ cp $HGRCPATH.orig $HGRCPATH

  >>> from hgclient import bprint, check, readchannel, runcommand, stdout
  >>> @check
  ... def checkflags(server):
  ...     readchannel(server)
  ...     bprint(b'')
  ...     bprint(b'# LFS required- both lfs and non-lfs revlogs have 0x2000 flag')
  ...     stdout.flush()
  ...     runcommand(server, [b'debugprocessors', b'lfs.bin', b'-R',
  ...                b'../server'])
  ...     runcommand(server, [b'debugprocessors', b'nonlfs2.txt', b'-R',
  ...                b'../server'])
  ...     runcommand(server, [b'config', b'extensions', b'--cwd',
  ...                b'../server'])
  ... 
  ...     bprint(b"\n# LFS not enabled- revlogs don't have 0x2000 flag")
  ...     stdout.flush()
  ...     runcommand(server, [b'debugprocessors', b'nonlfs3.txt'])
  ...     runcommand(server, [b'config', b'extensions'])
  
  # LFS required- both lfs and non-lfs revlogs have 0x2000 flag
  *** runcommand debugprocessors lfs.bin -R ../server
  registered processor '0x8000'
  registered processor '0x1000'
  registered processor '0x2000'
  *** runcommand debugprocessors nonlfs2.txt -R ../server
  registered processor '0x8000'
  registered processor '0x1000'
  registered processor '0x2000'
  *** runcommand config extensions --cwd ../server
  extensions.debugprocessors=$TESTTMP/debugprocessors.py
  extensions.lfs=
  
  # LFS not enabled- revlogs don't have 0x2000 flag
  *** runcommand debugprocessors nonlfs3.txt
  registered processor '0x8000'
  registered processor '0x1000'
  *** runcommand config extensions
  extensions.debugprocessors=$TESTTMP/debugprocessors.py

  $ rm $HGRCPATH
  $ mv $HGRCPATH.tmp $HGRCPATH

  $ hg clone $TESTTMP/client $TESTTMP/nonlfs -qr 0 --config extensions.lfs=
  $ cat >> $TESTTMP/nonlfs/.hg/hgrc <<EOF
  > [extensions]
  > lfs = !
  > EOF

  >>> from hgclient import bprint, check, readchannel, runcommand, stdout
  >>> @check
  ... def checkflags2(server):
  ...     readchannel(server)
  ...     bprint(b'')
  ...     bprint(b'# LFS enabled- both lfs and non-lfs revlogs have 0x2000 flag')
  ...     stdout.flush()
  ...     runcommand(server, [b'debugprocessors', b'lfs.bin', b'-R',
  ...                b'../server'])
  ...     runcommand(server, [b'debugprocessors', b'nonlfs2.txt', b'-R',
  ...                b'../server'])
  ...     runcommand(server, [b'config', b'extensions', b'--cwd',
  ...                b'../server'])
  ... 
  ...     bprint(b'\n# LFS enabled without requirement- revlogs have 0x2000 flag')
  ...     stdout.flush()
  ...     runcommand(server, [b'debugprocessors', b'nonlfs3.txt'])
  ...     runcommand(server, [b'config', b'extensions'])
  ... 
  ...     bprint(b"\n# LFS disabled locally- revlogs don't have 0x2000 flag")
  ...     stdout.flush()
  ...     runcommand(server, [b'debugprocessors', b'nonlfs.txt', b'-R',
  ...                b'../nonlfs'])
  ...     runcommand(server, [b'config', b'extensions', b'--cwd',
  ...                b'../nonlfs'])
  
  # LFS enabled- both lfs and non-lfs revlogs have 0x2000 flag
  *** runcommand debugprocessors lfs.bin -R ../server
  registered processor '0x8000'
  registered processor '0x1000'
  registered processor '0x2000'
  *** runcommand debugprocessors nonlfs2.txt -R ../server
  registered processor '0x8000'
  registered processor '0x1000'
  registered processor '0x2000'
  *** runcommand config extensions --cwd ../server
  extensions.debugprocessors=$TESTTMP/debugprocessors.py
  extensions.lfs=
  
  # LFS enabled without requirement- revlogs have 0x2000 flag
  *** runcommand debugprocessors nonlfs3.txt
  registered processor '0x8000'
  registered processor '0x1000'
  registered processor '0x2000'
  *** runcommand config extensions
  extensions.debugprocessors=$TESTTMP/debugprocessors.py
  extensions.lfs=
  
  # LFS disabled locally- revlogs don't have 0x2000 flag
  *** runcommand debugprocessors nonlfs.txt -R ../nonlfs
  registered processor '0x8000'
  registered processor '0x1000'
  *** runcommand config extensions --cwd ../nonlfs
  extensions.debugprocessors=$TESTTMP/debugprocessors.py
  extensions.lfs=!

--------------------------------------------------------------------------------
Case #6: client with lfs content and the extension enabled; server with
lfs content, and the extension enabled.

  $ echo 'this is another lfs file' > lfs2.txt
  $ hg ci -Aqm 'lfs file with lfs client'

  $ hg --config paths.default= push -v http://localhost:$HGPORT
  pushing to http://localhost:$HGPORT/
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  searching for changes
  remote has heads on branch 'default' that are not known locally: 8374dc4052cb
  lfs: uploading a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de (25 bytes)
  lfs: processed: a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de
  lfs: uploaded 1 files (25 bytes)
  1 changesets found
  uncompressed size of bundle content:
       206 (changelog)
       172 (manifests)
       275  lfs2.txt
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 1 changesets with 1 changes to 1 files
  (sent 8 HTTP requests and * bytes; received * bytes in responses) (glob) (?)
  $ hg debugrequires | grep lfs
  lfs
  $ hg debugrequires -R $SERVER_PATH | grep lfs
  lfs

  $ hg clone -q http://localhost:$HGPORT $TESTTMP/client6_clone
  $ hg debugrequires -R $TESTTMP/client6_clone/ | grep lfs
  lfs
  $ hg debugrequires -R $SERVER_PATH | grep lfs
  lfs

  $ hg init $TESTTMP/client6_pull
  $ hg -R $TESTTMP/client6_pull pull -u -v http://localhost:$HGPORT
  pulling from http://localhost:$HGPORT/
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  calling hook pretxnchangegroup.lfs: hgext.lfs.checkrequireslfs
  added 6 changesets with 5 changes to 5 files (+1 heads)
  new changesets d437e1d24fbd:d3b84d50eacb
  resolving manifests
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: downloading a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de (25 bytes)
  lfs: processed: a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de
  lfs: downloaded 1 files (25 bytes)
  getting lfs2.txt
  lfs: found a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de in the local lfs store
  getting nonlfs2.txt
  getting nonlfs3.txt
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  updated to "d3b84d50eacb: lfs file with lfs client"
  1 other heads for branch "default"
  (sent 3 HTTP requests and * bytes; received * bytes in responses) (glob)
  $ hg debugrequires -R $TESTTMP/client6_pull/ | grep lfs
  lfs
  $ hg debugrequires -R $SERVER_PATH | grep lfs
  lfs

  $ hg identify http://localhost:$HGPORT
  d3b84d50eacb

--------------------------------------------------------------------------------
Misc: process dies early if a requirement exists and the extension is disabled

  $ hg --config extensions.lfs=! summary
  abort: repository requires features unknown to this Mercurial: lfs
  (see https://mercurial-scm.org/wiki/MissingRequirement for more information)
  [255]

  $ echo 'this is an lfs file' > $TESTTMP/client6_clone/lfspair1.bin
  $ echo 'this is an lfs file too' > $TESTTMP/client6_clone/lfspair2.bin
  $ hg -R $TESTTMP/client6_clone ci -Aqm 'add lfs pair'
  $ hg -R $TESTTMP/client6_clone push -q

  $ hg clone -qU http://localhost:$HGPORT $TESTTMP/bulkfetch

Cat doesn't prefetch unless data is needed (e.g. '-T {rawdata}' doesn't need it)

  $ hg --cwd $TESTTMP/bulkfetch cat -vr tip lfspair1.bin -T '{rawdata}\n{path}\n'
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  version https://git-lfs.github.com/spec/v1
  oid sha256:cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782
  size 20
  x-is-binary 0
  
  lfspair1.bin

  $ hg --cwd $TESTTMP/bulkfetch cat -vr tip lfspair1.bin -T json
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  [lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: downloading cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782 (20 bytes)
  lfs: processed: cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782
  lfs: downloaded 1 files (20 bytes)
  lfs: found cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782 in the local lfs store
  
   {
    "data": "this is an lfs file\n",
    "path": "lfspair1.bin",
    "rawdata": "version https://git-lfs.github.com/spec/v1\noid sha256:cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782\nsize 20\nx-is-binary 0\n"
   }
  ]

  $ rm -r $TESTTMP/bulkfetch/.hg/store/lfs

  $ hg --cwd $TESTTMP/bulkfetch cat -vr tip lfspair1.bin -T '{data}\n'
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: downloading cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782 (20 bytes)
  lfs: processed: cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782
  lfs: downloaded 1 files (20 bytes)
  lfs: found cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782 in the local lfs store
  this is an lfs file
  
  $ hg --cwd $TESTTMP/bulkfetch cat -vr tip lfspair2.bin
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: downloading d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e (24 bytes)
  lfs: processed: d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e
  lfs: downloaded 1 files (24 bytes)
  lfs: found d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e in the local lfs store
  this is an lfs file too

Export will prefetch all needed files across all needed revisions

  $ rm -r $TESTTMP/bulkfetch/.hg/store/lfs
  $ hg -R $TESTTMP/bulkfetch -v export -r 0:tip -o all.export
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  exporting patches:
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: need to transfer 4 objects (92 bytes)
  lfs: downloading a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de (25 bytes)
  lfs: processed: a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de
  lfs: downloading bed80f00180ac404b843628ab56a1c1984d6145c391cd1628a7dd7d2598d71fc (23 bytes)
  lfs: processed: bed80f00180ac404b843628ab56a1c1984d6145c391cd1628a7dd7d2598d71fc
  lfs: downloading cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782 (20 bytes)
  lfs: processed: cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782
  lfs: downloading d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e (24 bytes)
  lfs: processed: d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e
  lfs: downloaded 4 files (92 bytes)
  all.export
  lfs: found bed80f00180ac404b843628ab56a1c1984d6145c391cd1628a7dd7d2598d71fc in the local lfs store
  lfs: found a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de in the local lfs store
  lfs: found cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782 in the local lfs store
  lfs: found d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e in the local lfs store

Export with selected files is used with `extdiff --patch`

  $ rm -r $TESTTMP/bulkfetch/.hg/store/lfs
  $ hg --config extensions.extdiff= \
  >    -R $TESTTMP/bulkfetch -v extdiff -r 2:tip --patch $TESTTMP/bulkfetch/lfs.bin
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: downloading bed80f00180ac404b843628ab56a1c1984d6145c391cd1628a7dd7d2598d71fc (23 bytes)
  lfs: processed: bed80f00180ac404b843628ab56a1c1984d6145c391cd1628a7dd7d2598d71fc
  lfs: downloaded 1 files (23 bytes)
  */hg-8374dc4052cb.patch (glob)
  lfs: found bed80f00180ac404b843628ab56a1c1984d6145c391cd1628a7dd7d2598d71fc in the local lfs store
  */hg-9640b57e77b1.patch (glob)
  --- */hg-8374dc4052cb.patch	* (glob)
  +++ */hg-9640b57e77b1.patch	* (glob)
  @@ -2,12 +2,7 @@
   # User test
   # Date 0 0
   #      Thu Jan 01 00:00:00 1970 +0000
  -# Node ID 8374dc4052cbd388e79d9dc4ddb29784097aa354
  -# Parent  1477875038c60152e391238920a16381c627b487
  -lfs
  +# Node ID 9640b57e77b14c3a0144fb4478b6cc13e13ea0d1
  +# Parent  d3b84d50eacbd56638e11abce6b8616aaba54420
  +add lfs pair
   
  -diff -r 1477875038c6 -r 8374dc4052cb lfs.bin
  ---- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  -+++ b/lfs.bin	Thu Jan 01 00:00:00 1970 +0000
  -@@ -0,0 +1,1 @@
  -+this is a big lfs file
  cleaning up temp directory
  [1]

Diff will prefetch files

  $ rm -r $TESTTMP/bulkfetch/.hg/store/lfs
  $ hg -R $TESTTMP/bulkfetch -v diff -r 2:tip
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: need to transfer 4 objects (92 bytes)
  lfs: downloading a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de (25 bytes)
  lfs: processed: a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de
  lfs: downloading bed80f00180ac404b843628ab56a1c1984d6145c391cd1628a7dd7d2598d71fc (23 bytes)
  lfs: processed: bed80f00180ac404b843628ab56a1c1984d6145c391cd1628a7dd7d2598d71fc
  lfs: downloading cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782 (20 bytes)
  lfs: processed: cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782
  lfs: downloading d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e (24 bytes)
  lfs: processed: d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e
  lfs: downloaded 4 files (92 bytes)
  lfs: found bed80f00180ac404b843628ab56a1c1984d6145c391cd1628a7dd7d2598d71fc in the local lfs store
  lfs: found a82f1c5cea0d40e3bb3a849686bb4e6ae47ca27e614de55c1ed0325698ef68de in the local lfs store
  lfs: found cf1b2787b74e66547d931b6ebe28ff63303e803cb2baa14a8f57c4383d875782 in the local lfs store
  lfs: found d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e in the local lfs store
  diff -r 8374dc4052cb -r 9640b57e77b1 lfs.bin
  --- a/lfs.bin	Thu Jan 01 00:00:00 1970 +0000
  +++ /dev/null	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +0,0 @@
  -this is a big lfs file
  diff -r 8374dc4052cb -r 9640b57e77b1 lfs2.txt
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/lfs2.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +this is another lfs file
  diff -r 8374dc4052cb -r 9640b57e77b1 lfspair1.bin
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/lfspair1.bin	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +this is an lfs file
  diff -r 8374dc4052cb -r 9640b57e77b1 lfspair2.bin
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/lfspair2.bin	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +this is an lfs file too
  diff -r 8374dc4052cb -r 9640b57e77b1 nonlfs.txt
  --- a/nonlfs.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ /dev/null	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +0,0 @@
  -non-lfs
  diff -r 8374dc4052cb -r 9640b57e77b1 nonlfs3.txt
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/nonlfs3.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +non-lfs

Only the files required by diff are prefetched

  $ rm -r $TESTTMP/bulkfetch/.hg/store/lfs
  $ hg -R $TESTTMP/bulkfetch -v diff -r 2:tip $TESTTMP/bulkfetch/lfspair2.bin
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: assuming remote store: http://localhost:$HGPORT/.git/info/lfs
  lfs: downloading d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e (24 bytes)
  lfs: processed: d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e
  lfs: downloaded 1 files (24 bytes)
  lfs: found d96eda2c74b56e95cfb5ffb66b6503e198cc6fc4a09dc877de925feebc65786e in the local lfs store
  diff -r 8374dc4052cb -r 9640b57e77b1 lfspair2.bin
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/lfspair2.bin	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +this is an lfs file too

#endif

  $ "$PYTHON" $TESTDIR/killdaemons.py $DAEMON_PIDS

  $ cat $TESTTMP/errors.log

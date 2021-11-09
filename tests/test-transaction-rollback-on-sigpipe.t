Test that, when an hg push is interrupted and the remote side receives SIGPIPE,
the remote hg is able to successfully roll back the transaction.

  $ hg init -q remote
  $ hg clone -q ssh://user@dummy/`pwd`/remote local
  $ SIGPIPE_REMOTE_DEBUG_FILE="$TESTTMP/DEBUGFILE"
  $ SYNCFILE1="$TESTTMP/SYNCFILE1"
  $ SYNCFILE2="$TESTTMP/SYNCFILE2"
  $ export SIGPIPE_REMOTE_DEBUG_FILE
  $ export SYNCFILE1
  $ export SYNCFILE2
  $ PYTHONUNBUFFERED=1
  $ export PYTHONUNBUFFERED

On the remote end, run hg, piping stdout and stderr through processes that we
know the PIDs of. We will later kill these to simulate an ssh client
disconnecting.

  $ remotecmd="$RUNTESTDIR/testlib/sigpipe-remote.py"

In the pretxnchangegroup hook, kill the PIDs recorded above to simulate ssh
disconnecting. Then exit nonzero, to force a transaction rollback.


  $ cat >remote/.hg/hgrc <<EOF
  > [hooks]
  > pretxnchangegroup.00-break-things=sh "$RUNTESTDIR/testlib/wait-on-file" 10 "$SYNCFILE2" "$SYNCFILE1"
  > pretxnchangegroup.01-output-things=echo "some remote output to be forward to the closed pipe"
  > pretxnchangegroup.02-output-things=echo "some more remote output"
  > EOF

  $ hg --cwd ./remote tip -T '{node|short}\n'
  000000000000
  $ cd local
  $ echo foo > foo ; hg commit -qAm "commit"

(use quiet to avoid flacky output from the server)

  $ hg push --quiet --remotecmd "$remotecmd"
  abort: stream ended unexpectedly (got 0 bytes, expected 4)
  [255]
  $ cat $SIGPIPE_REMOTE_DEBUG_FILE
  SIGPIPE-HELPER: Starting
  SIGPIPE-HELPER: Redirection in place
  SIGPIPE-HELPER: pipes closed in main
  SIGPIPE-HELPER: SYNCFILE1 detected
  SIGPIPE-HELPER: worker killed
  SIGPIPE-HELPER: creating SYNCFILE2
  SIGPIPE-HELPER: Shutting down
  SIGPIPE-HELPER: Server process terminated with status 255 (no-windows !)
  SIGPIPE-HELPER: Server process terminated with status 1 (windows !)
  SIGPIPE-HELPER: Shut down

The remote should be left in a good state
  $ hg --cwd ../remote tip -T '{node|short}\n'
  000000000000

#if windows

XXX-Windows Broken behavior to be fixed

Behavior on Windows is broken and should be fixed. However this is a fairly
corner case situation and no data are being corrupted. This would affect
central repository being hosted on a Windows machine and accessed using ssh.

This was catch as we setup new CI for Windows. Making the test pass on Windows
was enough of a pain that fixing the behavior set aside for now. Dear and
honorable reader, feel free to fix it.

  $ hg --cwd ../remote recover
  rolling back interrupted transaction
  (verify step skipped, run `hg verify` to check your repository content)

#else

  $ hg --cwd ../remote recover
  no interrupted transaction available
  [1]

#endif

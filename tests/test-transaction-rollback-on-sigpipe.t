Test that, when an hg push is interrupted and the remote side receives SIGPIPE,
the remote hg is able to successfully roll back the transaction.

  $ hg init -q remote
  $ hg clone -e "\"$PYTHON\" \"$RUNTESTDIR/dummyssh\"" -q ssh://user@dummy/`pwd`/remote local
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
  > pretxnchangegroup.00-break-things="$RUNTESTDIR/testlib/wait-on-file" 10 "$SYNCFILE2" "$SYNCFILE1"
  > pretxnchangegroup.01-output-things=echo "some remote output to be forward to the closed pipe"
  > EOF

  $ hg --cwd ./remote tip -T '{node|short}\n'
  000000000000
  $ cd local
  $ echo foo > foo ; hg commit -qAm "commit"
  $ hg push -e "\"$PYTHON\" \"$TESTDIR/dummyssh\"" --remotecmd "$remotecmd"
  pushing to ssh://user@dummy/$TESTTMP/remote
  searching for changes
  remote: adding changesets (py3 !)
  remote: adding manifests (py3 !)
  remote: adding file changes (py3 !)
  remote: adding changesets (no-py3 no-chg !)
  remote: adding manifests (no-py3 no-chg !)
  remote: adding file changes (no-py3 no-chg !)
  abort: stream ended unexpectedly (got 0 bytes, expected 4)
  [255]
  $ cat $SIGPIPE_REMOTE_DEBUG_FILE
  SIGPIPE-HELPER: Starting
  SIGPIPE-HELPER: Mercurial started
  SIGPIPE-HELPER: Redirection in place
  SIGPIPE-HELPER: SYNCFILE1 detected
  SIGPIPE-HELPER: pipes closed
  SIGPIPE-HELPER: creating SYNCFILE2
  SIGPIPE-HELPER: Shutting down
  SIGPIPE-HELPER: Server process terminated
  SIGPIPE-HELPER: Shut down

The remote should be left in a good state
  $ hg --cwd ../remote tip -T '{node|short}\n'
  000000000000
  $ hg --cwd ../remote recover
  no interrupted transaction available
  [1]

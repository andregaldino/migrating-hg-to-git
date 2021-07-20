#require no-windows no-rhg

XXX-RHG this test hangs if `hg` is really `rhg`. This was hidden by the use of
`alias hg=rhg` by run-tests.py. With such alias removed, this test is revealed
buggy. This need to be resolved sooner than later.

Dummy extension simulating unsafe long running command
  $ SYNC_FILE="$TESTTMP/sync-file"
  $ export SYNC_FILE
  $ DONE_FILE="$TESTTMP/done-file"
  $ export DONE_FILE
  $ 
  $ cat > wait_ext.py <<EOF
  > import os
  > import time
  > 
  > from mercurial.i18n import _
  > from mercurial import registrar
  > from mercurial import testing
  > 
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > 
  > @command(b'wait-signal', [], _(b'SYNC_FILE DONE_FILE'), norepo=True)
  > def sleep(ui, sync_file=b"$SYNC_FILE", done_file=b"$DONE_FILE", **opts):
  >     start = time.time()
  >     with ui.uninterruptible():
  >         testing.write_file(sync_file, b'%d' % os.getpid())
  >         testing.wait_file(done_file)
  >         ui.warn(b"end of unsafe operation\n")
  >     ui.warn(b"%d second(s) passed\n" % int(time.time() - start))
  > EOF

  $ cat > send-signal.sh << EOF
  > #!/bin/sh
  > SIG=\$1
  > if [ -z "\$SIG" ]; then
  >    echo "send-signal.sh requires one argument" >&2
  >    exit 1
  > fi
  > "$RUNTESTDIR/testlib/wait-on-file" 10 "$SYNC_FILE" || exit 2
  > kill -s \$SIG \`cat "$SYNC_FILE"\`
  > touch "$DONE_FILE"
  > EOF

#if no-windows
  $ chmod +x send-signal.sh
#endif

Kludge to emulate timeout(1) which is not generally available.

Set up repository
  $ hg init repo
  $ cd repo
  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > wait_ext = $TESTTMP/wait_ext.py
  > EOF


Test ctrl-c
  $ rm -f $SYNC_FILE $DONE_FILE
  $ sh -c "../send-signal.sh INT" &
  $ hg wait-signal
  interrupted!
  [255]

  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > nointerrupt = yes
  > EOF

  $ rm -f $SYNC_FILE $DONE_FILE
  $ sh -c "../send-signal.sh INT" &
  $ hg wait-signal
  interrupted!
  [255]

  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > nointerrupt-interactiveonly = False
  > EOF

  $ rm -f $SYNC_FILE $DONE_FILE
  $ sh -c "../send-signal.sh INT" &
  $ hg wait-signal
  shutting down cleanly
  press ^C again to terminate immediately (dangerous)
  end of unsafe operation
  interrupted!
  [255]

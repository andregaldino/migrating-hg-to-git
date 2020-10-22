#require serve

  $ hg clone http://localhost:$HGPORT/ copy
  abort: * (glob)
  [100]

  $ test -d copy
  [1]

  $ "$PYTHON" "$TESTDIR/dumbhttp.py" -p $HGPORT --pid dumb.pid
  $ cat dumb.pid >> $DAEMON_PIDS
  $ hg clone http://localhost:$HGPORT/foo copy2
  abort: HTTP Error 404: * (glob)
  [100]
  $ killdaemons.py

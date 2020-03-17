#require no-windows serve

  $ . "$TESTDIR/remotefilelog-library.sh"

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > remotefilelog=
  > share=
  > EOF

  $ hg init master
  $ cd master
  $ cat >> .hg/hgrc <<EOF
  > [remotefilelog]
  > server=True
  > EOF
  $ echo x > x
  $ hg commit -qAm x

  $ cd ..


  $ hgcloneshallow ssh://user@dummy/master wdir --noupdate -q
  $ cd wdir
  $ hg serve -n test -p $HGPORT -d --pid-file=hg.pid -E errors.log
  $ cat hg.pid >> $DAEMON_PIDS
  $ (get-with-headers.py localhost:$HGPORT 'file/tip/x')
  500 Internal Server Error
  
  Internal Server Error (no-eol)
  [1]


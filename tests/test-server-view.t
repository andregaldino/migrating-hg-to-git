  $ hg init test
  $ cd test
  $ hg debugbuilddag '+2'
  $ hg phase --public 0

  $ hg serve -p $HGPORT -d --pid-file=hg.pid -E errors.log
  $ cat hg.pid >> $DAEMON_PIDS
  $ cd ..
  $ hg init test2
  $ cd test2
  $ hg incoming http://foo:xyzzy@localhost:$HGPORT/
  comparing with http://foo:***@localhost:$HGPORT/
  changeset:   0:1ea73414a91b
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     r0
  
  changeset:   1:66f7d451a68b
  tag:         tip
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:01 1970 +0000
  summary:     r1
  
  $ killdaemons.py

  $ cd ../test
  $ hg --config server.view=immutable serve -p $HGPORT -d --pid-file=hg.pid -E errors.log
  $ cat hg.pid >> $DAEMON_PIDS
  $ cd ../test2
  $ hg incoming http://foo:xyzzy@localhost:$HGPORT/
  comparing with http://foo:***@localhost:$HGPORT/
  changeset:   0:1ea73414a91b
  tag:         tip
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     r0
  
  $ killdaemons.py

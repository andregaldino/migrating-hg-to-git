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

  $ cd ..
  $ hg -R test --config server.view=immutable serve -p $HGPORT -d --pid-file=hg.pid -E errors.log
  $ cat hg.pid >> $DAEMON_PIDS
  $ hg -R test2 incoming http://foo:xyzzy@localhost:$HGPORT/
  comparing with http://foo:***@localhost:$HGPORT/
  changeset:   0:1ea73414a91b
  tag:         tip
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     r0
  

Check same result using `experimental.extra-filter-revs`

  $ hg -R test --config experimental.extra-filter-revs='not public()' serve -p $HGPORT1 -d --pid-file=hg2.pid -E errors.log
  $ cat hg2.pid >> $DAEMON_PIDS
  $ hg -R test2 incoming http://foo:xyzzy@localhost:$HGPORT1/
  comparing with http://foo:***@localhost:$HGPORT1/
  changeset:   0:1ea73414a91b
  tag:         tip
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     r0
  
  $ hg -R test --config experimental.extra-filter-revs='not public()' debugupdatecache
  $ ls -1 test/.hg/cache/
  branch2-base%89c45d2fa07e
  branch2-immutable%89c45d2fa07e
  branch2-served
  branch2-served%89c45d2fa07e
  branch2-served.hidden%89c45d2fa07e
  branch2-visible%89c45d2fa07e
  branch2-visible-hidden%89c45d2fa07e
  hgtagsfnodes1
  rbc-names-v1
  rbc-revs-v1
  tags2
  tags2-served%89c45d2fa07e

cleanup

  $ cat errors.log
  $ killdaemons.py

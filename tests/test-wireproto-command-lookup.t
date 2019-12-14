  $ . $TESTDIR/wireprotohelpers.sh

  $ hg init server
  $ enablehttpv2 server
  $ cd server
  $ cat >> .hg/hgrc << EOF
  > [web]
  > push_ssl = false
  > allow-push = *
  > EOF
  $ hg debugdrawdag << EOF
  > C D
  > |/
  > B
  > |
  > A
  > EOF
  $ root_node=$(hg log -r A -T '{node}')

  $ hg serve -p $HGPORT -d --pid-file hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

lookup for known node works

  $ sendhttpv2peer << EOF
  > command lookup
  >     key $root_node
  > EOF
  creating http peer for wire protocol version 2
  sending lookup command
  response: b'Bk\xad\xa5\xc6u\x98\xcae\x03mW\xd9\xe4\xb6K\x0c\x1c\xe7\xa0'

  $ cat error.log

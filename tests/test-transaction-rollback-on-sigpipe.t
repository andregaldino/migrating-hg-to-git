Test that, when an hg push is interrupted and the remote side recieves SIGPIPE,
the remote hg is able to successfully roll back the transaction.

  $ hg init -q remote
  $ hg clone -e "\"$PYTHON\" \"$TESTDIR/dummyssh\"" -q ssh://user@dummy/`pwd`/remote local

  $ check_for_abandoned_transaction() {
  >     [ -f $TESTTMP/remote/.hg/store/journal ] && echo "Abandoned transaction!"
  > }

  $ pidfile=`pwd`/pidfile
  $ >$pidfile

  $ script() {
  >     cat >"$1"
  >     chmod +x "$1"
  > }

On the remote end, run hg, piping stdout and stderr through processes that we
know the PIDs of. We will later kill these to simulate an ssh client
disconnecting.

  $ killable_pipe=`pwd`/killable_pipe.sh
  $ script $killable_pipe <<EOF
  > #!/bin/bash
  > echo \$\$ >> $pidfile
  > exec cat
  > EOF

  $ remotecmd=`pwd`/remotecmd.sh
  $ script $remotecmd <<EOF
  > #!/bin/bash
  > hg "\$@" 1> >($killable_pipe) 2> >($killable_pipe >&2)
  > EOF

In the pretxnchangegroup hook, kill the PIDs recorded above to simulate ssh
disconnecting. Then exit nonzero, to force a transaction rollback.

  $ hook_script=`pwd`/pretxnchangegroup.sh
  $ script $hook_script <<EOF
  > #!/bin/bash
  > for pid in \$(cat $pidfile) ; do
  >   kill \$pid
  >   while kill -0 \$pid 2>/dev/null ; do
  >     sleep 0.1
  >   done
  > done
  > exit 1
  > EOF

  $ cat >remote/.hg/hgrc <<EOF
  > [hooks]
  > pretxnchangegroup.break-things=$hook_script
  > EOF

  $ cd local
  $ echo foo > foo ; hg commit -qAm "commit"
  $ hg push -q -e "\"$PYTHON\" \"$TESTDIR/dummyssh\"" --remotecmd $remotecmd 2>&1 | grep -v $killable_pipe
  abort: stream ended unexpectedly (got 0 bytes, expected 4)

  $ check_for_abandoned_transaction
  [1]

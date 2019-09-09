#require serve

  $ hg init test
  $ cd test

  $ cat > .hg/hgrc <<EOF
  > [extensions]
  > # this is only necessary to check that the mapping from
  > # interhg to websub works
  > interhg =
  > 
  > [websub]
  > issues = s|Issue(\d+)|<a href="http://bts.example.org/issue\1">Issue\1</a>|
  > tickets = s|ticket(\d+)|<a href="http://ticket.example.org/issue\1">Ticket\1</a>|i
  > 
  > [interhg]
  > # check that we maintain some interhg backwards compatibility...
  > # yes, 'x' is a weird delimiter...
  > markbugs = sxbugx<i class="\x">bug</i>x
  > problems = sxPROBLEMx<i class="\x">problem</i>xi
  > EOF

  $ touch foo
  $ hg add foo
  $ hg commit -d '1 0' -m 'Issue123: fixed the bug! Ticket456 and problem789 too'

  $ hg serve -n test -p $HGPORT -d --pid-file=hg.pid -A access.log -E errors.log
  $ cat hg.pid >> $DAEMON_PIDS

log

  $ get-with-headers.py localhost:$HGPORT "rev/tip" | grep bts
  <div class="description"><a href="http://bts.example.org/issue123">Issue123</a>: fixed the <i class="x">bug</i>! <a href="http://ticket.example.org/issue456">Ticket456</a> and <i class="x">problem</i>789 too</div>
errors

  $ cat errors.log

  $ cd ..

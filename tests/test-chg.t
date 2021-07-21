#require chg

  $ mkdir log
  $ cp $HGRCPATH $HGRCPATH.unconfigured
  $ cat <<'EOF' >> $HGRCPATH
  > [cmdserver]
  > log = $TESTTMP/log/server.log
  > max-log-files = 1
  > max-log-size = 10 kB
  > EOF
  $ cp $HGRCPATH $HGRCPATH.orig

  $ filterlog () {
  >   sed -e 's!^[0-9/]* [0-9:]* ([0-9]*)>!YYYY/MM/DD HH:MM:SS (PID)>!' \
  >       -e 's!\(setprocname\|received fds\|setenv\): .*!\1: ...!' \
  >       -e 's!\(confighash\|mtimehash\) = [0-9a-f]*!\1 = ...!g' \
  >       -e 's!\(in \)[0-9.]*s\b!\1 ...s!g' \
  >       -e 's!\(pid\)=[0-9]*!\1=...!g' \
  >       -e 's!\(/server-\)[0-9a-f]*!\1...!g'
  > }

init repo

  $ chg init foo
  $ cd foo

ill-formed config

  $ chg status
  $ echo '=brokenconfig' >> $HGRCPATH
  $ chg status
  config error at * =brokenconfig (glob)
  [30]

  $ cp $HGRCPATH.orig $HGRCPATH

long socket path

  $ sockpath=$TESTTMP/this/path/should/be/longer/than/one-hundred-and-seven/characters/where/107/is/the/typical/size/limit/of/unix-domain-socket
  $ mkdir -p $sockpath
  $ bakchgsockname=$CHGSOCKNAME
  $ CHGSOCKNAME=$sockpath/server
  $ export CHGSOCKNAME
  $ chg root
  $TESTTMP/foo
  $ rm -rf $sockpath
  $ CHGSOCKNAME=$bakchgsockname
  $ export CHGSOCKNAME

  $ cd ..

editor
------

  $ cat >> pushbuffer.py <<EOF
  > def reposetup(ui, repo):
  >     repo.ui.pushbuffer(subproc=True)
  > EOF

  $ chg init editor
  $ cd editor

by default, system() should be redirected to the client:

  $ touch foo
  $ CHGDEBUG= HGEDITOR=cat chg ci -Am channeled --edit 2>&1 \
  > | egrep "HG:|run 'cat"
  chg: debug: * run 'cat "*"' at '$TESTTMP/editor' (glob)
  HG: Enter commit message.  Lines beginning with 'HG:' are removed.
  HG: Leave message empty to abort commit.
  HG: --
  HG: user: test
  HG: branch 'default'
  HG: added foo

but no redirection should be made if output is captured:

  $ touch bar
  $ CHGDEBUG= HGEDITOR=cat chg ci -Am bufferred --edit \
  > --config extensions.pushbuffer="$TESTTMP/pushbuffer.py" 2>&1 \
  > | egrep "HG:|run 'cat"
  [1]

check that commit commands succeeded:

  $ hg log -T '{rev}:{desc}\n'
  1:bufferred
  0:channeled

  $ cd ..

pager
-----

  $ cat >> fakepager.py <<EOF
  > import sys
  > for line in sys.stdin:
  >     sys.stdout.write('paged! %r\n' % line)
  > EOF

enable pager extension globally, but spawns the master server with no tty:

  $ chg init pager
  $ cd pager
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > pager =
  > [pager]
  > pager = "$PYTHON" $TESTTMP/fakepager.py
  > EOF
  $ chg version > /dev/null
  $ touch foo
  $ chg ci -qAm foo

pager should be enabled if the attached client has a tty:

  $ chg log -l1 -q --config ui.formatted=True
  paged! '0:1f7b0de80e11\n'
  $ chg log -l1 -q --config ui.formatted=False
  0:1f7b0de80e11

chg waits for pager if runcommand raises

  $ cat > $TESTTMP/crash.py <<EOF
  > from mercurial import registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'crash')
  > def pagercrash(ui, repo, *pats, **opts):
  >     ui.write(b'going to crash\n')
  >     raise Exception('.')
  > EOF

  $ cat > $TESTTMP/fakepager.py <<EOF
  > from __future__ import absolute_import
  > import sys
  > import time
  > for line in iter(sys.stdin.readline, ''):
  >     if 'crash' in line: # only interested in lines containing 'crash'
  >         # if chg exits when pager is sleeping (incorrectly), the output
  >         # will be captured by the next test case
  >         time.sleep(1)
  >         sys.stdout.write('crash-pager: %s' % line)
  > EOF

  $ cat >> .hg/hgrc <<EOF
  > [extensions]
  > crash = $TESTTMP/crash.py
  > EOF

  $ chg crash --pager=on --config ui.formatted=True 2>/dev/null
  crash-pager: going to crash
  [255]

no stdout data should be printed after pager quits, and the buffered data
should never persist (issue6207)

"killed!" may be printed if terminated by SIGPIPE, which isn't important
in this test.

  $ cat > $TESTTMP/bulkwrite.py <<'EOF'
  > import time
  > from mercurial import error, registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'bulkwrite')
  > def bulkwrite(ui, repo, *pats, **opts):
  >     ui.write(b'going to write massive data\n')
  >     ui.flush()
  >     t = time.time()
  >     while time.time() - t < 2:
  >         ui.write(b'x' * 1023 + b'\n')  # will be interrupted by SIGPIPE
  >     raise error.Abort(b"write() doesn't block")
  > EOF

  $ cat > $TESTTMP/fakepager.py <<'EOF'
  > import sys
  > import time
  > sys.stdout.write('paged! %r\n' % sys.stdin.readline())
  > time.sleep(1)  # new data will be written
  > EOF

  $ cat >> .hg/hgrc <<EOF
  > [extensions]
  > bulkwrite = $TESTTMP/bulkwrite.py
  > EOF

  $ chg bulkwrite --pager=on --color no --config ui.formatted=True
  paged! 'going to write massive data\n'
  killed! (?)
  [255]

  $ chg bulkwrite --pager=on --color no --config ui.formatted=True
  paged! 'going to write massive data\n'
  killed! (?)
  [255]

  $ cd ..

missing stdio
-------------

  $ CHGDEBUG=1 chg version -q 0<&-
  chg: debug: * stdio fds are missing (glob)
  chg: debug: * execute original hg (glob)
  Mercurial Distributed SCM * (glob)

server lifecycle
----------------

chg server should be restarted on code change, and old server will shut down
automatically. In this test, we use the following time parameters:

 - "sleep 1" to make mtime different
 - "sleep 2" to notice mtime change (polling interval is 1 sec)

set up repository with an extension:

  $ chg init extreload
  $ cd extreload
  $ touch dummyext.py
  $ cat <<EOF >> .hg/hgrc
  > [extensions]
  > dummyext = dummyext.py
  > EOF

isolate socket directory for stable result:

  $ OLDCHGSOCKNAME=$CHGSOCKNAME
  $ mkdir chgsock
  $ CHGSOCKNAME=`pwd`/chgsock/server

warm up server:

  $ CHGDEBUG= chg log 2>&1 | egrep 'instruction|start'
  chg: debug: * start cmdserver at $TESTTMP/extreload/chgsock/server.* (glob)

new server should be started if extension modified:

  $ sleep 1
  $ touch dummyext.py
  $ CHGDEBUG= chg log 2>&1 | egrep 'instruction|start'
  chg: debug: * instruction: unlink $TESTTMP/extreload/chgsock/server-* (glob)
  chg: debug: * instruction: reconnect (glob)
  chg: debug: * start cmdserver at $TESTTMP/extreload/chgsock/server.* (glob)

old server will shut down, while new server should still be reachable:

  $ sleep 2
  $ CHGDEBUG= chg log 2>&1 | (egrep 'instruction|start' || true)

socket file should never be unlinked by old server:
(simulates unowned socket by updating mtime, which makes sure server exits
at polling cycle)

  $ ls chgsock/server-*
  chgsock/server-* (glob)
  $ touch chgsock/server-*
  $ sleep 2
  $ ls chgsock/server-*
  chgsock/server-* (glob)

since no server is reachable from socket file, new server should be started:
(this test makes sure that old server shut down automatically)

  $ CHGDEBUG= chg log 2>&1 | egrep 'instruction|start'
  chg: debug: * start cmdserver at $TESTTMP/extreload/chgsock/server.* (glob)

shut down servers and restore environment:

  $ rm -R chgsock
  $ sleep 2
  $ CHGSOCKNAME=$OLDCHGSOCKNAME
  $ cd ..

check that server events are recorded:

  $ ls log
  server.log
  server.log.1

print only the last 10 lines, since we aren't sure how many records are
preserved (since setprocname isn't available on py3 and pure version,
the 10th-most-recent line is different when using py3):

  $ cat log/server.log.1 log/server.log | tail -10 | filterlog
  YYYY/MM/DD HH:MM:SS (PID)> confighash = ... mtimehash = ... (no-setprocname !)
  YYYY/MM/DD HH:MM:SS (PID)> forked worker process (pid=...)
  YYYY/MM/DD HH:MM:SS (PID)> setprocname: ... (setprocname !)
  YYYY/MM/DD HH:MM:SS (PID)> received fds: ...
  YYYY/MM/DD HH:MM:SS (PID)> chdir to '$TESTTMP/extreload'
  YYYY/MM/DD HH:MM:SS (PID)> setumask 18
  YYYY/MM/DD HH:MM:SS (PID)> setenv: ...
  YYYY/MM/DD HH:MM:SS (PID)> confighash = ... mtimehash = ...
  YYYY/MM/DD HH:MM:SS (PID)> validate: []
  YYYY/MM/DD HH:MM:SS (PID)> worker process exited (pid=...)
  YYYY/MM/DD HH:MM:SS (PID)> $TESTTMP/extreload/chgsock/server-... is not owned, exiting.

global data mutated by schems
-----------------------------

  $ hg init schemes
  $ cd schemes

initial state

  $ cat > .hg/hgrc <<'EOF'
  > [extensions]
  > schemes =
  > [schemes]
  > foo = https://foo.example.org/
  > EOF
  $ hg debugexpandscheme foo://expanded
  https://foo.example.org/expanded
  $ hg debugexpandscheme bar://unexpanded
  bar://unexpanded

add bar

  $ cat > .hg/hgrc <<'EOF'
  > [extensions]
  > schemes =
  > [schemes]
  > foo = https://foo.example.org/
  > bar = https://bar.example.org/
  > EOF
  $ hg debugexpandscheme foo://expanded
  https://foo.example.org/expanded
  $ hg debugexpandscheme bar://expanded
  https://bar.example.org/expanded

remove foo

  $ cat > .hg/hgrc <<'EOF'
  > [extensions]
  > schemes =
  > [schemes]
  > bar = https://bar.example.org/
  > EOF
  $ hg debugexpandscheme foo://unexpanded
  foo://unexpanded
  $ hg debugexpandscheme bar://expanded
  https://bar.example.org/expanded

  $ cd ..

repository cache
----------------

  $ rm log/server.log*
  $ cp $HGRCPATH.unconfigured $HGRCPATH
  $ cat <<'EOF' >> $HGRCPATH
  > [cmdserver]
  > log = $TESTTMP/log/server.log
  > max-repo-cache = 1
  > track-log = command, repocache
  > EOF

isolate socket directory for stable result:

  $ OLDCHGSOCKNAME=$CHGSOCKNAME
  $ mkdir chgsock
  $ CHGSOCKNAME=`pwd`/chgsock/server

create empty repo and cache it:

  $ hg init cached
  $ hg id -R cached
  000000000000 tip
  $ sleep 1

modify repo (and cache will be invalidated):

  $ touch cached/a
  $ hg ci -R cached -Am 'add a'
  adding a
  $ sleep 1

read cached repo:

  $ hg log -R cached
  changeset:   0:ac82d8b1f7c4
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     add a
  
  $ sleep 1

discard cached from LRU cache:

  $ hg clone cached cached2
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg id -R cached2
  ac82d8b1f7c4 tip
  $ sleep 1

read uncached repo:

  $ hg log -R cached
  changeset:   0:ac82d8b1f7c4
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     add a
  
  $ sleep 1

shut down servers and restore environment:

  $ rm -R chgsock
  $ sleep 2
  $ CHGSOCKNAME=$OLDCHGSOCKNAME

check server log:

  $ cat log/server.log | filterlog
  YYYY/MM/DD HH:MM:SS (PID)> worker process exited (pid=...)
  YYYY/MM/DD HH:MM:SS (PID)> worker process exited (pid=...) (?)
  YYYY/MM/DD HH:MM:SS (PID)> init cached
  YYYY/MM/DD HH:MM:SS (PID)> id -R cached
  YYYY/MM/DD HH:MM:SS (PID)> loaded repo into cache: $TESTTMP/cached (in  ...s)
  YYYY/MM/DD HH:MM:SS (PID)> repo from cache: $TESTTMP/cached
  YYYY/MM/DD HH:MM:SS (PID)> ci -R cached -Am 'add a'
  YYYY/MM/DD HH:MM:SS (PID)> loaded repo into cache: $TESTTMP/cached (in  ...s)
  YYYY/MM/DD HH:MM:SS (PID)> repo from cache: $TESTTMP/cached
  YYYY/MM/DD HH:MM:SS (PID)> log -R cached
  YYYY/MM/DD HH:MM:SS (PID)> loaded repo into cache: $TESTTMP/cached (in  ...s)
  YYYY/MM/DD HH:MM:SS (PID)> clone cached cached2
  YYYY/MM/DD HH:MM:SS (PID)> id -R cached2
  YYYY/MM/DD HH:MM:SS (PID)> loaded repo into cache: $TESTTMP/cached2 (in  ...s)
  YYYY/MM/DD HH:MM:SS (PID)> log -R cached
  YYYY/MM/DD HH:MM:SS (PID)> loaded repo into cache: $TESTTMP/cached (in  ...s)

Test that chg works (sets to the user's actual LC_CTYPE) even when python
"coerces" the locale (py3.7+)

  $ cat > $TESTTMP/debugenv.py <<EOF
  > from mercurial import encoding
  > from mercurial import registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'debugenv', [], b'', norepo=True)
  > def debugenv(ui):
  >     for k in [b'LC_ALL', b'LC_CTYPE', b'LANG']:
  >         v = encoding.environ.get(k)
  >         if v is not None:
  >             ui.write(b'%s=%s\n' % (k, encoding.environ[k]))
  > EOF
(hg keeps python's modified LC_CTYPE, chg doesn't)
  $ (unset LC_ALL; unset LANG; LC_CTYPE= "$CHGHG" \
  >    --config extensions.debugenv=$TESTTMP/debugenv.py debugenv)
  LC_CTYPE=C.UTF-8 (py37 !)
  LC_CTYPE= (no-py37 !)
  $ (unset LC_ALL; unset LANG; LC_CTYPE= chg \
  >    --config extensions.debugenv=$TESTTMP/debugenv.py debugenv)
  LC_CTYPE=
  $ (unset LC_ALL; unset LANG; LC_CTYPE=unsupported_value chg \
  >    --config extensions.debugenv=$TESTTMP/debugenv.py debugenv)
  *cannot change locale* (glob) (?)
  LC_CTYPE=unsupported_value
  $ (unset LC_ALL; unset LANG; LC_CTYPE= chg \
  >    --config extensions.debugenv=$TESTTMP/debugenv.py debugenv)
  LC_CTYPE=
  $ LANG= LC_ALL= LC_CTYPE= chg \
  >    --config extensions.debugenv=$TESTTMP/debugenv.py debugenv
  LC_ALL=
  LC_CTYPE=
  LANG=

Profiling isn't permanently enabled or carried over between chg invocations that
share the same server
  $ cp $HGRCPATH.orig $HGRCPATH
  $ hg init $TESTTMP/profiling
  $ cd $TESTTMP/profiling
  $ filteredchg() {
  >   CHGDEBUG=1 chg "$@" 2>&1 | egrep 'Sample count|start cmdserver' || true
  > }
  $ newchg() {
  >   chg --kill-chg-daemon
  >   filteredchg "$@" | egrep -v 'start cmdserver' || true
  > }
(--profile isn't permanently on just because it was specified when chg was
started)
  $ newchg log -r . --profile
  Sample count: * (glob)
  $ filteredchg log -r .
(enabling profiling via config works, even on the first chg command that starts
a cmdserver)
  $ cat >> $HGRCPATH <<EOF
  > [profiling]
  > type=stat
  > enabled=1
  > EOF
  $ newchg log -r .
  Sample count: * (glob)
  $ filteredchg log -r .
  Sample count: * (glob)
(test that we aren't accumulating more and more samples each run)
  $ cat > $TESTTMP/debugsleep.py <<EOF
  > import time
  > from mercurial import registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'debugsleep', [], b'', norepo=True)
  > def debugsleep(ui):
  >   start = time.time()
  >   x = 0
  >   while time.time() < start + 0.5:
  >     time.sleep(.1)
  >     x += 1
  >   ui.status(b'%d debugsleep iterations in %.03fs\n' % (x, time.time() - start))
  > EOF
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > debugsleep = $TESTTMP/debugsleep.py
  > EOF
  $ newchg debugsleep > run_1
  $ filteredchg debugsleep > run_2
  $ filteredchg debugsleep > run_3
  $ filteredchg debugsleep > run_4
FIXME: Run 4 should not be >3x Run 1's number of samples.
  $ "$PYTHON" <<EOF
  > r1 = int(open("run_1", "r").read().split()[-1])
  > r4 = int(open("run_4", "r").read().split()[-1])
  > print("Run 1: %d samples\nRun 4: %d samples\nRun 4 > 3 * Run 1: %s" %
  >       (r1, r4, r4 > (r1 * 3)))
  > EOF
  Run 1: * samples (glob)
  Run 4: * samples (glob)
  Run 4 > 3 * Run 1: False
(Disabling with --no-profile on the commandline still works, but isn't permanent)
  $ newchg log -r . --no-profile
  $ filteredchg log -r .
  Sample count: * (glob)
  $ filteredchg log -r . --no-profile
  $ filteredchg log -r .
  Sample count: * (glob)

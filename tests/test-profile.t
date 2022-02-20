test --time

  $ hg --time help -q help 2>&1 | grep time > /dev/null
  $ hg init a
  $ cd a

Function to check that statprof ran
  $ statprofran () {
  >   egrep 'Sample count:|No samples recorded' > /dev/null
  > }

test --profile

  $ hg st --profile 2>&1 | statprofran

Abreviated version

  $ hg st --prof 2>&1 | statprofran

In alias

  $ hg --config "alias.profst=status --profile" profst 2>&1 | statprofran

#if lsprof

  $ prof () {
  >   hg --config profiling.type=ls --profile $@
  > }

  $ prof st 2>../out
  $ grep CallCount ../out > /dev/null || cat ../out

  $ prof --config profiling.output=../out st
  $ grep CallCount ../out > /dev/null || cat ../out

  $ prof --config profiling.output=blackbox --config extensions.blackbox= st
  $ grep CallCount .hg/blackbox.log > /dev/null || cat .hg/blackbox.log

  $ prof --config profiling.format=text st 2>../out
  $ grep CallCount ../out > /dev/null || cat ../out

  $ echo "[profiling]" >> $HGRCPATH
  $ echo "format=kcachegrind" >> $HGRCPATH

  $ prof st 2>../out
  $ grep 'events: Ticks' ../out > /dev/null || cat ../out

  $ prof --config profiling.output=../out st
  $ grep 'events: Ticks' ../out > /dev/null || cat ../out

#endif

#if lsprof serve

Profiling of HTTP requests works

  $ prof --config profiling.format=text --config profiling.output=../profile.log serve -d -p $HGPORT --pid-file ../hg.pid -A ../access.log
  $ cat ../hg.pid >> $DAEMON_PIDS
  $ hg -q clone -U http://localhost:$HGPORT ../clone

A single profile is logged because file logging doesn't append
  $ grep CallCount ../profile.log | wc -l
  \s*1 (re)

#endif

Install an extension that can sleep and guarantee a profiler has time to run

  $ cat >> sleepext_with_a_long_filename.py << EOF
  > import time
  > from mercurial import registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'sleep', [], b'hg sleep')
  > def sleep_for_at_least_one_stat_cycle(ui, *args, **kwargs):
  >     t = time.time()  # don't use time.sleep because we need CPU time
  >     while time.time() - t < 0.5:
  >         pass
  > EOF

  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > sleep = `pwd`/sleepext_with_a_long_filename.py
  > EOF

statistical profiler works

  $ hg --profile sleep 2>../out
  $ cat ../out | statprofran

Various statprof formatters work

  $ hg --profile --config profiling.statformat=byline sleep 2>../out || cat ../out
  $ grep -v _path_stat ../out | head -n 3
    %   cumulative      self          
   time    seconds   seconds  name    
  * sleepext_with_a_long_filename.py:*:sleep_for_at_least_one_stat_cycle (glob)
  $ cat ../out | statprofran

  $ hg --profile --config profiling.statformat=bymethod sleep 2>../out || cat ../out
  $ head -n 1 ../out
    %   cumulative      self          
  $ cat ../out | statprofran

Windows real time tracking is broken, only use CPU

#if no-windows
  $ hg --profile --config profiling.time-track=real --config profiling.statformat=hotpath sleep 2>../out || cat ../out
  $ cat ../out | statprofran
  $ grep sleepext_with_a_long_filename.py ../out | head -n 1
  .* [0-9.]+%  [0-9.]+s  sleepext_with_a_long_filename.py:\s*sleep_for_at_least_one_stat_cycle, line \d+:\s+(while|pass).* (re)
#endif

  $ hg --profile --config profiling.time-track=cpu --config profiling.statformat=hotpath sleep 2>../out || cat ../out
  $ cat ../out | statprofran
  $ grep sleepext_with_a_long_filename.py ../out | head -n 1
  .* [0-9.]+%  [0-9.]+s  sleepext_with_a_long_filename.py:\s*sleep_for_at_least_one_stat_cycle, line \d+:\s+(while|pass).* (re)

  $ hg --profile --config profiling.statformat=json sleep 2>../out || cat ../out
  $ cat ../out
  \[\[-?\d+.* (re)

statprof can be used as a standalone module

  $ "$PYTHON" -m mercurial.statprof hotpath
  must specify --file to load
  [1]

  $ cd ..

#if no-chg
profiler extension could be loaded before other extensions

  $ cat > fooprof.py <<EOF
  > import contextlib
  > import sys
  > @contextlib.contextmanager
  > def profile(ui, fp):
  >     print('fooprof: start profile')
  >     sys.stdout.flush()
  >     yield
  >     print('fooprof: end profile')
  >     sys.stdout.flush()
  > def extsetup(ui):
  >     ui.write(b'fooprof: loaded\n')
  > EOF

  $ cat > otherextension.py <<EOF
  > def extsetup(ui):
  >     ui.write(b'otherextension: loaded\n')
  > EOF

  $ hg init b
  $ cd b
  $ cat >> .hg/hgrc <<EOF
  > [extensions]
  > other = $TESTTMP/otherextension.py
  > fooprof = $TESTTMP/fooprof.py
  > EOF

  $ hg root
  otherextension: loaded
  fooprof: loaded
  $TESTTMP/b
  $ HGPROF=fooprof hg root --profile
  fooprof: loaded
  fooprof: start profile
  otherextension: loaded
  $TESTTMP/b
  fooprof: end profile

  $ HGPROF=other hg root --profile 2>&1 | head -n 2
  otherextension: loaded
  unrecognized profiler 'other' - ignored

  $ HGPROF=unknown hg root --profile 2>&1 | head -n 1
  unrecognized profiler 'unknown' - ignored

  $ cd ..
#endif

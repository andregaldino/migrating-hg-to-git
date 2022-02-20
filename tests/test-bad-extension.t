#require no-chg
  $ filterlog () {
  >   sed -e 's!^[0-9/]* [0-9:]* ([0-9]*)>!YYYY/MM/DD HH:MM:SS (PID)>!'
  > }

ensure that failing ui.atexit handlers report sensibly

  $ cat > $TESTTMP/bailatexit.py <<EOF
  > from mercurial import util
  > def bail():
  >     raise RuntimeError('ui.atexit handler exception')
  > 
  > def extsetup(ui):
  >     ui.atexit(bail)
  > EOF
  $ hg -q --config extensions.bailatexit=$TESTTMP/bailatexit.py \
  >  help help
  hg help [-eck] [-s PLATFORM] [TOPIC]
  
  show help for a given topic or a help overview
  error in exit handlers:
  Traceback (most recent call last):
    File "*/mercurial/dispatch.py", line *, in _runexithandlers (glob) (no-pyoxidizer !)
    File "mercurial.dispatch", line *, in _runexithandlers (glob) (pyoxidizer !)
      func(*args, **kwargs)
    File "$TESTTMP/bailatexit.py", line *, in bail (glob)
      raise RuntimeError('ui.atexit handler exception')
  RuntimeError: ui.atexit handler exception
  [255]

  $ rm $TESTTMP/bailatexit.py

another bad extension

  $ echo 'raise Exception("bit bucket overflow")' > badext.py
  $ abspathexc=`pwd`/badext.py

  $ cat >baddocext.py <<EOF
  > """
  > baddocext is bad
  > """
  > EOF
  $ abspathdoc=`pwd`/baddocext.py

  $ cat <<EOF >> $HGRCPATH
  > [extensions]
  > gpg =
  > hgext.gpg =
  > badext = $abspathexc
  > baddocext = $abspathdoc
  > badext2 =
  > EOF

  $ hg -q help help 2>&1 |grep extension
  *** failed to import extension "badext" from $TESTTMP/badext.py: bit bucket overflow
  *** failed to import extension "badext2": No module named 'badext2' (py3 !)

show traceback

  $ hg -q help help --traceback 2>&1 | egrep ' extension|^Exception|Traceback|ImportError|ModuleNotFound'
  *** failed to import extension "badext" from $TESTTMP/badext.py: bit bucket overflow
  Traceback (most recent call last):
  Exception: bit bucket overflow
  *** failed to import extension "badext2": No module named 'badext2' (py3 !)
  Traceback (most recent call last):
  ImportError: No module named 'hgext.badext2' (py3 no-py36 !)
  ModuleNotFoundError: No module named 'hgext.badext2' (py36 !)
  Traceback (most recent call last): (py3 !)
  ImportError: No module named 'hgext3rd.badext2' (py3 no-py36 !)
  ModuleNotFoundError: No module named 'hgext3rd.badext2' (py36 !)
  Traceback (most recent call last): (py3 !)
  ImportError: No module named 'badext2' (py3 no-py36 !)
  ModuleNotFoundError: No module named 'badext2' (py36 !)

names of extensions failed to load can be accessed via extensions.notloaded()

  $ cat <<EOF > showbadexts.py
  > from mercurial import commands, extensions, registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'showbadexts', norepo=True)
  > def showbadexts(ui, *pats, **opts):
  >     ui.write(b'BADEXTS: %s\n' % b' '.join(sorted(extensions.notloaded())))
  > EOF
  $ hg --config extensions.badexts=showbadexts.py showbadexts 2>&1 | grep '^BADEXTS'
  BADEXTS: badext badext2

#if no-extraextensions
show traceback for ImportError of hgext.name if devel.debug.extensions is set

  $ (hg help help --traceback --debug --config devel.debug.extensions=yes 2>&1) \
  > | grep -v '^ ' \
  > | filterlog \
  > | egrep 'extension..[^p]|^Exception|Traceback|ImportError|^YYYY|not import|ModuleNotFound'
  YYYY/MM/DD HH:MM:SS (PID)> loading extensions
  YYYY/MM/DD HH:MM:SS (PID)> - processing 5 entries
  YYYY/MM/DD HH:MM:SS (PID)>   - loading extension: gpg
  YYYY/MM/DD HH:MM:SS (PID)>   > gpg extension loaded in * (glob)
  YYYY/MM/DD HH:MM:SS (PID)>     - validating extension tables: gpg
  YYYY/MM/DD HH:MM:SS (PID)>     - invoking registered callbacks: gpg
  YYYY/MM/DD HH:MM:SS (PID)>     > callbacks completed in * (glob)
  YYYY/MM/DD HH:MM:SS (PID)>   - loading extension: badext
  *** failed to import extension "badext" from $TESTTMP/badext.py: bit bucket overflow
  Traceback (most recent call last):
  Exception: bit bucket overflow
  YYYY/MM/DD HH:MM:SS (PID)>   - loading extension: baddocext
  YYYY/MM/DD HH:MM:SS (PID)>   > baddocext extension loaded in * (glob)
  YYYY/MM/DD HH:MM:SS (PID)>     - validating extension tables: baddocext
  YYYY/MM/DD HH:MM:SS (PID)>     - invoking registered callbacks: baddocext
  YYYY/MM/DD HH:MM:SS (PID)>     > callbacks completed in * (glob)
  YYYY/MM/DD HH:MM:SS (PID)>   - loading extension: badext2
  YYYY/MM/DD HH:MM:SS (PID)>     - could not import hgext.badext2 (No module named *badext2*): trying hgext3rd.badext2 (glob)
  Traceback (most recent call last):
  ImportError: No module named 'hgext.badext2' (py3 no-py36 !)
  ModuleNotFoundError: No module named 'hgext.badext2' (py36 !)
  YYYY/MM/DD HH:MM:SS (PID)>     - could not import hgext3rd.badext2 (No module named *badext2*): trying badext2 (glob)
  Traceback (most recent call last):
  ImportError: No module named 'hgext.badext2' (py3 no-py36 !)
  ModuleNotFoundError: No module named 'hgext.badext2' (py36 !)
  Traceback (most recent call last): (py3 !)
  ImportError: No module named 'hgext3rd.badext2' (py3 no-py36 !)
  ModuleNotFoundError: No module named 'hgext3rd.badext2' (py36 !)
  *** failed to import extension "badext2": No module named 'badext2' (py3 !)
  Traceback (most recent call last):
  ImportError: No module named 'hgext.badext2' (py3 no-py36 !)
  ModuleNotFoundError: No module named 'hgext.badext2' (py36 !)
  Traceback (most recent call last): (py3 !)
  ImportError: No module named 'hgext3rd.badext2' (py3 no-py36 !)
  ModuleNotFoundError: No module named 'hgext3rd.badext2' (py36 !)
  Traceback (most recent call last): (py3 !)
  ModuleNotFoundError: No module named 'badext2' (py36 !)
  ImportError: No module named 'badext2' (py3 no-py36 !)
  YYYY/MM/DD HH:MM:SS (PID)> > loaded 2 extensions, total time * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - loading configtable attributes
  YYYY/MM/DD HH:MM:SS (PID)> - executing uisetup hooks
  YYYY/MM/DD HH:MM:SS (PID)>   - running uisetup for gpg
  YYYY/MM/DD HH:MM:SS (PID)>   > uisetup for gpg took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)>   - running uisetup for baddocext
  YYYY/MM/DD HH:MM:SS (PID)>   > uisetup for baddocext took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> > all uisetup took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - executing extsetup hooks
  YYYY/MM/DD HH:MM:SS (PID)>   - running extsetup for gpg
  YYYY/MM/DD HH:MM:SS (PID)>   > extsetup for gpg took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)>   - running extsetup for baddocext
  YYYY/MM/DD HH:MM:SS (PID)>   > extsetup for baddocext took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> > all extsetup took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - executing remaining aftercallbacks
  YYYY/MM/DD HH:MM:SS (PID)> > remaining aftercallbacks completed in * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - loading extension registration objects
  YYYY/MM/DD HH:MM:SS (PID)> > extension registration object loading took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> > extension baddocext take a total of * to load (glob)
  YYYY/MM/DD HH:MM:SS (PID)> > extension gpg take a total of * to load (glob)
  YYYY/MM/DD HH:MM:SS (PID)> extension loading complete
#endif

confirm that there's no crash when an extension's documentation is bad

  $ hg help --keyword baddocext
  *** failed to import extension "badext" from $TESTTMP/badext.py: bit bucket overflow
  *** failed to import extension "badext2": No module named 'badext2' (py3 !)
  Topics:
  
   extensions Using Additional Features

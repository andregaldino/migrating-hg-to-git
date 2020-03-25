#require no-chg

Test basic extension support

  $ cat > foobar.py <<EOF
  > import os
  > from mercurial import commands, registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > configtable = {}
  > configitem = registrar.configitem(configtable)
  > configitem(b'tests', b'foo', default=b"Foo")
  > def uisetup(ui):
  >     ui.debug(b"uisetup called [debug]\\n")
  >     ui.write(b"uisetup called\\n")
  >     ui.status(b"uisetup called [status]\\n")
  >     ui.flush()
  > def reposetup(ui, repo):
  >     ui.write(b"reposetup called for %s\\n" % os.path.basename(repo.root))
  >     ui.write(b"ui %s= repo.ui\\n" % (ui == repo.ui and b"=" or b"!"))
  >     ui.flush()
  > @command(b'foo', [], b'hg foo')
  > def foo(ui, *args, **kwargs):
  >     foo = ui.config(b'tests', b'foo')
  >     ui.write(foo)
  >     ui.write(b"\\n")
  > @command(b'bar', [], b'hg bar', norepo=True)
  > def bar(ui, *args, **kwargs):
  >     ui.write(b"Bar\\n")
  > EOF
  $ abspath=`pwd`/foobar.py

  $ mkdir barfoo
  $ cp foobar.py barfoo/__init__.py
  $ barfoopath=`pwd`/barfoo

  $ hg init a
  $ cd a
  $ echo foo > file
  $ hg add file
  $ hg commit -m 'add file'

  $ echo '[extensions]' >> $HGRCPATH
  $ echo "foobar = $abspath" >> $HGRCPATH

  $ filterlog () {
  >   sed -e 's!^[0-9/]* [0-9:]* ([0-9]*)>!YYYY/MM/DD HH:MM:SS (PID)>!'
  > }

Test extension setup timings

  $ hg foo --traceback --config devel.debug.extensions=yes --debug 2>&1 | filterlog
  YYYY/MM/DD HH:MM:SS (PID)> loading extensions
  YYYY/MM/DD HH:MM:SS (PID)> - processing 1 entries
  YYYY/MM/DD HH:MM:SS (PID)>   - loading extension: foobar
  YYYY/MM/DD HH:MM:SS (PID)>   > foobar extension loaded in * (glob)
  YYYY/MM/DD HH:MM:SS (PID)>     - validating extension tables: foobar
  YYYY/MM/DD HH:MM:SS (PID)>     - invoking registered callbacks: foobar
  YYYY/MM/DD HH:MM:SS (PID)>     > callbacks completed in * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> > loaded 1 extensions, total time * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - loading configtable attributes
  YYYY/MM/DD HH:MM:SS (PID)> - executing uisetup hooks
  YYYY/MM/DD HH:MM:SS (PID)>   - running uisetup for foobar
  uisetup called [debug]
  uisetup called
  uisetup called [status]
  YYYY/MM/DD HH:MM:SS (PID)>   > uisetup for foobar took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> > all uisetup took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - executing extsetup hooks
  YYYY/MM/DD HH:MM:SS (PID)>   - running extsetup for foobar
  YYYY/MM/DD HH:MM:SS (PID)>   > extsetup for foobar took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> > all extsetup took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - executing remaining aftercallbacks
  YYYY/MM/DD HH:MM:SS (PID)> > remaining aftercallbacks completed in * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - loading extension registration objects
  YYYY/MM/DD HH:MM:SS (PID)> > extension registration object loading took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> > extension foobar take a total of * to load (glob)
  YYYY/MM/DD HH:MM:SS (PID)> extension loading complete
  YYYY/MM/DD HH:MM:SS (PID)> loading additional extensions
  YYYY/MM/DD HH:MM:SS (PID)> - processing 1 entries
  YYYY/MM/DD HH:MM:SS (PID)> > loaded 0 extensions, total time * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - loading configtable attributes
  YYYY/MM/DD HH:MM:SS (PID)> - executing uisetup hooks
  YYYY/MM/DD HH:MM:SS (PID)> > all uisetup took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - executing extsetup hooks
  YYYY/MM/DD HH:MM:SS (PID)> > all extsetup took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - executing remaining aftercallbacks
  YYYY/MM/DD HH:MM:SS (PID)> > remaining aftercallbacks completed in * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> - loading extension registration objects
  YYYY/MM/DD HH:MM:SS (PID)> > extension registration object loading took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> extension loading complete
  YYYY/MM/DD HH:MM:SS (PID)> - executing reposetup hooks
  YYYY/MM/DD HH:MM:SS (PID)>   - running reposetup for foobar
  reposetup called for a
  ui == repo.ui
  YYYY/MM/DD HH:MM:SS (PID)>   > reposetup for foobar took * (glob)
  YYYY/MM/DD HH:MM:SS (PID)> > all reposetup took * (glob)
  Foo

  $ cd ..

  $ echo 'foobar = !' >> $HGRCPATH

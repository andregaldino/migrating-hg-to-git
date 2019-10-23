#require test-repo slow debhelper debdeps

  $ . "$TESTDIR/helpers-testrepo.sh"
  $ testrepohgenv

Ensure debuild doesn't run the testsuite, as that could get silly.
  $ DEB_BUILD_OPTIONS=nocheck
  $ export DEB_BUILD_OPTIONS
  $ OUTPUTDIR=`pwd`
  $ export OUTPUTDIR

  $ cd "$TESTDIR"/..
  $ make deb > $OUTPUTDIR/build.log 2>&1
  $ cd $OUTPUTDIR
  $ ls *.deb | grep -v 'dbg'
  mercurial_*.deb (glob)
should have .so and .py
  $ dpkg --contents mercurial_*.deb | egrep '(localrepo|parsers)'
  * ./usr/lib/python3/dist-packages/mercurial/cext/parsers*.so (glob)
  * ./usr/lib/python3/dist-packages/mercurial/localrepo.py (glob)
  * ./usr/lib/python3/dist-packages/mercurial/pure/parsers.py (glob)
should have zsh completions
  $ dpkg --contents mercurial_*.deb | egrep 'zsh.*[^/]$'
  * ./usr/share/zsh/vendor-completions/_hg (glob)
should have chg
  $ dpkg --contents mercurial_*.deb | egrep 'chg$'
  * ./usr/bin/chg (glob)
chg should come with a man page
  $ dpkg --contents mercurial_*.deb | egrep 'man.*chg'
  * ./usr/share/man/man1/chg.1.gz (glob)

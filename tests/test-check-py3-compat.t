#require test-repo pure

  $ . "$TESTDIR/helpers-testrepo.sh"
  $ cd "$TESTDIR"/..

  $ testrepohg files 'set:(**.py) - grep(pygments)' \
  > -X hgext/fsmonitor/pywatchman \
  > -X mercurial/cffi \
  > -X mercurial/thirdparty \
  > | sed 's|\\|/|g' | xargs "$PYTHON" contrib/check-py3-compat.py \
  > | sed 's/[0-9][0-9]*)$/*)/'
  hgext/convert/transport.py: error importing: <*Error> No module named 'svn.client' (error at transport.py:*) (glob) (?)
  hgext/infinitepush/sqlindexapi.py: error importing: <*Error> No module named 'mysql' (error at sqlindexapi.py:*) (glob) (?)
  mercurial/scmwindows.py: error importing: <ValueError> _type_ 'v' not supported (error at win32.py:*) (no-windows !)
  mercurial/win32.py: error importing: <ValueError> _type_ 'v' not supported (error at win32.py:*) (no-windows !)
  mercurial/windows.py: error importing: <*Error> No module named 'msvcrt' (error at windows.py:*) (glob) (no-windows !)
  mercurial/posix.py: error importing: <*Error> No module named 'fcntl' (error at posix.py:*) (glob) (windows !)
  mercurial/scmposix.py: error importing: <*Error> No module named 'fcntl' (error at scmposix.py:*) (glob) (windows !)

#if pygments
  $ testrepohg files 'set:(**.py) and grep(pygments)' | sed 's|\\|/|g' \
  > | xargs "$PYTHON" contrib/check-py3-compat.py \
  > | sed 's/[0-9][0-9]*)$/*)/'
#endif

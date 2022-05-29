#require test-repo pyflakes hg10

  $ . "$TESTDIR/helpers-testrepo.sh"

run pyflakes on all tracked files ending in .py or without a file ending
(skipping binary file random-seed)

  $ cat > test.py <<EOF
  > print(undefinedname)
  > EOF
  $ "$PYTHON" -m pyflakes test.py 2>/dev/null | "$TESTDIR/filterpyflakes.py"
  test.py:1:* undefined name 'undefinedname' (glob)
  
  $ cd "`dirname "$TESTDIR"`"

  $ testrepohg locate 'set:**.py or grep("^#!.*python")' \
  > -X hgext/fsmonitor/pywatchman \
  > -X contrib/python-zstandard \
  > -X mercurial/thirdparty \
  > 2>/dev/null \
  > | xargs "$PYTHON" -m pyflakes 2>/dev/null | "$TESTDIR/filterpyflakes.py"
  contrib/perf.py:*:* undefined name 'xrange' (glob) (?)
  mercurial/pycompat.py:*:* 'codecs' imported but unused (glob)
  mercurial/pycompat.py:*:* 'concurrent.futures' imported but unused (glob)
  mercurial/pycompat.py:*:* 'http.client as httplib' imported but unused (glob)
  mercurial/pycompat.py:*:* 'http.cookiejar as cookielib' imported but unused (glob)
  mercurial/pycompat.py:*:* 'io' imported but unused (glob)
  mercurial/pycompat.py:*:* 'queue' imported but unused (glob)
  mercurial/pycompat.py:*:* 'socketserver' imported but unused (glob)
  mercurial/pycompat.py:*:* 'xmlrpc.client as xmlrpclib' imported but unused (glob)
  mercurial/util.py:*:* 'pickle' imported but unused (glob)
  

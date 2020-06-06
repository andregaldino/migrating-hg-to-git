#require test-repo pyflakes hg10

  $ . "$TESTDIR/helpers-testrepo.sh"

run pyflakes on all tracked files ending in .py or without a file ending
(skipping binary file random-seed)

  $ cat > test.py <<EOF
  > print(undefinedname)
  > EOF
  $ $PYTHON -m pyflakes test.py 2>/dev/null | "$TESTDIR/filterpyflakes.py"
  test.py:1:* undefined name 'undefinedname' (glob)
  
  $ cd "`dirname "$TESTDIR"`"

  $ testrepohg locate 'set:**.py or grep("^#!.*python")' \
  > -X hgext/fsmonitor/pywatchman \
  > -X mercurial/pycompat.py -X contrib/python-zstandard \
  > -X mercurial/thirdparty \
  > 2>/dev/null \
  > | xargs $PYTHON -m pyflakes 2>/dev/null | "$TESTDIR/filterpyflakes.py"
  contrib/perf.py:*:* undefined name 'xrange' (glob) (?)
  mercurial/hgweb/server.py:*:* undefined name 'reload' (glob) (?)
  mercurial/util.py:*:* undefined name 'file' (glob) (?)
  mercurial/encoding.py:*:* undefined name 'localstr' (glob) (?)
  

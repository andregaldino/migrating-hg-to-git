#require test-repo hg10

  $ . "$TESTDIR/helpers-testrepo.sh"

  $ cat > $TESTTMP/check_ascii.py <<EOF
  > import sys
  > for file_path in sys.argv[1:]:
  >     with open(file_path, 'br') as f:
  >         try:
  >             f.read().decode('ascii', 'strict')
  >         except UnicodeDecodeError as exc:
  >             print('%s: %s' % (file_path, exc))
  > EOF

There are some web servers in the wild that can serve static files with an
incorrect encoding (e.g. https://bz.mercurial-scm.org/show_bug.cgi?id=6559).
One way to prevent any issues is to not use any non-ASCII characters, e.g.
URL-encoding them or using HTML entities.

check charset of all tracked files ending in .js

  $ cd "`dirname "$TESTDIR"`"

  $ testrepohg locate 'set:**.js' \
  > 2>/dev/null \
  > | xargs "$PYTHON" $TESTTMP/check_ascii.py

A script that implements uppercasing all letters in a file.

  $ UPPERCASEPY="$TESTTMP/uppercase.py"
  $ cat > $UPPERCASEPY <<EOF
  > import sys
  > from mercurial.utils.procutil import setbinary
  > setbinary(sys.stdin)
  > setbinary(sys.stdout)
  > sys.stdout.write(sys.stdin.read().upper())
  > EOF
  $ TESTLINES="foo\nbar\nbaz\n"
  $ printf $TESTLINES | "$PYTHON" $UPPERCASEPY
  FOO
  BAR
  BAZ

This file attempts to test our workarounds for pickle's lack of
support for short reads.

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > fix =
  > [fix]
  > uppercase-whole-file:command="$PYTHON" $UPPERCASEPY
  > uppercase-whole-file:pattern=set:**
  > EOF

  $ hg init repo
  $ cd repo

# Create a file that's large enough that it seems to not fit in
# pickle's buffer, making it use the code path that expects our
# _blockingreader's read() method to return bytes.
  $ echo "some stuff" > file
  $ for i in $($TESTDIR/seq.py 13); do
  >   cat file file > tmp
  >   mv -f tmp file
  > done
  $ hg commit -Am "add large file"
  adding file

Check that we don't get a crash

  $ hg fix -r .
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/*-fix.hg (glob)

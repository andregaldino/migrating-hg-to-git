  $ hg init a
  $ cd a
  $ touch a; hg commit -qAm_
  $ hg bookmark $(for i in $($TESTDIR/seq.py 0 20); do echo b$i; done)
  $ hg clone . ../b -q
  $ cd ../b

Checking that when lookup multiple bookmarks in one go, if one of them
fails (thus causing the sshpeer to be stopped), the errors from the
further lookups don't result in tracebacks.

  $ hg pull -r b0 -r nosuchbookmark $(for i in $($TESTDIR/seq.py 1 20); do echo -r b$i; done) ssh://user@dummy/$(pwd)/../a
  pulling from ssh://user@dummy/$TESTTMP/b/../a
  abort: unknown revision 'nosuchbookmark'
  [255]

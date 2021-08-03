Checking how hg behaves when one side of a pull/push doesn't support
some capability (because it's running an older hg version, usually).

  $ hg init repo1
  $ cd repo1
  $ echo a > a; hg add -q a; hg commit -q -m a
  $ hg bookmark a
  $ hg clone -q . ../repo2
  $ cd ../repo2

  $ touch $TESTTMP/disable-lookup.py
  $ disable_cap() {
  >   rm -f $TESTTMP/disable-lookup.pyc # pyc caching is buggy
  >   cat <<EOF > $TESTTMP/disable-lookup.py
  > from mercurial import extensions, wireprotov1server
  > def wcapabilities(orig, *args, **kwargs):
  >   cap = orig(*args, **kwargs)
  >   cap.remove(b'$1')
  >   return cap
  > extensions.wrapfunction(wireprotov1server, '_capabilities', wcapabilities)
  > EOF
  > }
  $ cat >> ../repo1/.hg/hgrc <<EOF
  > [extensions]
  > disable-lookup = $TESTTMP/disable-lookup.py
  > EOF

  $ hg pull ssh://user@dummy/repo1 -r tip -B a
  pulling from ssh://user@dummy/repo1
  no changes found

  $ disable_cap lookup
  $ hg pull ssh://user@dummy/repo1 -r tip -B a
  pulling from ssh://user@dummy/repo1
  abort: other repository doesn't support revision lookup, so a rev cannot be specified.
  [255]

  $ disable_cap pushkey
  $ hg pull ssh://user@dummy/repo1 -r tip -B a
  pulling from ssh://user@dummy/repo1
  abort: remote bookmark a not found!
  [10]

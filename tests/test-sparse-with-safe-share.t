Same with share-safe

  $ echo "[format]"         >> $HGRCPATH
  $ echo "use-share-safe = True" >> $HGRCPATH

  $ cd $TESTTMP

  $ hg init myrepo
  $ cd myrepo
  $ cat > .hg/hgrc <<EOF
  > [extensions]
  > sparse=
  > EOF

  $ echo a > show
  $ echo x > hide
  $ hg ci -Aqm 'initial'

Regression test: checks that this command correctly locks the store
before updating the store [requirements] config.

  $ hg up -q 0
  $ hg debugsparse --include 'hide'

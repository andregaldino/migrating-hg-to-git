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

Verify basic --include

  $ hg up -q 0
  $ hg debugsparse --include 'hide'
  devel-warn: write with no lock: "requires" at: *mercurial/scmutil.py:1558 (writerequires) (glob)

TODO: bug in sparse when used together with safe-share^

#require black

  $ cd $RUNTESTDIR/..
  $ black --config=black.toml --check --diff `hg files 'set:**.py - mercurial/thirdparty/** - "contrib/python-zstandard/**"'`


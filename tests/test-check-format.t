#require black

  $ cd $RUNTESTDIR/..
  $ black --config=black.toml --check --diff `hg files 'set:**.py - hgext/fsmonitor/pywatchman/** - mercurial/thirdparty/** - "contrib/python-zstandard/**"'`


#require black test-repo

  $ cd $RUNTESTDIR/..
  $ black --config=black.toml --check --diff `hg files 'set:(**.py + grep("^#!.*python")) - mercurial/thirdparty/**'`


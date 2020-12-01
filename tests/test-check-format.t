#require black test-repo

  $ cd $RUNTESTDIR/..
  $ black --check --diff `hg files 'set:(**.py + grep("^#!.*python")) - mercurial/thirdparty/**'`


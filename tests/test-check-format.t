#require black test-repo

Black needs the real USERPROFILE in order to run on Windows
#if msys
  $ USERPROFILE="$REALUSERPROFILE"
  $ export USERPROFILE
#endif

  $ cd $RUNTESTDIR/..
  $ black --check --diff `hg files 'set:(**.py + grep("^#!.*python")) - mercurial/thirdparty/**'`


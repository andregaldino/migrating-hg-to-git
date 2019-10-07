#require grey

(this should use the actual black as soon as possible)

  $ cd $RUNTESTDIR/..
  $ python3 contrib/grey.py -S --quiet --check --diff `hg files 'set:**.py - hgext/fsmonitor/pywatchman/** - mercurial/thirdparty/** - "contrib/python-zstandard/**" - contrib/grey.py'`


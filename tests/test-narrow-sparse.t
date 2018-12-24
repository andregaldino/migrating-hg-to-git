Testing interaction of sparse and narrow when both are enabled on the client
side and we do a non-ellipsis clone

#testcases tree flat
  $ . "$TESTDIR/narrow-library.sh"
  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > sparse =
  > EOF

#if tree
  $ cat << EOF >> $HGRCPATH
  > [experimental]
  > treemanifest = 1
  > EOF
#endif

  $ hg init master
  $ cd master

  $ mkdir inside
  $ echo 'inside' > inside/f
  $ hg add inside/f
  $ hg commit -m 'add inside'

  $ mkdir widest
  $ echo 'widest' > widest/f
  $ hg add widest/f
  $ hg commit -m 'add widest'

  $ mkdir outside
  $ echo 'outside' > outside/f
  $ hg add outside/f
  $ hg commit -m 'add outside'

  $ cd ..

narrow clone the inside file

  $ hg clone --narrow ssh://user@dummy/master narrow --include inside/f
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 1 changes to 1 files
  new changesets *:* (glob)
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd narrow
  $ hg tracked
  I path:inside/f
  $ hg files
  inside/f

XXX: we should have a flag in `hg debugsparse` to list the sparse profile
  $ test -f .hg/sparse
  [1]

  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  narrowhg-experimental
  revlogv1
  sparserevlog
  store
  treemanifest (tree !)

  $ hg debugrebuilddirstate
  ** unknown exception encountered, please report by visiting
  ** https://mercurial-scm.org/wiki/BugTracker
  ** Python 2.7.12 (default, Nov 12 2018, 14:36:49) [GCC 5.4.0 20160609]
  ** Mercurial Distributed SCM (version 4.8.1+588-479a5ea51ccc+20181224)
  ** Extensions loaded: narrow, sparse
  Traceback (most recent call last):
    File "/place/vartmp/hgtests.zMelCK/install/bin/hg", line 43, in <module>
      dispatch.run()
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/dispatch.py", line 99, in run
      status = dispatch(req)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/dispatch.py", line 225, in dispatch
      ret = _runcatch(req) or 0
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/dispatch.py", line 376, in _runcatch
      return _callcatch(ui, _runcatchfunc)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/dispatch.py", line 384, in _callcatch
      return scmutil.callcatch(ui, func)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/scmutil.py", line 166, in callcatch
      return func()
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/dispatch.py", line 367, in _runcatchfunc
      return _dispatch(req)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/dispatch.py", line 1021, in _dispatch
      cmdpats, cmdoptions)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/dispatch.py", line 756, in runcommand
      ret = _runcommand(ui, options, cmd, d)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/dispatch.py", line 1030, in _runcommand
      return cmdfunc()
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/dispatch.py", line 1018, in <lambda>
      d = lambda: util.checksignature(func)(ui, *args, **strcmdopt)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/util.py", line 1670, in check
      return func(*args, **kwargs)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/debugcommands.py", line 1998, in debugrebuilddirstate
      dirstate.rebuild(ctx.node(), ctx.manifest(), changedfiles)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/hgext/narrow/narrowdirstate.py", line 60, in rebuild
      super(narrowdirstate, self).rebuild(parent, allfiles, changedfiles)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/mercurial/extensions.py", line 437, in closure
      return func(*(args + a), **kw)
    File "/place/vartmp/hgtests.zMelCK/install/lib/python/hgext/sparse.py", line 213, in _rebuild
      allfiles = allfiles.matches(matcher)
  AttributeError: 'list' object has no attribute 'matches'
  [1]

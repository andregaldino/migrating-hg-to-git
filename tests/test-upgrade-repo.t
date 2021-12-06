#require no-reposimplestore

  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > share =
  > [format]
  > # stabilize test accross variant
  > revlog-compression=zlib
  > EOF

store and revlogv1 are required in source

  $ hg --config format.usestore=false init no-store
  $ hg -R no-store debugupgraderepo
  abort: cannot upgrade repository; requirement missing: store
  [255]

  $ hg init no-revlogv1
  $ cat > no-revlogv1/.hg/requires << EOF
  > dotencode
  > fncache
  > generaldelta
  > store
  > EOF

  $ hg -R no-revlogv1 debugupgraderepo
  abort: cannot upgrade repository; missing a revlog version
  [255]

Cannot upgrade shared repositories

  $ hg init share-parent
  $ hg -q share share-parent share-child

  $ hg -R share-child debugupgraderepo
  abort: cannot upgrade repository; unsupported source requirement: shared
  [255]

Do not yet support upgrading treemanifest repos

  $ hg --config experimental.treemanifest=true init treemanifest
  $ hg -R treemanifest debugupgraderepo
  abort: cannot upgrade repository; unsupported source requirement: treemanifest
  [255]

Cannot add treemanifest requirement during upgrade

  $ hg init disallowaddedreq
  $ hg -R disallowaddedreq --config experimental.treemanifest=true debugupgraderepo
  abort: cannot upgrade repository; do not support adding requirement: treemanifest
  [255]

An upgrade of a repository created with recommended settings only suggests optimizations

  $ hg init empty
  $ cd empty
  $ hg debugformat
  format-variant     repo
  fncache:            yes
  dirstate-v2:         no
  dotencode:          yes
  generaldelta:       yes
  share-safe:          no
  sparserevlog:       yes
  persistent-nodemap:  no (no-rust !)
  persistent-nodemap: yes (rust !)
  copies-sdc:          no
  revlog-v2:           no
  changelog-v2:        no
  plain-cl-delta:     yes
  compression:        zlib
  compression-level:  default
  $ hg debugformat --verbose
  format-variant     repo config default
  fncache:            yes    yes     yes
  dirstate-v2:         no     no      no
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:          no     no      no
  sparserevlog:       yes    yes     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap: yes    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zlib   zlib    zstd (zstd !)
  compression-level:  default default default
  $ hg debugformat --verbose --config format.usefncache=no
  format-variant     repo config default
  fncache:            yes     no     yes
  dirstate-v2:         no     no      no
  dotencode:          yes     no     yes
  generaldelta:       yes    yes     yes
  share-safe:          no     no      no
  sparserevlog:       yes    yes     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap: yes    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zlib   zlib    zstd (zstd !)
  compression-level:  default default default
  $ hg debugformat --verbose --config format.usefncache=no --color=debug
  format-variant     repo config default
  [formatvariant.name.mismatchconfig|fncache:           ][formatvariant.repo.mismatchconfig| yes][formatvariant.config.special|     no][formatvariant.default|     yes]
  [formatvariant.name.uptodate|dirstate-v2:       ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.mismatchconfig|dotencode:         ][formatvariant.repo.mismatchconfig| yes][formatvariant.config.special|     no][formatvariant.default|     yes]
  [formatvariant.name.uptodate|generaldelta:      ][formatvariant.repo.uptodate| yes][formatvariant.config.default|    yes][formatvariant.default|     yes]
  [formatvariant.name.uptodate|share-safe:        ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.uptodate|sparserevlog:      ][formatvariant.repo.uptodate| yes][formatvariant.config.default|    yes][formatvariant.default|     yes]
  [formatvariant.name.uptodate|persistent-nodemap:][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no] (no-rust !)
  [formatvariant.name.mismatchdefault|persistent-nodemap:][formatvariant.repo.mismatchdefault| yes][formatvariant.config.special|    yes][formatvariant.default|      no] (rust !)
  [formatvariant.name.uptodate|copies-sdc:        ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.uptodate|revlog-v2:         ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.uptodate|changelog-v2:      ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.uptodate|plain-cl-delta:    ][formatvariant.repo.uptodate| yes][formatvariant.config.default|    yes][formatvariant.default|     yes]
  [formatvariant.name.uptodate|compression:       ][formatvariant.repo.uptodate| zlib][formatvariant.config.default|   zlib][formatvariant.default|    zlib] (no-zstd !)
  [formatvariant.name.mismatchdefault|compression:       ][formatvariant.repo.mismatchdefault| zlib][formatvariant.config.special|   zlib][formatvariant.default|    zstd] (zstd !)
  [formatvariant.name.uptodate|compression-level: ][formatvariant.repo.uptodate| default][formatvariant.config.default| default][formatvariant.default| default]
  $ hg debugformat -Tjson
  [
   {
    "config": true,
    "default": true,
    "name": "fncache",
    "repo": true
   },
   {
    "config": false,
    "default": false,
    "name": "dirstate-v2",
    "repo": false
   },
   {
    "config": true,
    "default": true,
    "name": "dotencode",
    "repo": true
   },
   {
    "config": true,
    "default": true,
    "name": "generaldelta",
    "repo": true
   },
   {
    "config": false,
    "default": false,
    "name": "share-safe",
    "repo": false
   },
   {
    "config": true,
    "default": true,
    "name": "sparserevlog",
    "repo": true
   },
   {
    "config": false, (no-rust !)
    "config": true, (rust !)
    "default": false,
    "name": "persistent-nodemap",
    "repo": false (no-rust !)
    "repo": true (rust !)
   },
   {
    "config": false,
    "default": false,
    "name": "copies-sdc",
    "repo": false
   },
   {
    "config": false,
    "default": false,
    "name": "revlog-v2",
    "repo": false
   },
   {
    "config": false,
    "default": false,
    "name": "changelog-v2",
    "repo": false
   },
   {
    "config": true,
    "default": true,
    "name": "plain-cl-delta",
    "repo": true
   },
   {
    "config": "zlib",
    "default": "zlib", (no-zstd !)
    "default": "zstd", (zstd !)
    "name": "compression",
    "repo": "zlib"
   },
   {
    "config": "default",
    "default": "default",
    "name": "compression-level",
    "repo": "default"
   }
  ]
  $ hg debugupgraderepo
  (no format upgrades found in existing repository)
  performing an upgrade with "--run" will make the following changes:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  no revlogs to process
  
  additional optimizations are available by specifying "--optimize <name>":
  
  re-delta-parent
     deltas within internal storage will be recalculated to choose an optimal base revision where this was not already done; the size of the repository may shrink and various operations may become faster; the first time this optimization is performed could slow down upgrade execution considerably; subsequent invocations should not run noticeably slower
  
  re-delta-multibase
     deltas within internal storage will be recalculated against multiple base revision and the smallest difference will be used; the size of the repository may shrink significantly when there are many merges; this optimization will slow down execution in proportion to the number of merges in the repository and the amount of files in the repository; this slow down should not be significant unless there are tens of thousands of files and thousands of merges
  
  re-delta-all
     deltas within internal storage will always be recalculated without reusing prior deltas; this will likely make execution run several times slower; this optimization is typically not needed
  
  re-delta-fulladd
     every revision will be re-added as if it was new content. It will go through the full storage mechanism giving extensions a chance to process it (eg. lfs). This is similar to "re-delta-all" but even slower since more logic is involved.
  

  $ hg debugupgraderepo --quiet
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  no revlogs to process
  

--optimize can be used to add optimizations

  $ hg debugupgrade --optimize 're-delta-parent'
  (no format upgrades found in existing repository)
  performing an upgrade with "--run" will make the following changes:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  optimisations: re-delta-parent
  
  re-delta-parent
     deltas within internal storage will choose a new base revision if needed
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  additional optimizations are available by specifying "--optimize <name>":
  
  re-delta-multibase
     deltas within internal storage will be recalculated against multiple base revision and the smallest difference will be used; the size of the repository may shrink significantly when there are many merges; this optimization will slow down execution in proportion to the number of merges in the repository and the amount of files in the repository; this slow down should not be significant unless there are tens of thousands of files and thousands of merges
  
  re-delta-all
     deltas within internal storage will always be recalculated without reusing prior deltas; this will likely make execution run several times slower; this optimization is typically not needed
  
  re-delta-fulladd
     every revision will be re-added as if it was new content. It will go through the full storage mechanism giving extensions a chance to process it (eg. lfs). This is similar to "re-delta-all" but even slower since more logic is involved.
  

modern form of the option

  $ hg debugupgrade --optimize re-delta-parent
  (no format upgrades found in existing repository)
  performing an upgrade with "--run" will make the following changes:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  optimisations: re-delta-parent
  
  re-delta-parent
     deltas within internal storage will choose a new base revision if needed
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  additional optimizations are available by specifying "--optimize <name>":
  
  re-delta-multibase
     deltas within internal storage will be recalculated against multiple base revision and the smallest difference will be used; the size of the repository may shrink significantly when there are many merges; this optimization will slow down execution in proportion to the number of merges in the repository and the amount of files in the repository; this slow down should not be significant unless there are tens of thousands of files and thousands of merges
  
  re-delta-all
     deltas within internal storage will always be recalculated without reusing prior deltas; this will likely make execution run several times slower; this optimization is typically not needed
  
  re-delta-fulladd
     every revision will be re-added as if it was new content. It will go through the full storage mechanism giving extensions a chance to process it (eg. lfs). This is similar to "re-delta-all" but even slower since more logic is involved.
  
  $ hg debugupgrade --optimize re-delta-parent --quiet
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  optimisations: re-delta-parent
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  

unknown optimization:

  $ hg debugupgrade --optimize foobar
  abort: unknown optimization action requested: foobar
  (run without arguments to see valid optimizations)
  [255]

Various sub-optimal detections work

  $ cat > .hg/requires << EOF
  > revlogv1
  > store
  > EOF

  $ hg debugformat
  format-variant     repo
  fncache:             no
  dirstate-v2:         no
  dotencode:           no
  generaldelta:        no
  share-safe:          no
  sparserevlog:        no
  persistent-nodemap:  no
  copies-sdc:          no
  revlog-v2:           no
  changelog-v2:        no
  plain-cl-delta:     yes
  compression:        zlib
  compression-level:  default
  $ hg debugformat --verbose
  format-variant     repo config default
  fncache:             no    yes     yes
  dirstate-v2:         no     no      no
  dotencode:           no    yes     yes
  generaldelta:        no    yes     yes
  share-safe:          no     no      no
  sparserevlog:        no    yes     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap:  no    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zlib   zlib    zstd (zstd !)
  compression-level:  default default default
  $ hg debugformat --verbose --config format.usegeneraldelta=no
  format-variant     repo config default
  fncache:             no    yes     yes
  dirstate-v2:         no     no      no
  dotencode:           no    yes     yes
  generaldelta:        no     no     yes
  share-safe:          no     no      no
  sparserevlog:        no     no     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap:  no    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zlib   zlib    zstd (zstd !)
  compression-level:  default default default
  $ hg debugformat --verbose --config format.usegeneraldelta=no --color=debug
  format-variant     repo config default
  [formatvariant.name.mismatchconfig|fncache:           ][formatvariant.repo.mismatchconfig|  no][formatvariant.config.default|    yes][formatvariant.default|     yes]
  [formatvariant.name.uptodate|dirstate-v2:       ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.mismatchconfig|dotencode:         ][formatvariant.repo.mismatchconfig|  no][formatvariant.config.default|    yes][formatvariant.default|     yes]
  [formatvariant.name.mismatchdefault|generaldelta:      ][formatvariant.repo.mismatchdefault|  no][formatvariant.config.special|     no][formatvariant.default|     yes]
  [formatvariant.name.uptodate|share-safe:        ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.mismatchdefault|sparserevlog:      ][formatvariant.repo.mismatchdefault|  no][formatvariant.config.special|     no][formatvariant.default|     yes]
  [formatvariant.name.uptodate|persistent-nodemap:][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no] (no-rust !)
  [formatvariant.name.mismatchconfig|persistent-nodemap:][formatvariant.repo.mismatchconfig|  no][formatvariant.config.special|    yes][formatvariant.default|      no] (rust !)
  [formatvariant.name.uptodate|copies-sdc:        ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.uptodate|revlog-v2:         ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.uptodate|changelog-v2:      ][formatvariant.repo.uptodate|  no][formatvariant.config.default|     no][formatvariant.default|      no]
  [formatvariant.name.uptodate|plain-cl-delta:    ][formatvariant.repo.uptodate| yes][formatvariant.config.default|    yes][formatvariant.default|     yes]
  [formatvariant.name.uptodate|compression:       ][formatvariant.repo.uptodate| zlib][formatvariant.config.default|   zlib][formatvariant.default|    zlib] (no-zstd !)
  [formatvariant.name.mismatchdefault|compression:       ][formatvariant.repo.mismatchdefault| zlib][formatvariant.config.special|   zlib][formatvariant.default|    zstd] (zstd !)
  [formatvariant.name.uptodate|compression-level: ][formatvariant.repo.uptodate| default][formatvariant.config.default| default][formatvariant.default| default]
  $ hg debugupgraderepo
  note:    selecting all-filelogs for processing to change: dotencode
  note:    selecting all-manifestlogs for processing to change: dotencode
  note:    selecting changelog for processing to change: dotencode
  
  repository lacks features recommended by current config options:
  
  fncache
     long and reserved filenames may not work correctly; repository performance is sub-optimal
  
  dotencode
     storage of filenames beginning with a period or space may not work correctly
  
  generaldelta
     deltas within internal storage are unable to choose optimal revisions; repository is larger and slower than it could be; interaction with other repositories may require extra network and CPU resources, making "hg push" and "hg pull" slower
  
  sparserevlog
     in order to limit disk reading and memory usage on older version, the span of a delta chain from its root to its end is limited, whatever the relevant data in this span. This can severly limit Mercurial ability to build good chain of delta resulting is much more storage space being taken and limit reusability of on disk delta during exchange.
  
  persistent-nodemap (rust !)
     persist the node -> rev mapping on disk to speedup lookup (rust !)
   (rust !)
  
  performing an upgrade with "--run" will make the following changes:
  
  requirements
     preserved: revlogv1, store
     added: dotencode, fncache, generaldelta, sparserevlog (no-rust !)
     added: dotencode, fncache, generaldelta, persistent-nodemap, sparserevlog (rust !)
  
  fncache
     repository will be more resilient to storing certain paths and performance of certain operations should be improved
  
  dotencode
     repository will be better able to store files beginning with a space or period
  
  generaldelta
     repository storage will be able to create optimal deltas; new repository data will be smaller and read times should decrease; interacting with other repositories using this storage model should require less network and CPU resources, making "hg push" and "hg pull" faster
  
  sparserevlog
     Revlog supports delta chain with more unused data between payload. These gaps will be skipped at read time. This allows for better delta chains, making a better compression and faster exchange with server.
  
  persistent-nodemap (rust !)
     Speedup revision lookup by node id. (rust !)
   (rust !)
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  additional optimizations are available by specifying "--optimize <name>":
  
  re-delta-parent
     deltas within internal storage will be recalculated to choose an optimal base revision where this was not already done; the size of the repository may shrink and various operations may become faster; the first time this optimization is performed could slow down upgrade execution considerably; subsequent invocations should not run noticeably slower
  
  re-delta-multibase
     deltas within internal storage will be recalculated against multiple base revision and the smallest difference will be used; the size of the repository may shrink significantly when there are many merges; this optimization will slow down execution in proportion to the number of merges in the repository and the amount of files in the repository; this slow down should not be significant unless there are tens of thousands of files and thousands of merges
  
  re-delta-all
     deltas within internal storage will always be recalculated without reusing prior deltas; this will likely make execution run several times slower; this optimization is typically not needed
  
  re-delta-fulladd
     every revision will be re-added as if it was new content. It will go through the full storage mechanism giving extensions a chance to process it (eg. lfs). This is similar to "re-delta-all" but even slower since more logic is involved.
  
  $ hg debugupgraderepo --quiet
  requirements
     preserved: revlogv1, store
     added: dotencode, fncache, generaldelta, sparserevlog (no-rust !)
     added: dotencode, fncache, generaldelta, persistent-nodemap, sparserevlog (rust !)
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  

  $ hg --config format.dotencode=false debugupgraderepo
  note:    selecting all-filelogs for processing to change: fncache
  note:    selecting all-manifestlogs for processing to change: fncache
  note:    selecting changelog for processing to change: fncache
  
  repository lacks features recommended by current config options:
  
  fncache
     long and reserved filenames may not work correctly; repository performance is sub-optimal
  
  generaldelta
     deltas within internal storage are unable to choose optimal revisions; repository is larger and slower than it could be; interaction with other repositories may require extra network and CPU resources, making "hg push" and "hg pull" slower
  
  sparserevlog
     in order to limit disk reading and memory usage on older version, the span of a delta chain from its root to its end is limited, whatever the relevant data in this span. This can severly limit Mercurial ability to build good chain of delta resulting is much more storage space being taken and limit reusability of on disk delta during exchange.
  
  persistent-nodemap (rust !)
     persist the node -> rev mapping on disk to speedup lookup (rust !)
   (rust !)
  repository lacks features used by the default config options:
  
  dotencode
     storage of filenames beginning with a period or space may not work correctly
  
  
  performing an upgrade with "--run" will make the following changes:
  
  requirements
     preserved: revlogv1, store
     added: fncache, generaldelta, sparserevlog (no-rust !)
     added: fncache, generaldelta, persistent-nodemap, sparserevlog (rust !)
  
  fncache
     repository will be more resilient to storing certain paths and performance of certain operations should be improved
  
  generaldelta
     repository storage will be able to create optimal deltas; new repository data will be smaller and read times should decrease; interacting with other repositories using this storage model should require less network and CPU resources, making "hg push" and "hg pull" faster
  
  sparserevlog
     Revlog supports delta chain with more unused data between payload. These gaps will be skipped at read time. This allows for better delta chains, making a better compression and faster exchange with server.
  
  persistent-nodemap (rust !)
     Speedup revision lookup by node id. (rust !)
   (rust !)
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  additional optimizations are available by specifying "--optimize <name>":
  
  re-delta-parent
     deltas within internal storage will be recalculated to choose an optimal base revision where this was not already done; the size of the repository may shrink and various operations may become faster; the first time this optimization is performed could slow down upgrade execution considerably; subsequent invocations should not run noticeably slower
  
  re-delta-multibase
     deltas within internal storage will be recalculated against multiple base revision and the smallest difference will be used; the size of the repository may shrink significantly when there are many merges; this optimization will slow down execution in proportion to the number of merges in the repository and the amount of files in the repository; this slow down should not be significant unless there are tens of thousands of files and thousands of merges
  
  re-delta-all
     deltas within internal storage will always be recalculated without reusing prior deltas; this will likely make execution run several times slower; this optimization is typically not needed
  
  re-delta-fulladd
     every revision will be re-added as if it was new content. It will go through the full storage mechanism giving extensions a chance to process it (eg. lfs). This is similar to "re-delta-all" but even slower since more logic is involved.
  

  $ cd ..

Upgrading a repository that is already modern essentially no-ops

  $ hg init modern
  $ hg -R modern debugupgraderepo --run
  nothing to do

Upgrading a repository to generaldelta works

  $ hg --config format.usegeneraldelta=false init upgradegd
  $ cd upgradegd
  $ touch f0
  $ hg -q commit -A -m initial
  $ mkdir FooBarDirectory.d
  $ touch FooBarDirectory.d/f1
  $ hg -q commit -A -m 'add f1'
  $ hg -q up -r 0
  >>> from __future__ import absolute_import, print_function
  >>> import random
  >>> random.seed(0) # have a reproducible content
  >>> with open("f2", "wb") as f:
  ...     for i in range(100000):
  ...         f.write(b"%d\n" % random.randint(1000000000, 9999999999)) and None
  $ hg -q commit -A -m 'add f2'

make sure we have a .d file

  $ ls -d .hg/store/data/*
  .hg/store/data/_foo_bar_directory.d.hg
  .hg/store/data/f0.i
  .hg/store/data/f2.d
  .hg/store/data/f2.i

  $ hg debugupgraderepo --run --config format.sparse-revlog=false
  note:    selecting all-filelogs for processing to change: generaldelta
  note:    selecting all-manifestlogs for processing to change: generaldelta
  note:    selecting changelog for processing to change: generaldelta
  
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, revlogv1, store (no-rust !)
     preserved: dotencode, fncache, persistent-nodemap, revlogv1, store (rust !)
     added: generaldelta
  
  generaldelta
     repository storage will be able to create optimal deltas; new repository data will be smaller and read times should decrease; interacting with other repositories using this storage model should require less network and CPU resources, making "hg push" and "hg pull" faster
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 9 total revisions (3 in filelogs, 3 in manifests, 3 in changelog)
  migrating 519 KB in store; 1.05 MB tracked data
  migrating 3 filelogs containing 3 revisions (518 KB in store; 1.05 MB tracked data)
  finished migrating 3 filelog revisions across 3 filelogs; change in size: 0 bytes
  migrating 1 manifests containing 3 revisions (384 bytes in store; 238 bytes tracked data)
  finished migrating 3 manifest revisions across 1 manifests; change in size: -17 bytes
  migrating changelog containing 3 revisions (394 bytes in store; 199 bytes tracked data)
  finished migrating 3 changelog revisions; change in size: 0 bytes
  finished migrating 9 total revisions; total change in store size: -17 bytes
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replaced files will be backed up at $TESTTMP/upgradegd/.hg/upgradebackup.* (glob)
  replacing store...
  store replacement complete; repository was inconsistent for *s (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  copy of old repository backed up at $TESTTMP/upgradegd/.hg/upgradebackup.* (glob)
  the old repository will not be deleted; remove it to free up disk space once the upgraded repository is verified

Original requirements backed up

  $ cat .hg/upgradebackup.*/requires
  dotencode
  fncache
  persistent-nodemap (rust !)
  revlogv1
  store

generaldelta added to original requirements files

  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlogv1
  store

store directory has files we expect

  $ ls .hg/store
  00changelog.i
  00manifest.i
  data
  fncache
  phaseroots
  undo
  undo.backupfiles
  undo.phaseroots

manifest should be generaldelta

  $ hg debugrevlog -m | grep flags
  flags  : inline, generaldelta

verify should be happy

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 3 changes to 3 files

old store should be backed up

  $ ls -d .hg/upgradebackup.*/
  .hg/upgradebackup.*/ (glob)
  $ ls .hg/upgradebackup.*/store
  00changelog.i
  00manifest.i
  data
  fncache
  phaseroots
  undo
  undo.backup.fncache
  undo.backupfiles
  undo.phaseroots

unless --no-backup is passed

  $ rm -rf .hg/upgradebackup.*/
  $ hg debugupgraderepo --run --no-backup
  note:    selecting all-filelogs for processing to change: sparserevlog
  note:    selecting all-manifestlogs for processing to change: sparserevlog
  note:    selecting changelog for processing to change: sparserevlog
  
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, store (rust !)
     added: sparserevlog
  
  sparserevlog
     Revlog supports delta chain with more unused data between payload. These gaps will be skipped at read time. This allows for better delta chains, making a better compression and faster exchange with server.
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 9 total revisions (3 in filelogs, 3 in manifests, 3 in changelog)
  migrating 519 KB in store; 1.05 MB tracked data
  migrating 3 filelogs containing 3 revisions (518 KB in store; 1.05 MB tracked data)
  finished migrating 3 filelog revisions across 3 filelogs; change in size: 0 bytes
  migrating 1 manifests containing 3 revisions (367 bytes in store; 238 bytes tracked data)
  finished migrating 3 manifest revisions across 1 manifests; change in size: 0 bytes
  migrating changelog containing 3 revisions (394 bytes in store; 199 bytes tracked data)
  finished migrating 3 changelog revisions; change in size: 0 bytes
  finished migrating 9 total revisions; total change in store size: 0 bytes
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replacing store...
  store replacement complete; repository was inconsistent for * (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  $ ls -1 .hg/ | grep upgradebackup
  [1]

We can restrict optimization to some revlog:

  $ hg debugupgrade --optimize re-delta-parent --run --manifest --no-backup --debug --traceback
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  optimisations: re-delta-parent
  
  re-delta-parent
     deltas within internal storage will choose a new base revision if needed
  
  processed revlogs:
    - manifest
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 9 total revisions (3 in filelogs, 3 in manifests, 3 in changelog)
  migrating 519 KB in store; 1.05 MB tracked data
  migrating 3 filelogs containing 3 revisions (518 KB in store; 1.05 MB tracked data)
  blindly copying data/FooBarDirectory.d/f1.i containing 1 revisions
  blindly copying data/f0.i containing 1 revisions
  blindly copying data/f2.i containing 1 revisions
  finished migrating 3 filelog revisions across 3 filelogs; change in size: 0 bytes
  migrating 1 manifests containing 3 revisions (367 bytes in store; 238 bytes tracked data)
  cloning 3 revisions from 00manifest.i
  finished migrating 3 manifest revisions across 1 manifests; change in size: 0 bytes
  migrating changelog containing 3 revisions (394 bytes in store; 199 bytes tracked data)
  blindly copying 00changelog.i containing 3 revisions
  finished migrating 3 changelog revisions; change in size: 0 bytes
  finished migrating 9 total revisions; total change in store size: 0 bytes
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replacing store...
  store replacement complete; repository was inconsistent for *s (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/upgradegd/.hg/upgrade.* (glob)

Check that the repo still works fine

  $ hg log -G --stat
  @  changeset:   2:76d4395f5413 (no-py3 !)
  @  changeset:   2:fca376863211 (py3 !)
  |  tag:         tip
  |  parent:      0:ba592bf28da2
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     add f2
  |
  |   f2 |  100000 +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  |   1 files changed, 100000 insertions(+), 0 deletions(-)
  |
  | o  changeset:   1:2029ce2354e2
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     add f1
  |
  |
  o  changeset:   0:ba592bf28da2
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     initial
  
  

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 3 changes to 3 files

Check we can select negatively

  $ hg debugupgrade --optimize re-delta-parent --run --no-manifest --no-backup --debug --traceback
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  optimisations: re-delta-parent
  
  re-delta-parent
     deltas within internal storage will choose a new base revision if needed
  
  processed revlogs:
    - all-filelogs
    - changelog
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 9 total revisions (3 in filelogs, 3 in manifests, 3 in changelog)
  migrating 519 KB in store; 1.05 MB tracked data
  migrating 3 filelogs containing 3 revisions (518 KB in store; 1.05 MB tracked data)
  cloning 1 revisions from data/FooBarDirectory.d/f1.i
  cloning 1 revisions from data/f0.i
  cloning 1 revisions from data/f2.i
  finished migrating 3 filelog revisions across 3 filelogs; change in size: 0 bytes
  migrating 1 manifests containing 3 revisions (367 bytes in store; 238 bytes tracked data)
  blindly copying 00manifest.i containing 3 revisions
  finished migrating 3 manifest revisions across 1 manifests; change in size: 0 bytes
  migrating changelog containing 3 revisions (394 bytes in store; 199 bytes tracked data)
  cloning 3 revisions from 00changelog.i
  finished migrating 3 changelog revisions; change in size: 0 bytes
  finished migrating 9 total revisions; total change in store size: 0 bytes
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replacing store...
  store replacement complete; repository was inconsistent for *s (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 3 changes to 3 files

Check that we can select changelog only

  $ hg debugupgrade --optimize re-delta-parent --run --changelog --no-backup --debug --traceback
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  optimisations: re-delta-parent
  
  re-delta-parent
     deltas within internal storage will choose a new base revision if needed
  
  processed revlogs:
    - changelog
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 9 total revisions (3 in filelogs, 3 in manifests, 3 in changelog)
  migrating 519 KB in store; 1.05 MB tracked data
  migrating 3 filelogs containing 3 revisions (518 KB in store; 1.05 MB tracked data)
  blindly copying data/FooBarDirectory.d/f1.i containing 1 revisions
  blindly copying data/f0.i containing 1 revisions
  blindly copying data/f2.i containing 1 revisions
  finished migrating 3 filelog revisions across 3 filelogs; change in size: 0 bytes
  migrating 1 manifests containing 3 revisions (367 bytes in store; 238 bytes tracked data)
  blindly copying 00manifest.i containing 3 revisions
  finished migrating 3 manifest revisions across 1 manifests; change in size: 0 bytes
  migrating changelog containing 3 revisions (394 bytes in store; 199 bytes tracked data)
  cloning 3 revisions from 00changelog.i
  finished migrating 3 changelog revisions; change in size: 0 bytes
  finished migrating 9 total revisions; total change in store size: 0 bytes
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replacing store...
  store replacement complete; repository was inconsistent for *s (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 3 changes to 3 files

Check that we can select filelog only

  $ hg debugupgrade --optimize re-delta-parent --run --no-changelog --no-manifest --no-backup --debug --traceback
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  optimisations: re-delta-parent
  
  re-delta-parent
     deltas within internal storage will choose a new base revision if needed
  
  processed revlogs:
    - all-filelogs
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 9 total revisions (3 in filelogs, 3 in manifests, 3 in changelog)
  migrating 519 KB in store; 1.05 MB tracked data
  migrating 3 filelogs containing 3 revisions (518 KB in store; 1.05 MB tracked data)
  cloning 1 revisions from data/FooBarDirectory.d/f1.i
  cloning 1 revisions from data/f0.i
  cloning 1 revisions from data/f2.i
  finished migrating 3 filelog revisions across 3 filelogs; change in size: 0 bytes
  migrating 1 manifests containing 3 revisions (367 bytes in store; 238 bytes tracked data)
  blindly copying 00manifest.i containing 3 revisions
  finished migrating 3 manifest revisions across 1 manifests; change in size: 0 bytes
  migrating changelog containing 3 revisions (394 bytes in store; 199 bytes tracked data)
  blindly copying 00changelog.i containing 3 revisions
  finished migrating 3 changelog revisions; change in size: 0 bytes
  finished migrating 9 total revisions; total change in store size: 0 bytes
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replacing store...
  store replacement complete; repository was inconsistent for *s (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 3 changes to 3 files


Check you can't skip revlog clone during important format downgrade

  $ echo "[format]" > .hg/hgrc
  $ echo "sparse-revlog=no" >> .hg/hgrc
  $ hg debugupgrade --optimize re-delta-parent --no-manifest --no-backup --quiet
  warning: ignoring  --no-manifest, as upgrade is changing: sparserevlog
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, store (rust !)
     removed: sparserevlog
  
  optimisations: re-delta-parent
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg debugupgrade --optimize re-delta-parent --run --manifest --no-backup --debug --traceback
  note:    selecting all-filelogs for processing to change: sparserevlog
  note:    selecting changelog for processing to change: sparserevlog
  
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, store (rust !)
     removed: sparserevlog
  
  optimisations: re-delta-parent
  
  re-delta-parent
     deltas within internal storage will choose a new base revision if needed
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 9 total revisions (3 in filelogs, 3 in manifests, 3 in changelog)
  migrating 519 KB in store; 1.05 MB tracked data
  migrating 3 filelogs containing 3 revisions (518 KB in store; 1.05 MB tracked data)
  cloning 1 revisions from data/FooBarDirectory.d/f1.i
  cloning 1 revisions from data/f0.i
  cloning 1 revisions from data/f2.i
  finished migrating 3 filelog revisions across 3 filelogs; change in size: 0 bytes
  migrating 1 manifests containing 3 revisions (367 bytes in store; 238 bytes tracked data)
  cloning 3 revisions from 00manifest.i
  finished migrating 3 manifest revisions across 1 manifests; change in size: 0 bytes
  migrating changelog containing 3 revisions (394 bytes in store; 199 bytes tracked data)
  cloning 3 revisions from 00changelog.i
  finished migrating 3 changelog revisions; change in size: 0 bytes
  finished migrating 9 total revisions; total change in store size: 0 bytes
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replacing store...
  store replacement complete; repository was inconsistent for *s (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 3 changes to 3 files

Check you can't skip revlog clone during important format upgrade

  $ echo "sparse-revlog=yes" >> .hg/hgrc
  $ hg debugupgrade --optimize re-delta-parent --run --manifest --no-backup --debug --traceback
  note:    selecting all-filelogs for processing to change: sparserevlog
  note:    selecting changelog for processing to change: sparserevlog
  
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, store (rust !)
     added: sparserevlog
  
  optimisations: re-delta-parent
  
  sparserevlog
     Revlog supports delta chain with more unused data between payload. These gaps will be skipped at read time. This allows for better delta chains, making a better compression and faster exchange with server.
  
  re-delta-parent
     deltas within internal storage will choose a new base revision if needed
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 9 total revisions (3 in filelogs, 3 in manifests, 3 in changelog)
  migrating 519 KB in store; 1.05 MB tracked data
  migrating 3 filelogs containing 3 revisions (518 KB in store; 1.05 MB tracked data)
  cloning 1 revisions from data/FooBarDirectory.d/f1.i
  cloning 1 revisions from data/f0.i
  cloning 1 revisions from data/f2.i
  finished migrating 3 filelog revisions across 3 filelogs; change in size: 0 bytes
  migrating 1 manifests containing 3 revisions (367 bytes in store; 238 bytes tracked data)
  cloning 3 revisions from 00manifest.i
  finished migrating 3 manifest revisions across 1 manifests; change in size: 0 bytes
  migrating changelog containing 3 revisions (394 bytes in store; 199 bytes tracked data)
  cloning 3 revisions from 00changelog.i
  finished migrating 3 changelog revisions; change in size: 0 bytes
  finished migrating 9 total revisions; total change in store size: 0 bytes
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replacing store...
  store replacement complete; repository was inconsistent for *s (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/upgradegd/.hg/upgrade.* (glob)
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 3 changes to 3 files

  $ cd ..

store files with special filenames aren't encoded during copy

  $ hg init store-filenames
  $ cd store-filenames
  $ touch foo
  $ hg -q commit -A -m initial
  $ touch .hg/store/.XX_special_filename

  $ hg debugupgraderepo --run
  nothing to do
  $ hg debugupgraderepo --run --optimize 're-delta-fulladd'
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  optimisations: re-delta-fulladd
  
  re-delta-fulladd
     each revision will be added as new content to the internal storage; this will likely drastically slow down execution time, but some extensions might need it
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/store-filenames/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 3 total revisions (1 in filelogs, 1 in manifests, 1 in changelog)
  migrating 301 bytes in store; 107 bytes tracked data
  migrating 1 filelogs containing 1 revisions (64 bytes in store; 0 bytes tracked data)
  finished migrating 1 filelog revisions across 1 filelogs; change in size: 0 bytes
  migrating 1 manifests containing 1 revisions (110 bytes in store; 45 bytes tracked data)
  finished migrating 1 manifest revisions across 1 manifests; change in size: 0 bytes
  migrating changelog containing 1 revisions (127 bytes in store; 62 bytes tracked data)
  finished migrating 1 changelog revisions; change in size: 0 bytes
  finished migrating 3 total revisions; total change in store size: 0 bytes
  copying .XX_special_filename
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replaced files will be backed up at $TESTTMP/store-filenames/.hg/upgradebackup.* (glob)
  replacing store...
  store replacement complete; repository was inconsistent for *s (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/store-filenames/.hg/upgrade.* (glob)
  copy of old repository backed up at $TESTTMP/store-filenames/.hg/upgradebackup.* (glob)
  the old repository will not be deleted; remove it to free up disk space once the upgraded repository is verified

fncache is valid after upgrade

  $ hg debugrebuildfncache
  fncache already up to date

  $ cd ..

Check upgrading a large file repository
---------------------------------------

  $ hg init largefilesrepo
  $ cat << EOF >> largefilesrepo/.hg/hgrc
  > [extensions]
  > largefiles =
  > EOF

  $ cd largefilesrepo
  $ touch foo
  $ hg add --large foo
  $ hg -q commit -m initial
  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  largefiles
  persistent-nodemap (rust !)
  revlogv1
  sparserevlog
  store

  $ hg debugupgraderepo --run
  nothing to do
  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  largefiles
  persistent-nodemap (rust !)
  revlogv1
  sparserevlog
  store

  $ cat << EOF >> .hg/hgrc
  > [extensions]
  > lfs =
  > [lfs]
  > threshold = 10
  > EOF
  $ echo '123456789012345' > lfs.bin
  $ hg ci -Am 'lfs.bin'
  adding lfs.bin
  $ grep lfs .hg/requires
  lfs
  $ find .hg/store/lfs -type f
  .hg/store/lfs/objects/d0/beab232adff5ba365880366ad30b1edb85c4c5372442b5d2fe27adc96d653f

  $ hg debugupgraderepo --run
  nothing to do

  $ grep lfs .hg/requires
  lfs
  $ find .hg/store/lfs -type f
  .hg/store/lfs/objects/d0/beab232adff5ba365880366ad30b1edb85c4c5372442b5d2fe27adc96d653f
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 2 changesets with 2 changes to 2 files
  $ hg debugdata lfs.bin 0
  version https://git-lfs.github.com/spec/v1
  oid sha256:d0beab232adff5ba365880366ad30b1edb85c4c5372442b5d2fe27adc96d653f
  size 16
  x-is-binary 0

  $ cd ..

repository config is taken in account
-------------------------------------

  $ cat << EOF >> $HGRCPATH
  > [format]
  > maxchainlen = 1
  > EOF

  $ hg init localconfig
  $ cd localconfig
  $ cat << EOF > file
  > some content
  > with some length
  > to make sure we get a delta
  > after changes
  > very long
  > very long
  > very long
  > very long
  > very long
  > very long
  > very long
  > very long
  > very long
  > very long
  > very long
  > EOF
  $ hg -q commit -A -m A
  $ echo "new line" >> file
  $ hg -q commit -m B
  $ echo "new line" >> file
  $ hg -q commit -m C

  $ cat << EOF >> .hg/hgrc
  > [format]
  > maxchainlen = 9001
  > EOF
  $ hg config format
  format.revlog-compression=$BUNDLE2_COMPRESSIONS$
  format.maxchainlen=9001
  $ hg debugdeltachain file
      rev  chain# chainlen     prev   delta       size    rawsize  chainsize     ratio   lindist extradist extraratio   readsize largestblk rddensity srchunks
        0       1        1       -1    base         77        182         77   0.42308        77         0    0.00000         77         77   1.00000        1
        1       1        2        0      p1         21        191         98   0.51309        98         0    0.00000         98         98   1.00000        1
        2       1        2        0   other         30        200        107   0.53500       128        21    0.19626        128        128   0.83594        1

  $ hg debugupgraderepo --run --optimize 're-delta-all'
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
  
  optimisations: re-delta-all
  
  re-delta-all
     deltas within internal storage will be fully recomputed; this will likely drastically slow down execution time
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/localconfig/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  migrating 9 total revisions (3 in filelogs, 3 in manifests, 3 in changelog)
  migrating 1019 bytes in store; 882 bytes tracked data
  migrating 1 filelogs containing 3 revisions (320 bytes in store; 573 bytes tracked data)
  finished migrating 3 filelog revisions across 1 filelogs; change in size: -9 bytes
  migrating 1 manifests containing 3 revisions (333 bytes in store; 138 bytes tracked data)
  finished migrating 3 manifest revisions across 1 manifests; change in size: 0 bytes
  migrating changelog containing 3 revisions (366 bytes in store; 171 bytes tracked data)
  finished migrating 3 changelog revisions; change in size: 0 bytes
  finished migrating 9 total revisions; total change in store size: -9 bytes
  copying phaseroots
  data fully upgraded in a temporary repository
  marking source repository as being upgraded; clients will be unable to read from repository
  starting in-place swap of repository data
  replaced files will be backed up at $TESTTMP/localconfig/.hg/upgradebackup.* (glob)
  replacing store...
  store replacement complete; repository was inconsistent for *s (glob)
  finalizing requirements file and making repository readable again
  removing temporary repository $TESTTMP/localconfig/.hg/upgrade.* (glob)
  copy of old repository backed up at $TESTTMP/localconfig/.hg/upgradebackup.* (glob)
  the old repository will not be deleted; remove it to free up disk space once the upgraded repository is verified
  $ hg debugdeltachain file
      rev  chain# chainlen     prev   delta       size    rawsize  chainsize     ratio   lindist extradist extraratio   readsize largestblk rddensity srchunks
        0       1        1       -1    base         77        182         77   0.42308        77         0    0.00000         77         77   1.00000        1
        1       1        2        0      p1         21        191         98   0.51309        98         0    0.00000         98         98   1.00000        1
        2       1        3        1      p1         21        200        119   0.59500       119         0    0.00000        119        119   1.00000        1
  $ cd ..

  $ cat << EOF >> $HGRCPATH
  > [format]
  > maxchainlen = 9001
  > EOF

Check upgrading a sparse-revlog repository
---------------------------------------

  $ hg init sparserevlogrepo --config format.sparse-revlog=no
  $ cd sparserevlogrepo
  $ touch foo
  $ hg add foo
  $ hg -q commit -m "foo"
  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlogv1
  store

Check that we can add the sparse-revlog format requirement
  $ hg --config format.sparse-revlog=yes debugupgraderepo --run --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, store (rust !)
     added: sparserevlog
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlogv1
  sparserevlog
  store

Check that we can remove the sparse-revlog format requirement
  $ hg --config format.sparse-revlog=no debugupgraderepo --run --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, store (rust !)
     removed: sparserevlog
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlogv1
  store

#if zstd

Check upgrading to a zstd revlog
--------------------------------

upgrade

  $ hg --config format.revlog-compression=zstd debugupgraderepo --run  --no-backup --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, store (rust !)
     added: revlog-compression-zstd, sparserevlog
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg debugformat -v
  format-variant     repo config default
  fncache:            yes    yes     yes
  dirstate-v2:         no     no      no
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:          no     no      no
  sparserevlog:       yes    yes     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap: yes    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zstd   zlib    zstd (zstd !)
  compression-level:  default default default
  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd
  revlogv1
  sparserevlog
  store

downgrade

  $ hg debugupgraderepo --run --no-backup --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
     removed: revlog-compression-zstd
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg debugformat -v
  format-variant     repo config default
  fncache:            yes    yes     yes
  dirstate-v2:         no     no      no
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:          no     no      no
  sparserevlog:       yes    yes     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap: yes    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zlib   zlib    zstd (zstd !)
  compression-level:  default default default
  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlogv1
  sparserevlog
  store

upgrade from hgrc

  $ cat >> .hg/hgrc << EOF
  > [format]
  > revlog-compression=zstd
  > EOF
  $ hg debugupgraderepo --run --no-backup --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, revlogv1, sparserevlog, store (no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlogv1, sparserevlog, store (rust !)
     added: revlog-compression-zstd
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg debugformat -v
  format-variant     repo config default
  fncache:            yes    yes     yes
  dirstate-v2:         no     no      no
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:          no     no      no
  sparserevlog:       yes    yes     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap: yes    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zstd   zstd    zstd (zstd !)
  compression-level:  default default default
  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd
  revlogv1
  sparserevlog
  store

#endif

Check upgrading to a revlog format supporting sidedata
------------------------------------------------------

upgrade

  $ hg debugsidedata -c 0
  $ hg --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data debugupgraderepo --run  --no-backup --config "extensions.sidedata=$TESTDIR/testlib/ext-sidedata.py" --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, store (no-zstd !)
     preserved: dotencode, fncache, generaldelta, revlog-compression-zstd, sparserevlog, store (zstd no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlog-compression-zstd, sparserevlog, store (rust !)
     removed: revlogv1
     added: exp-revlogv2.2 (zstd !)
     added: exp-revlogv2.2, sparserevlog (no-zstd !)
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg debugformat -v
  format-variant     repo config default
  fncache:            yes    yes     yes
  dirstate-v2:         no     no      no
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:          no     no      no
  sparserevlog:       yes    yes     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap: yes    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:          yes     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zstd   zstd    zstd (zstd !)
  compression-level:  default default default
  $ cat .hg/requires
  dotencode
  exp-revlogv2.2
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  sparserevlog
  store
  $ hg debugsidedata -c 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32

downgrade

  $ hg debugupgraderepo --config experimental.revlogv2=no --run --no-backup --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, sparserevlog, store (no-zstd !)
     preserved: dotencode, fncache, generaldelta, revlog-compression-zstd, sparserevlog, store (zstd no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlog-compression-zstd, sparserevlog, store (rust !)
     removed: exp-revlogv2.2
     added: revlogv1
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg debugformat -v
  format-variant     repo config default
  fncache:            yes    yes     yes
  dirstate-v2:         no     no      no
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:          no     no      no
  sparserevlog:       yes    yes     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap: yes    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zstd   zstd    zstd (zstd !)
  compression-level:  default default default
  $ cat .hg/requires
  dotencode
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  revlogv1
  sparserevlog
  store
  $ hg debugsidedata -c 0

upgrade from hgrc

  $ cat >> .hg/hgrc << EOF
  > [experimental]
  > revlogv2=enable-unstable-format-and-corrupt-my-data
  > EOF
  $ hg debugupgraderepo --run --no-backup --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: dotencode, fncache, generaldelta, sparserevlog, store (no-zstd !)
     preserved: dotencode, fncache, generaldelta, revlog-compression-zstd, sparserevlog, store (zstd no-rust !)
     preserved: dotencode, fncache, generaldelta, persistent-nodemap, revlog-compression-zstd, sparserevlog, store (rust !)
     removed: revlogv1
     added: exp-revlogv2.2
  
  processed revlogs:
    - all-filelogs
    - changelog
    - manifest
  
  $ hg debugformat -v
  format-variant     repo config default
  fncache:            yes    yes     yes
  dirstate-v2:         no     no      no
  dotencode:          yes    yes     yes
  generaldelta:       yes    yes     yes
  share-safe:          no     no      no
  sparserevlog:       yes    yes     yes
  persistent-nodemap:  no     no      no (no-rust !)
  persistent-nodemap: yes    yes      no (rust !)
  copies-sdc:          no     no      no
  revlog-v2:          yes    yes      no
  changelog-v2:        no     no      no
  plain-cl-delta:     yes    yes     yes
  compression:        zlib   zlib    zlib (no-zstd !)
  compression:        zstd   zstd    zstd (zstd !)
  compression-level:  default default default
  $ cat .hg/requires
  dotencode
  exp-revlogv2.2
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  sparserevlog
  store
  $ hg debugsidedata -c 0

Demonstrate that nothing to perform upgrade will still run all the way through

  $ hg debugupgraderepo --run
  nothing to do

#if no-rust

  $ cat << EOF >> $HGRCPATH
  > [storage]
  > dirstate-v2.slow-path = allow
  > EOF

#endif

Upgrade to dirstate-v2

  $ hg debugformat -v --config format.exp-rc-dirstate-v2=1 | grep dirstate-v2
  dirstate-v2:         no    yes      no
  $ hg debugupgraderepo --config format.exp-rc-dirstate-v2=1 --run
  upgrade will perform the following actions:
  
  requirements
     preserved: * (glob)
     added: dirstate-v2
  
  dirstate-v2
     "hg status" will be faster
  
  no revlogs to process
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/sparserevlogrepo/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  upgrading to dirstate-v2 from v1
  replaced files will be backed up at $TESTTMP/sparserevlogrepo/.hg/upgradebackup.* (glob)
  removing temporary repository $TESTTMP/sparserevlogrepo/.hg/upgrade.* (glob)
  $ ls .hg/upgradebackup.*/dirstate
  .hg/upgradebackup.*/dirstate (glob)
  $ hg debugformat -v | grep dirstate-v2
  dirstate-v2:        yes     no      no
  $ hg status
  $ dd bs=12 count=1 if=.hg/dirstate 2> /dev/null
  dirstate-v2

Downgrade from dirstate-v2

  $ hg debugupgraderepo --run
  upgrade will perform the following actions:
  
  requirements
     preserved: * (glob)
     removed: dirstate-v2
  
  no revlogs to process
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/sparserevlogrepo/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  downgrading from dirstate-v2 to v1
  replaced files will be backed up at $TESTTMP/sparserevlogrepo/.hg/upgradebackup.* (glob)
  removing temporary repository $TESTTMP/sparserevlogrepo/.hg/upgrade.* (glob)
  $ hg debugformat -v | grep dirstate-v2
  dirstate-v2:         no     no      no
  $ hg status

  $ cd ..

dirstate-v2: upgrade and downgrade from and empty repository:
-------------------------------------------------------------

  $ hg init --config format.exp-rc-dirstate-v2=no dirstate-v2-empty
  $ cd dirstate-v2-empty
  $ hg debugformat | grep dirstate-v2
  dirstate-v2:         no

upgrade

  $ hg debugupgraderepo --run --config format.exp-rc-dirstate-v2=yes
  upgrade will perform the following actions:
  
  requirements
     preserved: * (glob)
     added: dirstate-v2
  
  dirstate-v2
     "hg status" will be faster
  
  no revlogs to process
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/dirstate-v2-empty/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  upgrading to dirstate-v2 from v1
  replaced files will be backed up at $TESTTMP/dirstate-v2-empty/.hg/upgradebackup.* (glob)
  removing temporary repository $TESTTMP/dirstate-v2-empty/.hg/upgrade.* (glob)
  $ hg debugformat | grep dirstate-v2
  dirstate-v2:        yes

downgrade

  $ hg debugupgraderepo --run --config format.exp-rc-dirstate-v2=no
  upgrade will perform the following actions:
  
  requirements
     preserved: * (glob)
     removed: dirstate-v2
  
  no revlogs to process
  
  beginning upgrade...
  repository locked and read-only
  creating temporary repository to stage upgraded data: $TESTTMP/dirstate-v2-empty/.hg/upgrade.* (glob)
  (it is safe to interrupt this process any time before data migration completes)
  downgrading from dirstate-v2 to v1
  replaced files will be backed up at $TESTTMP/dirstate-v2-empty/.hg/upgradebackup.* (glob)
  removing temporary repository $TESTTMP/dirstate-v2-empty/.hg/upgrade.* (glob)
  $ hg debugformat | grep dirstate-v2
  dirstate-v2:         no

  $ cd ..

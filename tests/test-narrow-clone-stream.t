#testcases tree flat-fncache flat-nofncache

Tests narrow stream clones

  $ . "$TESTDIR/narrow-library.sh"

#if tree
  $ cat << EOF >> $HGRCPATH
  > [experimental]
  > treemanifest = 1
  > EOF
#endif

#if flat-nofncache
  $ cat << EOF >> $HGRCPATH
  > [format]
  > usefncache = 0
  > EOF
#endif

Server setup

  $ hg init master
  $ cd master
  $ mkdir dir
  $ mkdir dir/src
  $ cd dir/src
  $ for x in `$TESTDIR/seq.py 20`; do echo $x > "F$x"; hg add "F$x"; hg commit -m "Commit src $x"; done

  $ cd ..
  $ mkdir tests
  $ cd tests
  $ for x in `$TESTDIR/seq.py 20`; do echo $x > "F$x"; hg add "F$x"; hg commit -m "Commit src $x"; done
  $ cd ../../..

Trying to stream clone when the server does not support it

  $ hg clone --narrow ssh://user@dummy/master narrow --noupdate --include "dir/src/F10" --stream
  streaming all changes
  remote: abort: server does not support narrow stream clones
  abort: pull failed on remote
  [100]

Enable stream clone on the server

  $ echo "[experimental]" >> master/.hg/hgrc
  $ echo "server.stream-narrow-clones=True" >> master/.hg/hgrc

Cloning a specific file when stream clone is supported

  $ hg clone --narrow ssh://user@dummy/master narrow --noupdate --include "dir/src/F10" --stream
  streaming all changes
  * files to transfer, * KB of data (glob)
  transferred * KB in * seconds (* */sec) (glob)

  $ cd narrow
  $ ls -A
  .hg
  $ hg tracked
  I path:dir/src/F10

Making sure we have the correct set of requirements

  $ hg debugrequires
  dotencode (tree !)
  dotencode (flat-fncache !)
  dirstate-v2 (dirstate-v2 !)
  fncache (tree !)
  fncache (flat-fncache !)
  generaldelta
  narrowhg-experimental
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  revlogv1
  share-safe
  sparserevlog
  store
  treemanifest (tree !)

Making sure store has the required files

  $ ls .hg/store/
  00changelog.i
  00manifest.i
  data
  fncache (tree !)
  fncache (flat-fncache !)
  meta (tree !)
  narrowspec
  requires
  undo
  undo.backupfiles
  undo.narrowspec
  undo.phaseroots

Checking that repository has all the required data and not broken

  $ hg verify
  checking changesets
  checking manifests
  checking directory manifests (tree !)
  crosschecking files in changesets and manifests
  checking files
  checked 40 changesets with 1 changes to 1 files

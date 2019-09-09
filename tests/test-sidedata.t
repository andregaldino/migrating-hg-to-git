==========================================================
Test file dedicated to checking side-data related behavior
==========================================================

Check data can be written/read from sidedata
============================================

  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata.py
  > EOF

  $ hg init test-sidedata --config format.use-side-data=yes
  $ cd test-sidedata
  $ echo aaa > a
  $ hg add a
  $ hg commit -m a --traceback
  $ echo aaa > b
  $ hg add b
  $ hg commit -m b
  $ echo xxx >> a
  $ hg commit -m aa

Check upgrade behavior
======================

Right now, sidedata has not upgrade support

Check that we cannot upgrade to sidedata
----------------------------------------

  $ hg init up-no-side-data --config format.use-side-data=no
  $ hg debugformat -v -R up-no-side-data
  format-variant    repo config default
  fncache:           yes    yes     yes
  dotencode:         yes    yes     yes
  generaldelta:      yes    yes     yes
  sparserevlog:      yes    yes     yes
  sidedata:           no     no      no
  plain-cl-delta:    yes    yes     yes
  compression:       zlib   zlib    zlib
  compression-level: default default default
  $ hg debugformat -v -R up-no-side-data --config format.use-side-data=yes
  format-variant    repo config default
  fncache:           yes    yes     yes
  dotencode:         yes    yes     yes
  generaldelta:      yes    yes     yes
  sparserevlog:      yes    yes     yes
  sidedata:           no    yes      no
  plain-cl-delta:    yes    yes     yes
  compression:       zlib   zlib    zlib
  compression-level: default default default
  $ hg debugupgraderepo -R up-no-side-data --config format.use-side-data=yes
  abort: cannot upgrade repository; do not support adding requirement: exp-sidedata-flag
  [255]

Check that we cannot upgrade to sidedata
----------------------------------------

  $ hg init up-side-data --config format.use-side-data=yes
  $ hg debugformat -v -R up-side-data
  format-variant    repo config default
  fncache:           yes    yes     yes
  dotencode:         yes    yes     yes
  generaldelta:      yes    yes     yes
  sparserevlog:      yes    yes     yes
  sidedata:          yes     no      no
  plain-cl-delta:    yes    yes     yes
  compression:       zlib   zlib    zlib
  compression-level: default default default
  $ hg debugformat -v -R up-side-data --config format.use-side-data=no
  format-variant    repo config default
  fncache:           yes    yes     yes
  dotencode:         yes    yes     yes
  generaldelta:      yes    yes     yes
  sparserevlog:      yes    yes     yes
  sidedata:          yes     no      no
  plain-cl-delta:    yes    yes     yes
  compression:       zlib   zlib    zlib
  compression-level: default default default
  $ hg debugupgraderepo -R up-side-data --config format.use-side-data=no
  abort: cannot upgrade repository; requirement would be removed: exp-sidedata-flag
  [255]

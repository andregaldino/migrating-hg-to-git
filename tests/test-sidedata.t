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

  $ hg debugsidedata -c 0
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg debugsidedata -c 1 -v
  2 sidedata entries
   entry-0001 size 4
    '\x00\x00\x006'
   entry-0002 size 32
    '\x98\t\xf9\xc4v\xf0\xc5P\x90\xf7wRf\xe8\xe27e\xfc\xc1\x93\xa4\x96\xd0\x1d\x97\xaaG\x1d\xd7t\xfa\xde'
  $ hg debugsidedata -m 2
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32
  $ hg debugsidedata a  1
  2 sidedata entries
   entry-0001 size 4
   entry-0002 size 32

Check upgrade behavior
======================

Right now, sidedata has not upgrade support

Check that we can upgrade to sidedata
-------------------------------------

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
  $ hg debugupgraderepo -R up-no-side-data --config format.use-side-data=yes > /dev/null

Check that we can downgrade from sidedata
-----------------------------------------

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
  $ hg debugupgraderepo -R up-side-data --config format.use-side-data=no > /dev/null

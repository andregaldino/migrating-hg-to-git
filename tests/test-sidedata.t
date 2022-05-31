==========================================================
Test file dedicated to checking side-data related behavior
==========================================================

Check data can be written/read from sidedata
============================================

  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > testsidedata=$TESTDIR/testlib/ext-sidedata.py
  > EOF

  $ hg init test-sidedata --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
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

  $ hg debug-revlog-index --verbose -c
     rev   rank linkrev       nodeid p1-rev    p1-nodeid p2-rev    p2-nodeid            full-size delta-base flags comp-mode          data-offset chunk-size sd-comp-mode      sidedata-offset sd-chunk-size
       0     -1       0 7049e48789d7     -1 000000000000     -1 000000000000                   54          0     0         0                    0         54        plain                    0            90
       1     -1       1 2707720c6597      0 7049e48789d7     -1 000000000000                   54          1     0         0                   54         54        plain                   90            90
       2     -1       2 40f977031323      1 2707720c6597     -1 000000000000                   55          2     0         0                  108         55        plain                  180            90

  $ hg debug-revlog-index --verbose -m
     rev   rank linkrev       nodeid p1-rev    p1-nodeid p2-rev    p2-nodeid            full-size delta-base flags comp-mode          data-offset chunk-size sd-comp-mode      sidedata-offset sd-chunk-size
       0     -1       0 b85d294330e3     -1 000000000000     -1 000000000000                   43          0     0         0                    0         43        plain                    0            90
       1     -1       1 1a0aec305c63      0 b85d294330e3     -1 000000000000                   86          0     0         0                   43         55        plain                   90            90
       2     -1       2 104258a4f75f      1 1a0aec305c63     -1 000000000000                   86          1     0         0                   98         55        plain                  180            90

Check upgrade behavior
======================

Right now, sidedata has not upgrade support

Check that we can upgrade to sidedata
-------------------------------------

  $ hg init up-no-side-data --config experimental.revlogv2=no
  $ hg debugformat -v -R up-no-side-data | egrep 'changelog-v2|revlog-v2'
  revlog-v2:           no     no      no
  changelog-v2:        no     no      no
  $ hg debugformat -v -R up-no-side-data --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data | egrep 'changelog-v2|revlog-v2'
  revlog-v2:           no    yes      no
  changelog-v2:        no     no      no
  $ hg debugupgraderepo -R up-no-side-data --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data > /dev/null

Check that we can downgrade from sidedata
-----------------------------------------

  $ hg init up-side-data --config experimental.revlogv2=enable-unstable-format-and-corrupt-my-data
  $ hg debugformat -v -R up-side-data | egrep 'changelog-v2|revlog-v2'
  revlog-v2:          yes     no      no
  changelog-v2:        no     no      no
  $ hg debugformat -v -R up-side-data --config experimental.revlogv2=no | egrep 'changelog-v2|revlog-v2'
  revlog-v2:          yes     no      no
  changelog-v2:        no     no      no
  $ hg debugupgraderepo -R up-side-data --config experimental.revlogv2=no > /dev/null

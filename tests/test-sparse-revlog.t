====================================
Test delta choice with sparse revlog
====================================

Sparse-revlog usually shows the most gain on Manifest. However, it is simpler
to general an appropriate file, so we test with a single file instead. The
goal is to observe intermediate snapshot being created.

We need a large enough file. Part of the content needs to be replaced
repeatedly while some of it changes rarely.

  $ bundlepath="$TESTDIR/artifacts/cache/big-file-churn.hg"

  $ expectedhash=`cat "$bundlepath".md5`
  $ if [ ! -f "$bundlepath" ]; then
  >     echo 'skipped: missing artifact, run "'"$TESTDIR"'/artifacts/scripts/generate-churning-bundle.py"'
  >     exit 80
  > fi
  $ currenthash=`f -M "$bundlepath" | cut -d = -f 2`
  $ if [ "$currenthash" != "$expectedhash" ]; then
  >     echo 'skipped: outdated artifact, md5 "'"$currenthash"'" expected "'"$expectedhash"'" run "'"$TESTDIR"'/artifacts/scripts/generate-churning-bundle.py"'
  >     exit 80
  > fi

  $ cat >> $HGRCPATH << EOF
  > [format]
  > sparse-revlog = yes
  > maxchainlen = 15
  > [storage]
  > revlog.optimize-delta-parent-choice = yes
  > [format]
  > generaldelta = yes
  > EOF
  $ hg init sparse-repo
  $ cd sparse-repo
  $ hg unbundle $bundlepath
  adding changesets
  adding manifests
  adding file changes
  added 5001 changesets with 5001 changes to 1 files (+89 heads)
  new changesets 9706f5af64f4:d9032adc8114 (5001 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg up
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  updated to "d9032adc8114: commit #5000"
  89 other heads for branch "default"

  $ hg log --stat -r 0:3
  changeset:   0:9706f5af64f4
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     initial commit
  
   SPARSE-REVLOG-TEST-FILE |  10500 ++++++++++++++++++++++++++++++++++++++++++++++
   1 files changed, 10500 insertions(+), 0 deletions(-)
  
  changeset:   1:724907deaa5e
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     commit #1
  
   SPARSE-REVLOG-TEST-FILE |  1068 +++++++++++++++++++++++-----------------------
   1 files changed, 534 insertions(+), 534 deletions(-)
  
  changeset:   2:62c41bce3e5d
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     commit #2
  
   SPARSE-REVLOG-TEST-FILE |  1068 +++++++++++++++++++++++-----------------------
   1 files changed, 534 insertions(+), 534 deletions(-)
  
  changeset:   3:348a9cbd6959
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     commit #3
  
   SPARSE-REVLOG-TEST-FILE |  1068 +++++++++++++++++++++++-----------------------
   1 files changed, 534 insertions(+), 534 deletions(-)
  

  $ f -s .hg/store/data/*.d
  .hg/store/data/_s_p_a_r_s_e-_r_e_v_l_o_g-_t_e_s_t-_f_i_l_e.d: size=63327412
  $ hg debugrevlog *
  format : 1
  flags  : generaldelta
  
  revisions     :     5001
      merges    :      625 (12.50%)
      normal    :     4376 (87.50%)
  revisions     :     5001
      empty     :        0 ( 0.00%)
                     text  :        0 (100.00%)
                     delta :        0 (100.00%)
      snapshot  :      383 ( 7.66%)
        lvl-0   :              3 ( 0.06%)
        lvl-1   :             20 ( 0.40%)
        lvl-2   :             68 ( 1.36%)
        lvl-3   :            112 ( 2.24%)
        lvl-4   :            180 ( 3.60%)
      deltas    :     4618 (92.34%)
  revision size : 63327412
      snapshot  :  9886710 (15.61%)
        lvl-0   :         603104 ( 0.95%)
        lvl-1   :        1559991 ( 2.46%)
        lvl-2   :        2295592 ( 3.62%)
        lvl-3   :        2531199 ( 4.00%)
        lvl-4   :        2896824 ( 4.57%)
      deltas    : 53440702 (84.39%)
  
  chunks        :     5001
      0x78 (x)  :     5001 (100.00%)
  chunks size   : 63327412
      0x78 (x)  : 63327412 (100.00%)
  
  avg chain length  :        9
  max chain length  :       15
  max chain reach   : 28248745
  compression ratio :       27
  
  uncompressed data size (min/max/avg) : 346468 / 346472 / 346471
  full revision size (min/max/avg)     : 201008 / 201050 / 201034
  inter-snapshot size (min/max/avg)    : 11596 / 168150 / 24430
      level-1   (min/max/avg)          : 16653 / 168150 / 77999
      level-2   (min/max/avg)          : 12951 / 85595 / 33758
      level-3   (min/max/avg)          : 11608 / 43029 / 22599
      level-4   (min/max/avg)          : 11596 / 21632 / 16093
  delta size (min/max/avg)             : 10649 / 107163 / 11572
  
  deltas against prev  : 3910 (84.67%)
      where prev = p1  : 3910     (100.00%)
      where prev = p2  :    0     ( 0.00%)
      other            :    0     ( 0.00%)
  deltas against p1    :  648 (14.03%)
  deltas against p2    :   60 ( 1.30%)
  deltas against other :    0 ( 0.00%)

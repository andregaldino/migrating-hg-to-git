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

#if slow

  $ if [ ! -f "$bundlepath" ]; then
  >     "$TESTDIR"/artifacts/scripts/generate-churning-bundle.py > /dev/null
  > fi

#else

  $ if [ ! -f "$bundlepath" ]; then
  >     echo 'skipped: missing artifact, run "'"$TESTDIR"'/artifacts/scripts/generate-churning-bundle.py"'
  >     exit 80
  > fi

#endif

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
  > revlog.reuse-external-delta = no
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
  .hg/store/data/_s_p_a_r_s_e-_r_e_v_l_o_g-_t_e_s_t-_f_i_l_e.d: size=58616973
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
        lvl-1   :             18 ( 0.36%)
        lvl-2   :             62 ( 1.24%)
        lvl-3   :            108 ( 2.16%)
        lvl-4   :            191 ( 3.82%)
        lvl-5   :              1 ( 0.02%)
      deltas    :     4618 (92.34%)
  revision size : 58616973
      snapshot  :  9247844 (15.78%)
        lvl-0   :         539532 ( 0.92%)
        lvl-1   :        1467743 ( 2.50%)
        lvl-2   :        1873820 ( 3.20%)
        lvl-3   :        2326874 ( 3.97%)
        lvl-4   :        3029118 ( 5.17%)
        lvl-5   :          10757 ( 0.02%)
      deltas    : 49369129 (84.22%)
  
  chunks        :     5001
      0x28      :     5001 (100.00%)
  chunks size   : 58616973
      0x28      : 58616973 (100.00%)
  
  avg chain length  :        9
  max chain length  :       15
  max chain reach   : 27366701
  compression ratio :       29
  
  uncompressed data size (min/max/avg) : 346468 / 346472 / 346471
  full revision size (min/max/avg)     : 179288 / 180786 / 179844
  inter-snapshot size (min/max/avg)    : 10757 / 169507 / 22916
      level-1   (min/max/avg)          : 13905 / 169507 / 81541
      level-2   (min/max/avg)          : 10887 / 83873 / 30222
      level-3   (min/max/avg)          : 10911 / 43047 / 21545
      level-4   (min/max/avg)          : 10838 / 21390 / 15859
      level-5   (min/max/avg)          : 10757 / 10757 / 10757
  delta size (min/max/avg)             : 9672 / 108072 / 10690
  
  deltas against prev  : 3906 (84.58%)
      where prev = p1  : 3906     (100.00%)
      where prev = p2  :    0     ( 0.00%)
      other            :    0     ( 0.00%)
  deltas against p1    :  649 (14.05%)
  deltas against p2    :   63 ( 1.36%)
  deltas against other :    0 ( 0.00%)

  $ cd ..

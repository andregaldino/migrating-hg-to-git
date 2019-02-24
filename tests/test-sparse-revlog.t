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
  .hg/store/data/_s_p_a_r_s_e-_r_e_v_l_o_g-_t_e_s_t-_f_i_l_e.d: size=65281524
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
      snapshot  :      372 ( 7.44%)
        lvl-0   :              4 ( 0.08%)
        lvl-1   :             25 ( 0.50%)
        lvl-2   :             74 ( 1.48%)
        lvl-3   :            117 ( 2.34%)
        lvl-4   :            152 ( 3.04%)
      deltas    :     4629 (92.56%)
  revision size : 65281524
      snapshot  :  9910992 (15.18%)
        lvl-0   :         804162 ( 1.23%)
        lvl-1   :        1816378 ( 2.78%)
        lvl-2   :        2355855 ( 3.61%)
        lvl-3   :        2557680 ( 3.92%)
        lvl-4   :        2376917 ( 3.64%)
      deltas    : 55370532 (84.82%)
  
  chunks        :     5001
      0x78 (x)  :     5001 (100.00%)
  chunks size   : 65281524
      0x78 (x)  : 65281524 (100.00%)
  
  avg chain length  :        9
  max chain length  :       15
  max chain reach   : 27873839
  compression ratio :       26
  
  uncompressed data size (min/max/avg) : 346468 / 346472 / 346471
  full revision size (min/max/avg)     : 200973 / 201094 / 201040
  inter-snapshot size (min/max/avg)    : 11586 / 170448 / 24746
      level-1   (min/max/avg)          : 14021 / 170448 / 72655
      level-2   (min/max/avg)          : 11616 / 81152 / 31835
      level-3   (min/max/avg)          : 11607 / 42813 / 21860
      level-4   (min/max/avg)          : 11586 / 21590 / 15637
  delta size (min/max/avg)             : 10649 / 166014 / 11961
  
  deltas against prev  : 3839 (82.93%)
      where prev = p1  : 3839     (100.00%)
      where prev = p2  :    0     ( 0.00%)
      other            :    0     ( 0.00%)
  deltas against p1    :  634 (13.70%)
  deltas against p2    :   62 ( 1.34%)
  deltas against other :   94 ( 2.03%)

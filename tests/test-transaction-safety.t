Test transaction safety
=======================

#testcases revlogv1 revlogv2 changelogv2

#if revlogv1

  $ cat << EOF >> $HGRCPATH
  > [experimental]
  > revlogv2=no
  > EOF

#endif

#if revlogv2

  $ cat << EOF >> $HGRCPATH
  > [experimental]
  > revlogv2=enable-unstable-format-and-corrupt-my-data
  > EOF

#endif

#if changelogv2

  $ cat << EOF >> $HGRCPATH
  > [format]
  > exp-use-changelog-v2=enable-unstable-format-and-corrupt-my-data
  > EOF

#endif

This test basic case to make sure external process do not see transaction
content until it is committed.

# TODO: also add an external reader accessing revlog files while they are written
#       (instead of during transaction finalisation)

# TODO: also add stream clone and hardlink clone happening during these transaction.

setup
-----

synchronisation+output script:

  $ mkdir sync
  $ mkdir output
  $ mkdir script
  $ HG_TEST_FILE_EXT_WAITING=$TESTTMP/sync/ext_waiting
  $ export HG_TEST_FILE_EXT_WAITING
  $ HG_TEST_FILE_EXT_UNLOCK=$TESTTMP/sync/ext_unlock
  $ export HG_TEST_FILE_EXT_UNLOCK
  $ HG_TEST_FILE_EXT_DONE=$TESTTMP/sync/ext_done
  $ export HG_TEST_FILE_EXT_DONE
  $ cat << EOF > script/external.sh
  > #!/bin/sh
  > "$RUNTESTDIR/testlib/wait-on-file" 5 "$HG_TEST_FILE_EXT_UNLOCK" "$HG_TEST_FILE_EXT_WAITING"
  > hg log --rev 'tip' -T 'external: {rev} {desc}\n' > "$TESTTMP/output/external.out"
  > touch "$HG_TEST_FILE_EXT_DONE"
  > EOF
  $ cat << EOF > script/internal.sh
  > #!/bin/sh
  > hg log --rev 'tip' -T 'internal: {rev} {desc}\n' > "$TESTTMP/output/internal.out"
  > "$RUNTESTDIR/testlib/wait-on-file" 5 "$HG_TEST_FILE_EXT_DONE" "$HG_TEST_FILE_EXT_UNLOCK"
  > EOF


Automated commands:

  $ make_one_commit() {
  > rm -f $TESTTMP/sync/*
  > rm -f $TESTTMP/output/*
  > hg log --rev 'tip' -T 'pre-commit: {rev} {desc}\n'
  > echo x >> a
  > sh $TESTTMP/script/external.sh & hg commit -m "$1"
  > cat $TESTTMP/output/external.out
  > cat $TESTTMP/output/internal.out
  > hg log --rev 'tip' -T 'post-tr:  {rev} {desc}\n'
  > }


  $ make_one_pull() {
  > rm -f $TESTTMP/sync/*
  > rm -f $TESTTMP/output/*
  > hg log --rev 'tip' -T 'pre-commit: {rev} {desc}\n'
  > echo x >> a
  > sh $TESTTMP/script/external.sh & hg pull ../other-repo/ --rev "$1" --force --quiet
  > cat $TESTTMP/output/external.out
  > cat $TESTTMP/output/internal.out
  > hg log --rev 'tip' -T 'post-tr:  {rev} {desc}\n'
  > }

prepare a large source to which to pull from:

The source is large to unsure we don't use inline more after the pull

  $ hg init other-repo
  $ hg -R other-repo debugbuilddag .+500


prepare an empty repository where to make test:

  $ hg init repo
  $ cd repo
  $ touch a
  $ hg add a

prepare a small extension to controll inline size

  $ mkdir $TESTTMP/ext
  $ cat << EOF > $TESTTMP/ext/small_inline.py
  > from mercurial import revlog
  > revlog._maxinline = 64 * 100
  > EOF




  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > small_inline=$TESTTMP/ext/small_inline.py
  > [hooks]
  > pretxnclose = sh $TESTTMP/script/internal.sh
  > EOF

check this is true for the initial commit (inline → inline)
-----------------------------------------------------------

the repository should still be inline (for relevant format)

  $ make_one_commit first
  pre-commit: -1 
  external: -1 
  internal: 0 first
  post-tr:  0 first

#if revlogv1

  $ hg debugrevlog -c | grep inline
  flags  : inline

#endif

check this is true for extra commit (inline → inline)
-----------------------------------------------------

the repository should still be inline (for relevant format)

#if revlogv1

  $ hg debugrevlog -c | grep inline
  flags  : inline

#endif

  $ make_one_commit second
  pre-commit: 0 first
  external: 0 first
  internal: 1 second
  post-tr:  1 second

#if revlogv1

  $ hg debugrevlog -c | grep inline
  flags  : inline

#endif

check this is true for a small pull (inline → inline)
-----------------------------------------------------

the repository should still be inline (for relevant format)

#if revlogv1

  $ hg debugrevlog -c | grep inline
  flags  : inline

#endif

  $ make_one_pull 3
  pre-commit: 1 second
  warning: repository is unrelated
  external: 1 second
  internal: 5 r3
  post-tr:  5 r3

#if revlogv1

  $ hg debugrevlog -c | grep inline
  flags  : inline

#endif

Make a large pull (inline → no-inline)
---------------------------------------

the repository should no longer be inline (for relevant format)

#if revlogv1

  $ hg debugrevlog -c | grep inline
  flags  : inline

#endif

  $ make_one_pull 400
  pre-commit: 5 r3
  external: 5 r3
  internal: 402 r400
  post-tr:  402 r400

#if revlogv1

  $ hg debugrevlog -c | grep inline
  [1]

#endif

check this is true for extra commit (no-inline → no-inline)
-----------------------------------------------------------

the repository should no longer be inline (for relevant format)

#if revlogv1

  $ hg debugrevlog -c | grep inline
  [1]

#endif

  $ make_one_commit third
  pre-commit: 402 r400
  external: 402 r400
  internal: 403 third
  post-tr:  403 third

#if revlogv1

  $ hg debugrevlog -c | grep inline
  [1]

#endif


Make a  pull (not-inline → no-inline)
-------------------------------------

the repository should no longer be inline (for relevant format)

#if revlogv1

  $ hg debugrevlog -c | grep inline
  [1]

#endif

  $ make_one_pull tip
  pre-commit: 403 third
  external: 403 third
  internal: 503 r500
  post-tr:  503 r500

#if revlogv1

  $ hg debugrevlog -c | grep inline
  [1]

#endif

Testing recorded "modified" files for merge commit
==================================================

This file shows what hg says are "modified" files for a merge commit
(hg log -T {files}), somewhat exhaustively.

This test file shows merges that involves files contents changing

For merges taht involves executable bit changing, check test-merge-combination-exec-bytes.t

For testing of multiple corner case, check test-merge-combination-misc.t

Case with multiple or zero merge ancestors, copies/renames, and identical file contents
with different filelog revisions are not currently covered.

  $ . $TESTDIR/testlib/merge-combination-util.sh

All the merges of various file contents.

  $ range () {
  >   max=0
  >   for i in $@; do
  >     if [ $i = - ]; then continue; fi
  >     if [ $i -gt $max ]; then max=$i; fi
  >   done
  >   $TESTDIR/seq.py `expr $max + 1`
  > }
  $ isgood () { true; }
  $ createfile () {
  >   if [ -f a ] && [ "`cat a`" = $1 ]
  >   then touch $file
  >   else echo $v > a
  >   fi
  > }

  $ genmerges
  1111  : agree on ""
  1112  : agree on "a"
  111-  : agree on "a"
  1121  : agree on "a"
  1122  : agree on ""
  1123  : agree on "a"
  112-  : agree on "a"
  11-1  : hg said "", expected "a"
  11-2  : agree on "a"
  11--  : agree on ""
  1211  : agree on "a"
  1212  : agree on ""
  1213  : agree on "a"
  121-  : agree on "a"
  1221  : agree on "a"
  1222  : agree on ""
  1223  : agree on "a"
  122-  : agree on "a"
  1231 C: agree on "a"
  1232 C: agree on "a"
  1233 C: agree on "a"
  1234 C: agree on "a"
  123- C: agree on "a"
  12-1 C: agree on "a"
  12-2 C: hg said "", expected "a"
  12-3 C: agree on "a"
  12-- C: agree on "a"
  1-11  : hg said "", expected "a"
  1-12  : agree on "a"
  1-1-  : agree on ""
  1-21 C: agree on "a"
  1-22 C: hg said "", expected "a"
  1-23 C: agree on "a"
  1-2- C: agree on "a"
  1--1  : agree on "a"
  1--2  : agree on "a"
  1---  : agree on ""
  -111  : agree on ""
  -112  : agree on "a"
  -11-  : agree on "a"
  -121 C: agree on "a"
  -122 C: agree on "a"
  -123 C: agree on "a"
  -12- C: agree on "a"
  -1-1  : agree on ""
  -1-2  : agree on "a"
  -1--  : agree on "a"
  --11  : agree on ""
  --12  : agree on "a"
  --1-  : agree on "a"
  ---1  : agree on "a"
  ----  : agree on ""

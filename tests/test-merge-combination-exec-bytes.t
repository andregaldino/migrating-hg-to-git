Testing recorded "modified" files for merge commit
==================================================

#require execbit

This file shows what hg says are "modified" files for a merge commit
(hg log -T {files}), somewhat exhaustively.

This test file shows merges that involves executable bit changing, check test-merge-combination-exec-bytes.t

For merges that involve files contents changing, check test-merge-combination-file-content.t

For testing of multiple corner case, check test-merge-combination-misc.t

Case with multiple or zero merge ancestors, copies/renames, and identical file contents
with different filelog revisions are not currently covered.

  $ . $TESTDIR/testlib/merge-combination-util.sh

All the merges of executable bit.

  $ range () {
  >   max=a
  >   for i in $@; do
  >     if [ $i = - ]; then continue; fi
  >     if [ $i > $max ]; then max=$i; fi
  >   done
  >   if [ $max = a ]; then echo f; else echo f x; fi
  > }
  $ isgood () { case $line in *f*x*) true;; *) false;; esac; }
  $ createfile () {
  >   if [ -f a ] && (([ -x a ] && [ $v = x ]) || (! [ -x a ] && [ $v != x ]))
  >   then touch $file
  >   else touch a; if [ $v = x ]; then chmod +x a; else chmod -x a; fi
  >   fi
  > }

  $ genmerges
  fffx  : agree on "a"
  ffxf  : agree on "a"
  ffxx  : agree on ""
  ffx-  : agree on "a"
  ff-x  : hg said "", expected "a"
  fxff  : hg said "", expected "a"
  fxfx  : hg said "a", expected ""
  fxf-  : agree on "a"
  fxxf  : agree on "a"
  fxxx  : agree on ""
  fxx-  : agree on "a"
  fx-f  : hg said "", expected "a"
  fx-x  : hg said "", expected "a"
  fx--  : hg said "", expected "a"
  f-fx  : agree on "a"
  f-xf  : agree on "a"
  f-xx  : hg said "", expected "a"
  f-x-  : agree on "a"
  f--x  : agree on "a"
  -ffx  : agree on "a"
  -fxf C: agree on "a"
  -fxx C: hg said "", expected "a"
  -fx- C: agree on "a"
  -f-x  : hg said "", expected "a"
  --fx  : agree on "a"

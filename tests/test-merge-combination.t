This file shows what hg says are "modified" files for a merge commit
(hg log -T {files}), somewhat exhaustively.
It shows merges that involves files contents changing, and merges that
involve executable bit changing, but not merges with multiple or zero
merge ancestors, nor copies/renames, and nor identical file contents
with different filelog revisions.

genmerges is the workhorse. Given:
- a range function describing the possible values for file a
- a isgood function to filter out uninteresting combination
- a createfile function to actually write the values for file a on the
filesystem
it print a series of lines that look like: abcd C: output of -T {files}
describing the file a at respectively the base, p2, p1, merge
revision. "C" indicates that hg merge had conflicts.
  $ genmerges () {
  >   for base in `range` -; do
  >     for r1 in `range $base` -; do
  >       for r2 in `range $base $r1` -; do
  >         for m in `range $base $r1 $r2` -; do
  >           line="$base$r1$r2$m"
  >           isgood $line || continue
  >           hg init repo
  >           cd repo
  >           make_commit () {
  >             v=$1; msg=$2; file=$3;
  >             if [ $v != - ]; then
  >               createfile $v
  >             else
  >               if [ -f a ]
  >               then rm a
  >               else touch $file
  >               fi
  >             fi
  >             hg commit -q -Am $msg || exit 123
  >           }
  >           echo foo > foo
  >           make_commit $base base b
  >           make_commit $r1 r1 c
  >           hg up -r 0 -q
  >           make_commit $r2 r2 d
  >           hg merge -q -r 1 > ../output 2>&1
  >           if [ $? -ne 0 ]; then rm -f *.orig; hg resolve -m --all -q; fi
  >           if [ -s ../output ]; then conflicts=" C"; else conflicts="  "; fi
  >           make_commit $m m e
  >           if [ $m = $r1 ] && [ $m = $r2 ]
  >           then expected=
  >           elif [ $m = $r1 ]
  >           then if [ $base = $r2 ]
  >                then expected=
  >                else expected=a
  >                fi
  >           elif [ $m = $r2 ]
  >           then if [ $base = $r1 ]
  >                then expected=
  >                else expected=a
  >                fi
  >           else expected=a
  >           fi
  >           got=`hg log -r 3 --template '{files}\n' | tr -d 'e '`
  >           if [ "$got" = "$expected" ]
  >           then echo "$line$conflicts: agree on \"$got\""
  >           else echo "$line$conflicts: hg said \"$got\", expected \"$expected\""
  >           fi
  >           cd ../
  >           rm -rf repo
  >         done
  >       done
  >     done
  >   done
  > }

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

#if execbit
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
#endif

Files modified or cleanly merged, with no greatest common ancestors:

  $ hg init repo; cd repo
  $ touch a0 b0; hg commit -qAm 0
  $ hg up -qr null; touch a1 b1; hg commit -qAm 1
  $ hg merge -qr 0; rm b*; hg commit -qAm 2
  $ hg log -r . -T '{files}\n'
  b0 b1
  $ cd ../
  $ rm -rf repo

A few cases of criss-cross merges involving deletions (listing all
such merges is probably too much). Both gcas contain $files, so we
expect the final merge to behave like a merge with a single gca
containing $files.

  $ hg init repo; cd repo
  $ files="c1 u1 c2 u2"
  $ touch $files; hg commit -qAm '0 root'
  $ for f in $files; do echo f > $f; done; hg commit -qAm '1 gca1'
  $ hg up -qr0; hg revert -qr 1 --all; hg commit -qAm '2 gca2'
  $ hg up -qr 1; hg merge -qr 2; rm *1; hg commit -qAm '3 p1'
  $ hg up -qr 2; hg merge -qr 1; rm *2; hg commit -qAm '4 p2'
  $ hg merge -qr 3; echo f > u1; echo f > u2; rm -f c1 c2
  $ hg commit -qAm '5 merge with two gcas'
  $ hg log -r . -T '{files}\n' # expecting u1 u2
  
  $ cd ../
  $ rm -rf repo

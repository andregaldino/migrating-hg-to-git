# genmerges is the workhorse of the test-merge-combination-*.t tests.

# Given:
# - a `range` function describing the possible values for file a
# - a `isgood` function to filter out uninteresting combination
# - a `createfile` function to actually write the values for file a on the
#   filesystem
#
# it print a series of lines that look like: abcd C: output of -T {files}
# describing the file a at respectively the base, p2, p1, merge
# revision. "C" indicates that hg merge had conflicts.

genmerges () {

  (LC_ALL=C type range | grep -q 'function') || (echo >&2 "missing function: range")
  (LC_ALL=C type isgood | grep -q 'function') || (echo >&2 "missing function: isgood")
  (LC_ALL=C type createfile | grep -q 'function') || (echo >&2 "missing function: createfile")

  for base in `range` -; do
    for r1 in `range $base` -; do
      for r2 in `range $base $r1` -; do
        for m in `range $base $r1 $r2` -; do
          line="$base$r1$r2$m"
          isgood $line || continue
          hg init repo
          cd repo
          make_commit () {
            v=$1; msg=$2; file=$3;
            if [ $v != - ]; then
              createfile $v
            else
              if [ -f a ]
              then rm a
              else touch $file
              fi
            fi
            hg commit -q -Am $msg || exit 123
          }
          echo foo > foo
          make_commit $base base b
          make_commit $r1 r1 c
          hg up -r 0 -q
          make_commit $r2 r2 d
          hg merge -q -r 1 > ../output 2>&1
          if [ $? -ne 0 ]; then rm -f *.orig; hg resolve -m --all -q; fi
          if [ -s ../output ]; then conflicts=" C"; else conflicts="  "; fi
          make_commit $m m e
          if [ $m = $r1 ] && [ $m = $r2 ]
          then expected=
          elif [ $m = $r1 ]
          then if [ $base = $r2 ]
               then expected=
               else expected=a
               fi
          elif [ $m = $r2 ]
          then if [ $base = $r1 ]
               then expected=
               else expected=a
               fi
          else expected=a
          fi
          got=`hg log -r 3 --template '{files}\n' | tr -d 'e '`
          if [ "$got" = "$expected" ]
          then echo "$line$conflicts: agree on \"$got\""
          else echo "$line$conflicts: hg said \"$got\", expected \"$expected\""
          fi
          cd ../
          rm -rf repo
        done
      done
    done
  done
}

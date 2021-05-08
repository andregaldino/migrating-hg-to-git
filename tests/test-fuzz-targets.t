#require test-repo py3

  $ cd $TESTDIR/../contrib/fuzz
  $ OUT=$TESTTMP ; export OUT

which(1) could exit nonzero, but that's fine because we'll still end
up without a valid executable, so we don't need to check $? here.

  $ if which gmake >/dev/null 2>&1; then
  >     MAKE=gmake
  > else
  >     MAKE=make
  > fi

  $ havefuzz() {
  >     cat > $TESTTMP/dummy.cc <<EOF
  > #include <stdlib.h>
  > #include <stdint.h>
  > int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) { return 0; }
  > int main(int argc, char **argv) {
  >     const char data[] = "asdf";
  >     return LLVMFuzzerTestOneInput((const uint8_t *)data, 4);
  > }
  > EOF
  >     $CXX $TESTTMP/dummy.cc -o $TESTTMP/dummy \
  >        -fsanitize=fuzzer-no-link,address || return 1
  > }

Try to find a python3-config that's next to our sys.executable. If
that doesn't work, fall back to looking for a global python3-config
and hope that works out for the best.
  $ PYBIN=`"$PYTHON" -c 'import sys, os; print(os.path.dirname(sys.executable))'`
  $ if [ -x "$PYBIN/python3-config" ] ; then
  >   PYTHON_CONFIG="$PYBIN/python3-config"
  > else
  >   PYTHON_CONFIG="`which python3-config`"
  > fi

#if clang-libfuzzer
  $ CXX=clang++ havefuzz || exit 80
  $ $MAKE -s clean all PYTHON_CONFIG="$PYTHON_CONFIG"
#endif
#if no-clang-libfuzzer clang-6.0
  $ CXX=clang++-6.0 havefuzz || exit 80
  $ $MAKE -s clean all CC=clang-6.0 CXX=clang++-6.0 PYTHON_CONFIG="$PYTHON_CONFIG"
#endif
#if no-clang-libfuzzer no-clang-6.0
  $ exit 80
#endif

  $ cd $TESTTMP

Run each fuzzer using dummy.cc as a fake input, to make sure it runs
at all. In the future we should instead unpack the corpus for each
fuzzer and use that instead.

  $ for fuzzer in `ls *_fuzzer | sort` ; do
  >   echo run $fuzzer...
  >   ./$fuzzer dummy.cc > /dev/null 2>&1 
  > done
  run bdiff_fuzzer...
  run dirs_fuzzer...
  run dirstate_fuzzer...
  run fm1readmarkers_fuzzer...
  run fncache_fuzzer...
  run jsonescapeu8fast_fuzzer...
  run manifest_fuzzer...
  run mpatch_fuzzer...
  run revlog_fuzzer...
  run xdiff_fuzzer...

Clean up.
  $ cd $TESTDIR/../contrib/fuzz
  $ $MAKE -s clean

#require emacs
  $ emacs -q -no-site-file -batch -l $TESTDIR/../contrib/hg-test-mode.el \
  >  -f ert-run-tests-batch-and-exit
  Running 1 tests (*) (glob)
     passed  1/1  hg-test-mode--compilation-mode-support
  
  Ran 1 tests, 1 results as expected (*) (glob)
  

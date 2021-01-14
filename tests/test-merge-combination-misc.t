Testing recorded "modified" files for merge commit
==================================================

This file shows what hg says are "modified" files for a merge commit
(hg log -T {files}), somewhat exhaustively.

This file test multiple corner case.

For merges that involve files contents changing, check test-merge-combination-file-content.t

For merges that involve executable bit changing, check test-merge-combination-exec-bytes.t


Case with multiple or zero merge ancestors, copies/renames, and identical file contents
with different filelog revisions are not currently covered.

  $ . $TESTDIR/testlib/merge-combination-util.sh

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

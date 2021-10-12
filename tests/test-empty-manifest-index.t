Create a repo such that the changelog entry refers to a null manifest node:

  $ hg init a
  $ cd a
  $ hg log
  $ touch x
  $ hg add x
  $ hg commit -m "init"
  $ hg rm x
  $ hg commit -q --amend

  $ wc -c < .hg/store/00manifest.i
  0

Make sure that the manifest can be read (and is empty):

  $ hg --config rhg.on-unsupported=abort files -r .
  [1]

Test a null changelog rev, too:

  $ hg --config rhg.on-unsupported=abort files -r 0000000000000000000000000000000000000000
  [1]

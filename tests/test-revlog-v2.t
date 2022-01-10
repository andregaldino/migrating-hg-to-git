#require reporevlogstore

A repo with unknown revlogv2 requirement string cannot be opened

  $ hg init invalidreq
  $ cd invalidreq
  $ echo exp-revlogv2.unknown >> .hg/requires
  $ hg log
  abort: repository requires features unknown to this Mercurial: exp-revlogv2.unknown
  (see https://mercurial-scm.org/wiki/MissingRequirement for more information)
  [255]
  $ cd ..

Can create and open repo with revlog v2 requirement

  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > revlogv2 = enable-unstable-format-and-corrupt-my-data
  > EOF

  $ hg init new-repo
  $ cd new-repo
  $ hg debugrequires | grep revlogv2
  exp-revlogv2.2
  dirstate-v2 (dirstate-v2 !)

  $ hg log

Unknown flags to revlog are rejected

  >>> with open('.hg/store/00changelog.i', 'wb') as fh:
  ...     fh.write(b'\xff\x00\xde\xad') and None

  $ hg log
  abort: unknown flags (0xff00) in version 57005 revlog 00changelog
  [50]

  $ cd ..

Writing a simple revlog v2 works

  $ hg init simple
  $ cd simple
  $ touch foo
  $ hg -q commit -A -m initial

  $ hg log
  changeset:   0:96ee1d7354c4
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     initial
  

Header written as expected

  $ f --hexdump --bytes 4 .hg/store/00changelog.i
  .hg/store/00changelog.i:
  0000: 00 00 de ad                                     |....|

  $ f --hexdump --bytes 4 .hg/store/data/foo.i
  .hg/store/data/foo.i:
  0000: 00 00 de ad                                     |....|

Bundle use a compatible changegroup format
------------------------------------------

  $ hg bundle --all ../basic.hg
  1 changesets found
  $ hg debugbundle --spec ../basic.hg
  bzip2-v2

The expected files are generated
--------------------------------

We should have have:
- a docket
- a index file with a unique name
- a data file

  $ ls .hg/store/00changelog* .hg/store/00manifest*
  .hg/store/00changelog-1335303a.sda
  .hg/store/00changelog-6b8ab34b.idx
  .hg/store/00changelog-b875dfc5.dat
  .hg/store/00changelog.i
  .hg/store/00manifest-05a21d65.idx
  .hg/store/00manifest-43c37dde.dat
  .hg/store/00manifest-e2c9362a.sda
  .hg/store/00manifest.i

Local clone works
-----------------

  $ hg clone . ../cloned-repo
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg tip | tee ../tip-new
  changeset:   0:96ee1d7354c4
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     initial
  
  $ hg tip -R ../cloned-repo | tee ../tip-cloned
  changeset:   0:96ee1d7354c4
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     initial
  

The two repository should be identical, this diff MUST be empty

  $ cmp ../tip-new ../tip-cloned || diff -U8 ../tip-new ../tip-cloned


hg verify should be happy
-------------------------

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 1 changesets with 1 changes to 1 files

  $ hg verify -R ../cloned-repo
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 1 changesets with 1 changes to 1 files

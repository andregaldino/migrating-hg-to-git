test stripping of filelogs where the linkrev doesn't always increase

  $ echo '[extensions]' >> $HGRCPATH
  $ echo 'strip =' >> $HGRCPATH
  $ commit()
  > {
  >     hg up -qC null
  >     count=1
  >     for i in "$@"; do
  >         for f in $i; do
  >             mkdir -p `dirname $f`
  >             echo $count > $f
  >         done
  >         count=`expr $count + 1`
  >     done
  >     hg commit -qAm "$*"
  > }

2 1 0 2 0 1 2

  $ mkdir files
  $ cd files
  $ hg init orig
  $ cd orig
  $ commit '201 210'
  $ commit '102 120' '210'
  $ commit '021'
  $ commit '201' '021 120'
  $ commit '012 021' '102 201' '120 210'
  $ commit '102 120' '012 210' '021 201'
  $ commit '201 210' '021 120' '012 102'
  $ cd ..
  $ hg clone -q -U -r 4 -r 5 -r 6 orig crossed
  $ cd crossed

  $ for i in 012 021 102 120 201 210; do
  >     echo $i
  >     hg debugindex $i
  >     echo
  > done
  012
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       0 b8e02f643373 000000000000 000000000000
       1       1 5d9299349fc0 000000000000 000000000000
       2       2 2661d26c6496 000000000000 000000000000
  
  021
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       0 b8e02f643373 000000000000 000000000000
       1       2 5d9299349fc0 000000000000 000000000000
       2       1 2661d26c6496 000000000000 000000000000
  
  102
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       1 b8e02f643373 000000000000 000000000000
       1       0 5d9299349fc0 000000000000 000000000000
       2       2 2661d26c6496 000000000000 000000000000
  
  120
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       1 b8e02f643373 000000000000 000000000000
       1       2 5d9299349fc0 000000000000 000000000000
       2       0 2661d26c6496 000000000000 000000000000
  
  201
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       2 b8e02f643373 000000000000 000000000000
       1       0 5d9299349fc0 000000000000 000000000000
       2       1 2661d26c6496 000000000000 000000000000
  
  210
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       2 b8e02f643373 000000000000 000000000000
       1       1 5d9299349fc0 000000000000 000000000000
       2       0 2661d26c6496 000000000000 000000000000
  
  $ cd ..
  $ for i in 0 1 2; do
  >     hg clone -q -U --pull crossed $i
  >     echo "% Trying to strip revision $i"
  >     hg --cwd $i strip $i
  >     echo "% Verifying"
  >     hg --cwd $i verify
  >     echo
  > done
  % Trying to strip revision 0
  saved backup bundle to $TESTTMP/files/0/.hg/strip-backup/cbb8c2f0a2e3-239800b9-backup.hg
  % Verifying
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 2 changesets with 12 changes to 6 files
  
  % Trying to strip revision 1
  saved backup bundle to $TESTTMP/files/1/.hg/strip-backup/124ecc0cbec9-6104543f-backup.hg
  % Verifying
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 2 changesets with 12 changes to 6 files
  
  % Trying to strip revision 2
  saved backup bundle to $TESTTMP/files/2/.hg/strip-backup/f6439b304a1a-c6505a5f-backup.hg
  % Verifying
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 2 changesets with 12 changes to 6 files
  
  $ cd ..

Do a similar test where the manifest revlog has unordered linkrevs
  $ mkdir manifests
  $ cd manifests
  $ hg init orig
  $ cd orig
  $ commit 'file'
  $ commit 'other'
  $ commit '' 'other'
  $ HGUSER=another-user; export HGUSER
  $ commit 'file'
  $ commit 'other' 'file'
  $ cd ..
  $ hg clone -q -U -r 1 -r 2 -r 3 -r 4 orig crossed
  $ cd crossed
  $ hg debugindex --manifest
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       2 6bbc6fee55c2 000000000000 000000000000
       1       0 1c556153fe54 000000000000 000000000000
       2       1 1f76dba919fd 000000000000 000000000000
       3       3 bbee06ad59d5 000000000000 000000000000

  $ cd ..
  $ for i in 2 3; do
  >     hg clone -q -U --pull crossed $i
  >     echo "% Trying to strip revision $i"
  >     hg --cwd $i strip $i
  >     echo "% Verifying"
  >     hg --cwd $i verify
  >     echo
  > done
  % Trying to strip revision 2
  saved backup bundle to $TESTTMP/manifests/2/.hg/strip-backup/f3015ad03c03-4d98bdc2-backup.hg
  % Verifying
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 3 changes to 2 files
  
  % Trying to strip revision 3
  saved backup bundle to $TESTTMP/manifests/3/.hg/strip-backup/9632aa303aa4-69192e3f-backup.hg
  % Verifying
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 3 changes to 2 files
  
  $ cd ..

Now a similar test for a non-root manifest revlog
  $ cat >> $HGRCPATH <<EOF
  > [experimental]
  > treemanifests = yes
  > EOF
  $ mkdir treemanifests
  $ cd treemanifests
  $ 
  $ hg --config experimental.treemanifest=True init orig
  $ cd orig
  $ commit 'dir/file'
  $ commit 'dir/other'
  $ commit '' 'dir/other'
  $ HGUSER=yet-another-user; export HGUSER
  $ commit 'otherdir dir/file'
  $ commit 'otherdir dir/other' 'otherdir dir/file'
  $ cd ..
  $ hg --config experimental.treemanifest=True clone -q -U -r 1 -r 2 -r 3 -r 4 orig crossed
  $ cd crossed
  $ hg debugindex --dir dir
     rev linkrev       nodeid    p1-nodeid    p2-nodeid
       0       2 6bbc6fee55c2 000000000000 000000000000
       1       0 1c556153fe54 000000000000 000000000000
       2       1 1f76dba919fd 000000000000 000000000000
       3       3 bbee06ad59d5 000000000000 000000000000

  $ cd ..
  $ for i in 2 3; do
  >     hg --config experimental.treemanifest=True clone -q -U --pull crossed $i
  >     echo "% Trying to strip revision $i"
  >     hg --cwd $i strip $i
  >     echo "% Verifying"
  >     hg --cwd $i verify
  >     echo
  > done
  % Trying to strip revision 2
  saved backup bundle to $TESTTMP/treemanifests/2/.hg/strip-backup/145f5c75f9ac-a105cfbe-backup.hg
  % Verifying
  checking changesets
  checking manifests
  checking directory manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 4 changes to 3 files
  
  % Trying to strip revision 3
  saved backup bundle to $TESTTMP/treemanifests/3/.hg/strip-backup/e4e3de5c3cb2-f4c70376-backup.hg
  % Verifying
  checking changesets
  checking manifests
  checking directory manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 4 changes to 3 files
  
  $ cd ..

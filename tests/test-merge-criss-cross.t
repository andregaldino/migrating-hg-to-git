#testcases old newfilenode

#if newfilenode
Enable the config option
------------------------

  $ cat >> $HGRCPATH <<EOF
  > [experimental]
  > merge-track-salvaged = True
  > EOF
#endif

Criss cross merging

  $ hg init criss-cross
  $ cd criss-cross
  $ echo '0 base' > f1
  $ echo '0 base' > f2
  $ hg ci -Aqm '0 base'

  $ echo '1 first change' > f1
  $ hg ci -m '1 first change f1'

  $ hg up -qr0
  $ echo '2 first change' > f2
  $ hg ci -qm '2 first change f2'

  $ hg merge -qr 1
  $ hg ci -m '3 merge'

  $ hg up -qr2
  $ hg merge -qr1
  $ hg ci -qm '4 merge'

  $ echo '5 second change' > f1
  $ hg ci -m '5 second change f1'

  $ hg up -r3
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo '6 second change' > f2
  $ hg ci -m '6 second change f2'

  $ hg log -G
  @  changeset:   6:3b08d01b0ab5
  |  tag:         tip
  |  parent:      3:cf89f02107e5
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     6 second change f2
  |
  | o  changeset:   5:adfe50279922
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     5 second change f1
  | |
  | o    changeset:   4:7d3e55501ae6
  | |\   parent:      2:40663881a6dd
  | | |  parent:      1:0f6b37dbe527
  | | |  user:        test
  | | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | | |  summary:     4 merge
  | | |
  o---+  changeset:   3:cf89f02107e5
  | | |  parent:      2:40663881a6dd
  |/ /   parent:      1:0f6b37dbe527
  | |    user:        test
  | |    date:        Thu Jan 01 00:00:00 1970 +0000
  | |    summary:     3 merge
  | |
  | o  changeset:   2:40663881a6dd
  | |  parent:      0:40494bf2444c
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     2 first change f2
  | |
  o |  changeset:   1:0f6b37dbe527
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     1 first change f1
  |
  o  changeset:   0:40494bf2444c
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     0 base
  

  $ hg merge -v --debug --tool internal:dump 5 --config merge.preferancestor='!'
  note: using 0f6b37dbe527 as ancestor of 3b08d01b0ab5 and adfe50279922
        alternatively, use --config merge.preferancestor=40663881a6dd
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 0f6b37dbe527, local: 3b08d01b0ab5+, remote: adfe50279922
   f1: remote is newer -> g
  getting f1
   preserving f2 for resolve of f2
   f2: versions differ -> m
  picked tool ':dump' for f2 (binary False symlink False changedelete False)
  merging f2
  my f2@3b08d01b0ab5+ other f2@adfe50279922 ancestor f2@0f6b37dbe527
  1 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]

  $ f --dump *
  f1:
  >>>
  5 second change
  <<<
  f2:
  >>>
  6 second change
  <<<
  f2.base:
  >>>
  0 base
  <<<
  f2.local:
  >>>
  6 second change
  <<<
  f2.orig:
  >>>
  6 second change
  <<<
  f2.other:
  >>>
  2 first change
  <<<

  $ hg up -qC .
  $ hg merge -v --tool internal:dump 5 --config merge.preferancestor="null 40663881 3b08d"
  note: using 40663881a6dd as ancestor of 3b08d01b0ab5 and adfe50279922
        alternatively, use --config merge.preferancestor=0f6b37dbe527
  resolving manifests
  merging f1
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]

Redo merge with merge.preferancestor="*" to enable bid merge

  $ rm f*
  $ hg up -qC .
  $ hg merge -v --debug --tool internal:dump 5 --config merge.preferancestor="*"
  note: merging 3b08d01b0ab5+ and adfe50279922 using bids from ancestors 0f6b37dbe527 and 40663881a6dd
  
  calculating bids for ancestor 0f6b37dbe527
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 0f6b37dbe527, local: 3b08d01b0ab5+, remote: adfe50279922
   f1: remote is newer -> g
   f2: versions differ -> m
  
  calculating bids for ancestor 40663881a6dd
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 40663881a6dd, local: 3b08d01b0ab5+, remote: adfe50279922
   f1: versions differ -> m
   f2: remote unchanged -> k
  
  auction for merging merge bids (2 ancestors)
   list of bids for f1:
     remote is newer -> g
     versions differ -> m
   f1: picking 'get' action
   list of bids for f2:
     remote unchanged -> k
     versions differ -> m
   f2: picking 'keep' action
  end of auction
  
   f1: remote is newer -> g
  getting f1
   f2: remote unchanged -> k
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ f --dump *
  f1:
  >>>
  5 second change
  <<<
  f2:
  >>>
  6 second change
  <<<


The other way around:

  $ hg up -C -r5
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge -v --debug --config merge.preferancestor="*"
  note: merging adfe50279922+ and 3b08d01b0ab5 using bids from ancestors 0f6b37dbe527 and 40663881a6dd
  
  calculating bids for ancestor 0f6b37dbe527
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 0f6b37dbe527, local: adfe50279922+, remote: 3b08d01b0ab5
   f1: remote unchanged -> k
   f2: versions differ -> m
  
  calculating bids for ancestor 40663881a6dd
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 40663881a6dd, local: adfe50279922+, remote: 3b08d01b0ab5
   f1: versions differ -> m
   f2: remote is newer -> g
  
  auction for merging merge bids (2 ancestors)
   list of bids for f1:
     remote unchanged -> k
     versions differ -> m
   f1: picking 'keep' action
   list of bids for f2:
     remote is newer -> g
     versions differ -> m
   f2: picking 'get' action
  end of auction
  
   f2: remote is newer -> g
  getting f2
   f1: remote unchanged -> k
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ f --dump *
  f1:
  >>>
  5 second change
  <<<
  f2:
  >>>
  6 second change
  <<<

Verify how the output looks and and how verbose it is:

  $ hg up -qC
  $ hg merge
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg up -qC tip
  $ hg merge -v
  note: merging 3b08d01b0ab5+ and adfe50279922 using bids from ancestors 0f6b37dbe527 and 40663881a6dd
  
  calculating bids for ancestor 0f6b37dbe527
  resolving manifests
  
  calculating bids for ancestor 40663881a6dd
  resolving manifests
  
  auction for merging merge bids (2 ancestors)
   f1: picking 'get' action
   f2: picking 'keep' action
  end of auction
  
  getting f1
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg up -qC
  $ hg merge -v --debug --config merge.preferancestor="*"
  note: merging 3b08d01b0ab5+ and adfe50279922 using bids from ancestors 0f6b37dbe527 and 40663881a6dd
  
  calculating bids for ancestor 0f6b37dbe527
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 0f6b37dbe527, local: 3b08d01b0ab5+, remote: adfe50279922
   f1: remote is newer -> g
   f2: versions differ -> m
  
  calculating bids for ancestor 40663881a6dd
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 40663881a6dd, local: 3b08d01b0ab5+, remote: adfe50279922
   f1: versions differ -> m
   f2: remote unchanged -> k
  
  auction for merging merge bids (2 ancestors)
   list of bids for f1:
     remote is newer -> g
     versions differ -> m
   f1: picking 'get' action
   list of bids for f2:
     remote unchanged -> k
     versions differ -> m
   f2: picking 'keep' action
  end of auction
  
   f1: remote is newer -> g
  getting f1
   f2: remote unchanged -> k
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

Test the greatest common ancestor returning multiple changesets

  $ hg log -r 'heads(commonancestors(head()))'
  changeset:   1:0f6b37dbe527
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     1 first change f1
  
  changeset:   2:40663881a6dd
  parent:      0:40494bf2444c
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     2 first change f2
  

  $ cd ..

http://stackoverflow.com/questions/9350005/how-do-i-specify-a-merge-base-to-use-in-a-hg-merge/9430810

  $ hg init ancestor-merging
  $ cd ancestor-merging
  $ echo a > x
  $ hg commit -A -m a x
  $ hg update -q 0
  $ echo b >> x
  $ hg commit -m b
  $ hg update -q 0
  $ echo c >> x
  $ hg commit -qm c
  $ hg update -q 1
  $ hg merge -q --tool internal:local 2
  $ echo c >> x
  $ hg commit -m bc
  $ hg update -q 2
  $ hg merge -q --tool internal:local 1
  $ echo b >> x
  $ hg commit -qm cb

  $ hg merge --config merge.preferancestor='!'
  note: using 70008a2163f6 as ancestor of 0d355fdef312 and 4b8b546a3eef
        alternatively, use --config merge.preferancestor=b211bbc6eb3c
  merging x
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ cat x
  a
  c
  b
  c

  $ hg up -qC .

  $ hg merge --config merge.preferancestor=b211bbc6eb3c
  note: using b211bbc6eb3c as ancestor of 0d355fdef312 and 4b8b546a3eef
        alternatively, use --config merge.preferancestor=70008a2163f6
  merging x
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ cat x
  a
  b
  c
  b

  $ hg up -qC .

  $ hg merge -v --config merge.preferancestor="*"
  note: merging 0d355fdef312+ and 4b8b546a3eef using bids from ancestors 70008a2163f6 and b211bbc6eb3c
  
  calculating bids for ancestor 70008a2163f6
  resolving manifests
  
  calculating bids for ancestor b211bbc6eb3c
  resolving manifests
  
  auction for merging merge bids (2 ancestors)
   x: multiple bids for merge action:
    versions differ -> m
    versions differ -> m
   x: ambiguous merge - picked m action
  end of auction
  
  merging x
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ cat x
  a
  c
  b
  c

Verify that the old context ancestor works with / despite preferancestor:

  $ hg log -r 'ancestor(head())' --config merge.preferancestor=1 -T '{rev}\n'
  1
  $ hg log -r 'ancestor(head())' --config merge.preferancestor=2 -T '{rev}\n'
  2
  $ hg log -r 'ancestor(head())' --config merge.preferancestor=3 -T '{rev}\n'
  1
  $ hg log -r 'ancestor(head())' --config merge.preferancestor='1337 * - 2' -T '{rev}\n'
  2

  $ cd ..

  $ hg init issue5020
  $ cd issue5020

  $ echo a > noop
  $ hg ci -qAm initial

  $ echo b > noop
  $ hg ci -qAm 'uninteresting change'

  $ hg up -q 0
  $ mkdir d1
  $ echo a > d1/a
  $ echo b > d1/b
  $ hg ci -qAm 'add d1/a and d1/b'

  $ hg merge -q 1
  $ hg rm d1/a
  $ hg mv -q d1 d2
  $ hg ci -qm 'merge while removing d1/a and moving d1/b to d2/b'

  $ hg up -q 1
  $ hg merge -q 2
  $ hg ci -qm 'merge (no changes while merging)'
  $ hg log -G -T '{rev}:{node|short} {desc}'
  @    4:c0ef19750a22 merge (no changes while merging)
  |\
  +---o  3:6ca01f7342b9 merge while removing d1/a and moving d1/b to d2/b
  | |/
  | o  2:154e6000f54e add d1/a and d1/b
  | |
  o |  1:11b5b303e36c uninteresting change
  |/
  o  0:7b54db1ebf33 initial
  
  $ hg merge 3 --debug
  note: merging c0ef19750a22+ and 6ca01f7342b9 using bids from ancestors 11b5b303e36c and 154e6000f54e
  
  calculating bids for ancestor 11b5b303e36c
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 11b5b303e36c, local: c0ef19750a22+, remote: 6ca01f7342b9
   d1/a: ancestor missing, remote missing -> kn
   d1/b: ancestor missing, remote missing -> kn
   d2/b: remote created -> g
  
  calculating bids for ancestor 154e6000f54e
    unmatched files in other:
     d2/b
    all copies found (* = to merge, ! = divergent, % = renamed and deleted):
     on remote side:
      src: 'd1/b' -> dst: 'd2/b' 
    checking for directory renames
     discovered dir src: 'd1/' -> dst: 'd2/'
  resolving manifests
   branchmerge: True, force: False, partial: False
   ancestor: 154e6000f54e, local: c0ef19750a22+, remote: 6ca01f7342b9
   d1/a: other deleted -> r
   d1/b: other deleted -> r
   d2/b: remote created -> g
  
  auction for merging merge bids (2 ancestors)
   list of bids for d1/a:
     ancestor missing, remote missing -> kn
     other deleted -> r
   d1/a: picking 'keep new' action
   list of bids for d1/b:
     ancestor missing, remote missing -> kn
     other deleted -> r
   d1/b: picking 'keep new' action
   list of bids for d2/b:
     remote created -> g
     remote created -> g
   d2/b: consensus for g
  end of auction
  
   d2/b: remote created -> g
  getting d2/b
   d1/a: ancestor missing, remote missing -> kn
   d1/b: ancestor missing, remote missing -> kn
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)


Check that removal reversion does not go unotified
==================================================

On a merge, a file can be removed and user can revert that removal. This means
user has made an explicit choice of keeping the file or reverting the removal
even though the merge algo wanted to remove it.
Based on this, when we do criss cross merges, merge algorithm should not again
choose to remove the file as in one of the merges, user made an explicit choice
to revert the removal.
Following test cases demonstrate how merge algo does not take in account
explicit choices made by users to revert the removal and on criss-cross merging
removes the file again.

"Simple" case where the filenode changes
----------------------------------------

  $ cd ..
  $ hg init criss-cross-merge-reversal-with-update
  $ cd criss-cross-merge-reversal-with-update
  $ echo the-file > the-file
  $ echo other-file > other-file
  $ hg add the-file other-file
  $ hg ci -m 'root-commit'
  $ echo foo >> the-file
  $ echo bar >> other-file
  $ hg ci -m 'updating-both-file'
  $ hg up 'desc("root-commit")'
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg rm the-file
  $ hg ci -m 'delete-the-file'
  created new head
  $ hg log -G -T '{node|short} {desc}\n'
  @  7801bc9b9899 delete-the-file
  |
  | o  9b610631ab29 updating-both-file
  |/
  o  955800955977 root-commit
  

Do all the merge combination (from the deleted or the update side × keeping and deleting the file

  $ hg update 'desc("delete-the-file")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("updating-both-file")' -t :local
  1 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg debugmergestate
  local (working copy): 7801bc9b9899de5e304bd162cafde9b78e10ab9b
  other (merge rev): 9b610631ab29024c5f44af7d2c19658ef8f8f071
  file: the-file (state "r")
    local path: the-file (hash 0000000000000000000000000000000000000000, flags "")
    ancestor path: the-file (node 4b69178b9bdae28b651393b46e631427a72f217a)
    other path: the-file (node 59e363a07dc876278f0e41756236f30213b6b460)
    extra: ancestorlinknode = 955800955977bd6c103836ee3e437276e940a589
    extra: merge-removal-candidate = yes
    extra: merged = yes
  extra: other-file (filenode-source = other)
  $ hg ci -m "merge-deleting-the-file-from-deleted"
  $ hg manifest
  other-file
  $ hg debugrevlogindex the-file
     rev linkrev nodeid       p1           p2
       0       0 4b69178b9bda 000000000000 000000000000
       1       1 59e363a07dc8 4b69178b9bda 000000000000

  $ hg update 'desc("updating-both-file")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("delete-the-file")' -t :other
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg debugmergestate
  local (working copy): 9b610631ab29024c5f44af7d2c19658ef8f8f071
  other (merge rev): 7801bc9b9899de5e304bd162cafde9b78e10ab9b
  file: the-file (state "r")
    local path: the-file (hash 6d2e02da5a9fe0691363dc6b573845fa271eaa35, flags "")
    ancestor path: the-file (node 4b69178b9bdae28b651393b46e631427a72f217a)
    other path: the-file (node 0000000000000000000000000000000000000000)
    extra: ancestorlinknode = 955800955977bd6c103836ee3e437276e940a589
    extra: merge-removal-candidate = yes
    extra: merged = yes
  $ hg ci -m "merge-deleting-the-file-from-updated"
  created new head
  $ hg manifest
  other-file
  $ hg debugrevlogindex the-file
     rev linkrev nodeid       p1           p2
       0       0 4b69178b9bda 000000000000 000000000000
       1       1 59e363a07dc8 4b69178b9bda 000000000000

  $ hg update 'desc("delete-the-file")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 'desc("updating-both-file")' -t :other
  1 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg debugmergestate
  local (working copy): 7801bc9b9899de5e304bd162cafde9b78e10ab9b
  other (merge rev): 9b610631ab29024c5f44af7d2c19658ef8f8f071
  file: the-file (state "r")
    local path: the-file (hash 0000000000000000000000000000000000000000, flags "")
    ancestor path: the-file (node 4b69178b9bdae28b651393b46e631427a72f217a)
    other path: the-file (node 59e363a07dc876278f0e41756236f30213b6b460)
    extra: ancestorlinknode = 955800955977bd6c103836ee3e437276e940a589
    extra: merge-removal-candidate = yes
    extra: merged = yes
  extra: other-file (filenode-source = other)
  $ hg ci -m "merge-keeping-the-file-from-deleted"
  created new head
  $ hg manifest
  other-file
  the-file

  $ hg debugrevlogindex the-file
     rev linkrev nodeid       p1           p2
       0       0 4b69178b9bda 000000000000 000000000000
       1       1 59e363a07dc8 4b69178b9bda 000000000000
       2       5 885af55420b3 59e363a07dc8 000000000000 (newfilenode !)

  $ hg update 'desc("updating-both-file")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (newfilenode !)
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved (old !)
  $ hg merge 'desc("delete-the-file")' -t :local
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg debugmergestate
  local (working copy): 9b610631ab29024c5f44af7d2c19658ef8f8f071
  other (merge rev): 7801bc9b9899de5e304bd162cafde9b78e10ab9b
  file: the-file (state "r")
    local path: the-file (hash 6d2e02da5a9fe0691363dc6b573845fa271eaa35, flags "")
    ancestor path: the-file (node 4b69178b9bdae28b651393b46e631427a72f217a)
    other path: the-file (node 0000000000000000000000000000000000000000)
    extra: ancestorlinknode = 955800955977bd6c103836ee3e437276e940a589
    extra: merge-removal-candidate = yes
    extra: merged = yes
  $ hg ci -m "merge-keeping-the-file-from-updated"
  created new head
  $ hg manifest
  other-file
  the-file

XXX: This should create a new filenode because user explicitly decided to keep
the file. If we reuse the same filenode, future merges (criss-cross ones mostly)
will think that file remain unchanged and user explicit choice will not be taken
in consideration.
  $ hg debugrevlogindex the-file
     rev linkrev nodeid       p1           p2
       0       0 4b69178b9bda 000000000000 000000000000
       1       1 59e363a07dc8 4b69178b9bda 000000000000
       2       5 885af55420b3 59e363a07dc8 000000000000 (newfilenode !)

  $ hg log -G -T '{node|short} {desc}\n'
  @    5e3eccec60d8 merge-keeping-the-file-from-updated
  |\
  +---o  38a4c3e7cac8 merge-keeping-the-file-from-deleted (newfilenode !)
  +---o  e9b708131723 merge-keeping-the-file-from-deleted (old !)
  | |/
  +---o  a4e0e44229dc merge-deleting-the-file-from-updated
  | |/
  +---o  adfd88e5d7d3 merge-deleting-the-file-from-deleted
  | |/
  | o  7801bc9b9899 delete-the-file
  | |
  o |  9b610631ab29 updating-both-file
  |/
  o  955800955977 root-commit
  

There the resulting merge together (leading to criss cross situation). Check
the conflict is properly detected.

(merging two deletion together → no conflict)

  $ hg update --clean 'desc("merge-deleting-the-file-from-deleted")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg merge          'desc("merge-deleting-the-file-from-updated")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ ls -1
  other-file
  $ hg debugmergestate
  no merge state found

(merging a deletion with keeping → conflict)

  $ hg update --clean 'desc("merge-deleting-the-file-from-deleted")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

#if newfilenode
  $ hg merge          'desc("merge-keeping-the-file-from-deleted")'
  file 'the-file' was deleted in local [working copy] but was modified in other [merge rev].
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved (old !)
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
#else
  $ hg merge          'desc("merge-keeping-the-file-from-deleted")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
#endif
  $ ls -1
  other-file
  the-file (newfilenode !)

#if newfilenode
  $ hg debugmergestate
  local (working copy): adfd88e5d7d3d3e22bdd26512991ee64d59c1d8f
  other (merge rev): 38a4c3e7cac8c294ecb0a7a85a05464e9836ca78
  file: the-file (state "u")
    local path: the-file (hash 0000000000000000000000000000000000000000, flags "")
    ancestor path: the-file (node 59e363a07dc876278f0e41756236f30213b6b460)
    other path: the-file (node 885af55420b35d7bf3bbd6f546615295bfe6544a)
    extra: ancestorlinknode = 9b610631ab29024c5f44af7d2c19658ef8f8f071
    extra: merge-removal-candidate = yes
    extra: merged = yes
#else
  $ hg debugmergestate
  local (working copy): adfd88e5d7d3d3e22bdd26512991ee64d59c1d8f
  other (merge rev): e9b7081317232edce73f7ad5ae0b7807ff5c326a
  extra: the-file (merge-removal-candidate = yes)
#endif

(merging a deletion with keeping → conflict)
BROKEN: this should result in conflict

  $ hg update --clean 'desc("merge-deleting-the-file-from-deleted")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (newfilenode !)
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved (old !)
  $ hg merge          'desc("merge-keeping-the-file-from-updated")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ ls -1
  other-file
  $ hg debugmergestate
  local (working copy): adfd88e5d7d3d3e22bdd26512991ee64d59c1d8f
  other (merge rev): 5e3eccec60d88f94a7ba57c351f32cb24c15fe0c
  extra: the-file (merge-removal-candidate = yes)

(merging two deletion together → no conflict)

  $ hg update --clean 'desc("merge-deleting-the-file-from-updated")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge          'desc("merge-deleting-the-file-from-deleted")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ ls -1
  other-file
  $ hg debugmergestate
  no merge state found

(merging a deletion with keeping → conflict)

  $ hg update --clean 'desc("merge-deleting-the-file-from-updated")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

#if newfilenode
  $ hg merge          'desc("merge-keeping-the-file-from-deleted")'
  file 'the-file' was deleted in local [working copy] but was modified in other [merge rev].
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved (old !)
  You can use (c)hanged version, leave (d)eleted, or leave (u)nresolved.
  What do you want to do? u
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
#else
  $ hg merge          'desc("merge-keeping-the-file-from-deleted")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
#endif

  $ ls -1
  other-file
  the-file (newfilenode !)
#if newfilenode
  $ hg debugmergestate
  local (working copy): a4e0e44229dc130be2915b92c957c093f8c7ee3e
  other (merge rev): 38a4c3e7cac8c294ecb0a7a85a05464e9836ca78
  file: the-file (state "u")
    local path: the-file (hash 0000000000000000000000000000000000000000, flags "")
    ancestor path: the-file (node 59e363a07dc876278f0e41756236f30213b6b460)
    other path: the-file (node 885af55420b35d7bf3bbd6f546615295bfe6544a)
    extra: ancestorlinknode = 9b610631ab29024c5f44af7d2c19658ef8f8f071
    extra: merge-removal-candidate = yes
    extra: merged = yes
#else
  $ hg debugmergestate
  local (working copy): a4e0e44229dc130be2915b92c957c093f8c7ee3e
  other (merge rev): e9b7081317232edce73f7ad5ae0b7807ff5c326a
  extra: the-file (merge-removal-candidate = yes)
#endif

(merging a deletion with keeping → conflict)
BROKEN: this should result in conflict

  $ hg update --clean 'desc("merge-deleting-the-file-from-updated")'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved (newfilenode !)
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved (old !)
  $ hg merge          'desc("merge-keeping-the-file-from-updated")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ ls -1
  other-file
  $ hg debugmergestate
  local (working copy): a4e0e44229dc130be2915b92c957c093f8c7ee3e
  other (merge rev): 5e3eccec60d88f94a7ba57c351f32cb24c15fe0c
  extra: the-file (merge-removal-candidate = yes)

(merging two "keeping" together → no conflict)

  $ hg update --clean 'desc("merge-keeping-the-file-from-updated")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge          'desc("merge-keeping-the-file-from-deleted")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (newfilenode !)
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved (old !)
  (branch merge, don't forget to commit)
  $ ls -1
  other-file
  the-file
#if newfilenode
  $ hg debugmergestate
  local (working copy): 5e3eccec60d88f94a7ba57c351f32cb24c15fe0c
  other (merge rev): 38a4c3e7cac8c294ecb0a7a85a05464e9836ca78
  extra: the-file (filenode-source = other)
#else
  $ hg debugmergestate
  no merge state found
#endif

(merging a deletion with keeping → conflict)
BROKEN: this should result in conflict

  $ hg update --clean 'desc("merge-keeping-the-file-from-updated")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (newfilenode !)
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved (old !)
  $ hg merge          'desc("merge-deleting-the-file-from-deleted")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ ls -1
  other-file
  the-file
  $ hg debugmergestate
  local (working copy): 5e3eccec60d88f94a7ba57c351f32cb24c15fe0c
  other (merge rev): adfd88e5d7d3d3e22bdd26512991ee64d59c1d8f
  extra: the-file (merge-removal-candidate = yes)

(merging a deletion with keeping → conflict)
BROKEN: this should result in conflict

  $ hg update --clean 'desc("merge-keeping-the-file-from-updated")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge          'desc("merge-deleting-the-file-from-updated")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ ls -1
  other-file
  the-file
  $ hg debugmergestate
  local (working copy): 5e3eccec60d88f94a7ba57c351f32cb24c15fe0c
  other (merge rev): a4e0e44229dc130be2915b92c957c093f8c7ee3e
  extra: the-file (merge-removal-candidate = yes)

(merging two "keeping" together → no conflict)

  $ hg update --clean 'desc("merge-keeping-the-file-from-deleted")'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved (newfilenode !)
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved (old !)
  $ hg merge          'desc("merge-keeping-the-file-from-updated")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ ls -1
  other-file
  the-file
  $ hg debugmergestate
  no merge state found

(merging a deletion with keeping → conflict)

  $ hg update --clean 'desc("merge-keeping-the-file-from-deleted")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
#if newfilenode
  $ hg merge          'desc("merge-deleting-the-file-from-deleted")'
  file 'the-file' was deleted in other [merge rev] but was modified in local [working copy].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
#else
  $ hg merge          'desc("merge-deleting-the-file-from-deleted")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
#endif
  $ ls -1
  other-file
  the-file

#if newfilenode
  $ hg debugmergestate
  local (working copy): 38a4c3e7cac8c294ecb0a7a85a05464e9836ca78 (newfilenode !)
  local (working copy): e9b7081317232edce73f7ad5ae0b7807ff5c326a (old !)
  other (merge rev): adfd88e5d7d3d3e22bdd26512991ee64d59c1d8f
  file: the-file (state "u")
    local path: the-file (hash 6d2e02da5a9fe0691363dc6b573845fa271eaa35, flags "")
    ancestor path: the-file (node 59e363a07dc876278f0e41756236f30213b6b460)
    other path: the-file (node 0000000000000000000000000000000000000000)
    extra: ancestorlinknode = 9b610631ab29024c5f44af7d2c19658ef8f8f071
    extra: merge-removal-candidate = yes
    extra: merged = yes
#else
  $ hg debugmergestate
  local (working copy): e9b7081317232edce73f7ad5ae0b7807ff5c326a
  other (merge rev): adfd88e5d7d3d3e22bdd26512991ee64d59c1d8f
  extra: the-file (merge-removal-candidate = yes)
#endif

(merging a deletion with keeping → conflict)

  $ hg update --clean 'desc("merge-keeping-the-file-from-deleted")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
#if newfilenode
  $ hg merge          'desc("merge-deleting-the-file-from-updated")'
  file 'the-file' was deleted in other [merge rev] but was modified in local [working copy].
  You can use (c)hanged version, (d)elete, or leave (u)nresolved.
  What do you want to do? u
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
#else
  $ hg merge          'desc("merge-deleting-the-file-from-updated")'
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
#endif
  $ ls -1
  other-file
  the-file
#if newfilenode
  $ hg debugmergestate
  local (working copy): 38a4c3e7cac8c294ecb0a7a85a05464e9836ca78
  other (merge rev): a4e0e44229dc130be2915b92c957c093f8c7ee3e
  file: the-file (state "u")
    local path: the-file (hash 6d2e02da5a9fe0691363dc6b573845fa271eaa35, flags "")
    ancestor path: the-file (node 59e363a07dc876278f0e41756236f30213b6b460)
    other path: the-file (node 0000000000000000000000000000000000000000)
    extra: ancestorlinknode = 9b610631ab29024c5f44af7d2c19658ef8f8f071
    extra: merge-removal-candidate = yes
    extra: merged = yes
#else
  $ hg debugmergestate
  local (working copy): e9b7081317232edce73f7ad5ae0b7807ff5c326a
  other (merge rev): a4e0e44229dc130be2915b92c957c093f8c7ee3e
  extra: the-file (merge-removal-candidate = yes)
#endif

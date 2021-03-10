====================================================
Test push/pull from multiple source at the same time
====================================================


Setup
=====

main repository
---------------

  $ . $RUNTESTDIR/testlib/common.sh
  $ hg init main-repo
  $ cd main-repo
  $ mkcommit A
  $ mkcommit B
  $ mkcommit C
  $ mkcommit D
  $ mkcommit E
  $ hg up 'desc(B)'
  0 files updated, 0 files merged, 3 files removed, 0 files unresolved
  $ mkcommit F
  created new head
  $ mkcommit G
  $ hg up 'desc(C)'
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ mkcommit H
  created new head
  $ hg up null --quiet
  $ hg log -T '{desc} {rev}\n' --rev 'sort(all(), "topo")' -G
  o  H 7
  |
  | o  E 4
  | |
  | o  D 3
  |/
  o  C 2
  |
  | o  G 6
  | |
  | o  F 5
  |/
  o  B 1
  |
  o  A 0
  
  $ cd ..

Various other repositories
--------------------------

  $ hg clone main-repo branch-E --rev 4 -U
  adding changesets
  adding manifests
  adding file changes
  added 5 changesets with 5 changes to 5 files
  new changesets 4a2df7238c3b:a603bfb5a83e
  $ hg clone main-repo branch-G --rev 6 -U
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 4 changes to 4 files
  new changesets 4a2df7238c3b:c521a06b234b
  $ hg clone main-repo branch-H --rev 7 -U
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 4 changes to 4 files
  new changesets 4a2df7238c3b:40faebb2ec45

Test simple bare operation
==========================

  $ hg clone main-repo test-repo-bare --rev 0 -U
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 4a2df7238c3b

  $ hg pull -R test-repo-bare ./branch-E ./branch-G ./branch-H
  pulling from ./branch-E
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 4 changes to 4 files
  new changesets 27547f69f254:a603bfb5a83e
  (run 'hg update' to get a working copy)
  pulling from ./branch-G
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files (+1 heads)
  new changesets 2f3a4c5c1417:c521a06b234b
  (run 'hg heads' to see heads, 'hg merge' to merge)
  pulling from ./branch-H
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)
  new changesets 40faebb2ec45
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ hg log -R test-repo-bare -T '{desc} {rev}\n' --rev 'sort(all(), "topo")' -G
  o  H 7
  |
  | o  E 4
  | |
  | o  D 3
  |/
  o  C 2
  |
  | o  G 6
  | |
  | o  F 5
  |/
  o  B 1
  |
  o  A 0
  

Test operation with a target
============================

  $ hg clone main-repo test-repo-rev --rev 0 -U
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 4a2df7238c3b

pulling an explicite revision

  $ node_b=`hg log -R main-repo --rev 'desc(B)' -T '{node}'`
  $ hg pull -R test-repo-rev ./branch-E ./branch-G ./branch-H --rev $node_b
  pulling from ./branch-E
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 27547f69f254
  (run 'hg update' to get a working copy)
  pulling from ./branch-G
  no changes found
  pulling from ./branch-H
  no changes found
  $ hg log -R test-repo-rev -T '{desc} {rev}\n' --rev 'sort(all(), "topo")' -G
  o  B 1
  |
  o  A 0
  

pulling a branch head, the branch head resolve to different revision on the
different repositories.

  $ hg pull -R test-repo-rev ./branch-E ./branch-G ./branch-H --rev default
  pulling from ./branch-E
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 3 files
  new changesets f838bfaca5c7:a603bfb5a83e
  (run 'hg update' to get a working copy)
  pulling from ./branch-G
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files (+1 heads)
  new changesets 2f3a4c5c1417:c521a06b234b
  (run 'hg heads' to see heads, 'hg merge' to merge)
  pulling from ./branch-H
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)
  new changesets 40faebb2ec45
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ hg log -R test-repo-rev -T '{desc} {rev}\n' --rev 'sort(all(), "topo")' -G
  o  H 7
  |
  | o  E 4
  | |
  | o  D 3
  |/
  o  C 2
  |
  | o  G 6
  | |
  | o  F 5
  |/
  o  B 1
  |
  o  A 0
  


Test with --update
==================

update without conflicts
------------------------

  $ hg clone main-repo test-repo-update --rev 0
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 4a2df7238c3b
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

We update for each pull, so the first on get into a branch independant from the
other and stay there. This is the expected behavior.

  $ hg log -R test-repo-update -T '{desc} {rev}\n' --rev 'sort(all(), "topo")' -G
  @  A 0
  
  $ hg pull -R test-repo-update ./branch-E ./branch-G ./branch-H --update
  pulling from ./branch-E
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 4 changes to 4 files
  new changesets 27547f69f254:a603bfb5a83e
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved
  pulling from ./branch-G
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files (+1 heads)
  new changesets 2f3a4c5c1417:c521a06b234b
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  updated to "a603bfb5a83e: E"
  1 other heads for branch "default"
  pulling from ./branch-H
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)
  new changesets 40faebb2ec45
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  updated to "a603bfb5a83e: E"
  2 other heads for branch "default"
  $ hg log -R test-repo-update -T '{desc} {rev}\n' --rev 'sort(all(), "topo")' -G
  o  H 7
  |
  | @  E 4
  | |
  | o  D 3
  |/
  o  C 2
  |
  | o  G 6
  | |
  | o  F 5
  |/
  o  B 1
  |
  o  A 0
  

update with conflicts
---------------------

  $ hg clone main-repo test-repo-conflict --rev 0
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 4a2df7238c3b
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

The update has conflict and interrupt the pull.

  $ echo this-will-conflict > test-repo-conflict/D
  $ hg add -R test-repo-conflict test-repo-conflict/D
  $ hg log -R test-repo-conflict -T '{desc} {rev}\n' --rev 'sort(all(), "topo")' -G
  @  A 0
  
  $ hg pull -R test-repo-conflict ./branch-E ./branch-G ./branch-H --update
  pulling from ./branch-E
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 4 changes to 4 files
  new changesets 27547f69f254:a603bfb5a83e
  merging D
  warning: conflicts while merging D! (edit, then use 'hg resolve --mark')
  3 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges
  [1]
  $ hg -R test-repo-conflict resolve -l
  U D
  $ hg log -R test-repo-conflict -T '{desc} {rev}\n' --rev 'sort(all(), "topo")' -G
  @  E 4
  |
  o  D 3
  |
  o  C 2
  |
  o  B 1
  |
  %  A 0
  

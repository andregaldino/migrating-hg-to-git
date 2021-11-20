Test 'hg log' with a bookmark


Create the repository

  $ hg init Test-D8973
  $ cd Test-D8973
  $ echo "bar" > foo.txt
  $ hg add foo.txt
  $ hg commit -m "Add foo in 'default'"


Add a bookmark for topic X

  $ hg branch -f sebhtml
  marked working directory as branch sebhtml
  (branches are permanent and global, did you want a bookmark?)

  $ hg bookmark sebhtml/99991-topic-X
  $ hg up sebhtml/99991-topic-X
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ echo "X" > x.txt
  $ hg add x.txt
  $ hg commit -m "Add x.txt in 'sebhtml/99991-topic-X'"

  $ hg log -B sebhtml/99991-topic-X
  changeset:   1:29f39dea9bf9
  branch:      sebhtml
  bookmark:    sebhtml/99991-topic-X
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     Add x.txt in 'sebhtml/99991-topic-X'
  

Add a bookmark for topic Y

  $ hg update default
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (leaving bookmark sebhtml/99991-topic-X)

  $ echo "Y" > y.txt
  $ hg add y.txt
  $ hg branch -f sebhtml
  marked working directory as branch sebhtml
  $ hg bookmark sebhtml/99992-topic-Y
  $ hg up sebhtml/99992-topic-Y
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg commit -m "Add y.txt in 'sebhtml/99992-topic-Y'"
  created new head

  $ hg log -B sebhtml/99992-topic-Y
  changeset:   2:11df7969cf8d
  branch:      sebhtml
  bookmark:    sebhtml/99992-topic-Y
  tag:         tip
  parent:      0:eaea25376a59
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     Add y.txt in 'sebhtml/99992-topic-Y'
  

The log of topic Y does not interfere with the log of topic X

  $ hg log -B sebhtml/99991-topic-X
  changeset:   1:29f39dea9bf9
  branch:      sebhtml
  bookmark:    sebhtml/99991-topic-X
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     Add x.txt in 'sebhtml/99991-topic-X'
  

Merge topics Y and X in the default branch

  $ hg update default
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (leaving bookmark sebhtml/99992-topic-Y)

  $ hg bookmark
     sebhtml/99991-topic-X     1:29f39dea9bf9
     sebhtml/99992-topic-Y     2:11df7969cf8d

  $ hg merge sebhtml/99992-topic-Y
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg commit -m "Merge branch 'sebhtml/99992-topic-Y' into 'default'"

  $ hg update default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ hg merge sebhtml/99991-topic-X
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg commit -m "Merge branch 'sebhtml/99991-topic-X' into 'default'"


Check the log of topic X, topic Y, and default branch

  $ hg log -B sebhtml/99992-topic-Y

  $ hg log -B sebhtml/99991-topic-X

  $ hg log -b default
  changeset:   4:c26ba8c1e1cb
  tag:         tip
  parent:      3:2189f3fb90d6
  parent:      1:29f39dea9bf9
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     Merge branch 'sebhtml/99991-topic-X' into 'default'
  
  changeset:   3:2189f3fb90d6
  parent:      0:eaea25376a59
  parent:      2:11df7969cf8d
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     Merge branch 'sebhtml/99992-topic-Y' into 'default'
  
  changeset:   0:eaea25376a59
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     Add foo in 'default'
  

Set up multiple bookmarked heads:

  $ hg bookmark merged-head
  $ hg up 1
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (leaving bookmark merged-head)
  $ echo "Z" > z.txt
  $ hg ci -Am 'Add Z'
  adding z.txt
  $ hg bookmark topic-Z

  $ hg log -GT '{rev}: {branch}, {bookmarks}\n'
  @  5: sebhtml, topic-Z
  |
  | o  4: default, merged-head
  |/|
  | o    3: default,
  | |\
  | | o  2: sebhtml, sebhtml/99992-topic-Y
  | |/
  o |  1: sebhtml, sebhtml/99991-topic-X
  |/
  o  0: default,
  

Multiple revisions under bookmarked head:

  $ hg log -GT '{rev}: {branch}, {bookmarks}\n' -B merged-head
  o    4: default, merged-head
  |\
  | ~
  o    3: default,
  |\
  ~ ~

Follows multiple bookmarks:

  $ hg log -GT '{rev}: {branch}, {bookmarks}\n' -B merged-head -B topic-Z
  @  5: sebhtml, topic-Z
  |
  ~
  o    4: default, merged-head
  |\
  | ~
  o    3: default,
  |\
  ~ ~

Filter by bookmark and branch:

  $ hg log -GT '{rev}: {branch}, {bookmarks}\n' -B merged-head -B topic-Z -b default
  o    4: default, merged-head
  |\
  | ~
  o    3: default,
  |\
  ~ ~


Unknown bookmark:

  $ hg log -B unknown
  abort: bookmark 'unknown' does not exist
  [10]

Shouldn't accept string-matcher syntax:

  $ hg log -B 're:.*'
  abort: bookmark 're:.*' does not exist
  [10]

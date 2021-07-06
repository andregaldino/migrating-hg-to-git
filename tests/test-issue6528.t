===============================================================
Test non-regression on the corruption associated with issue6528
===============================================================

Setup
-----

  $ hg init base-repo
  $ cd base-repo

  $ cat <<EOF > a.txt
  > 1
  > 2
  > 3
  > 4
  > 5
  > 6
  > EOF

  $ hg add a.txt
  $ hg commit -m 'c_base_c - create a.txt'

Modify a.txt

  $ sed -e 's/1/foo/' a.txt > a.tmp; mv a.tmp a.txt
  $ hg commit -m 'c_modify_c - modify a.txt'

Modify and rename a.txt to b.txt

  $ hg up -r "desc('c_base_c')"
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ sed -e 's/6/bar/' a.txt > a.tmp; mv a.tmp a.txt
  $ hg mv a.txt b.txt
  $ hg commit -m 'c_rename_c - rename and modify a.txt to b.txt'
  created new head

Merge each branch

  $ hg merge -r "desc('c_modify_c')"
  merging b.txt and a.txt to b.txt
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg commit -m 'c_merge_c: commit merge'

  $ hg debugrevlogindex b.txt
     rev linkrev nodeid       p1           p2
       0       2 05b806ebe5ea 000000000000 000000000000
       1       3 a58b36ad6b65 000000000000 05b806ebe5ea

Check commit Graph

  $ hg log -G
  @    changeset:   3:a1cc2bdca0aa
  |\   tag:         tip
  | |  parent:      2:615c6ccefd15
  | |  parent:      1:373d507f4667
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     c_merge_c: commit merge
  | |
  | o  changeset:   2:615c6ccefd15
  | |  parent:      0:f5a5a568022f
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     c_rename_c - rename and modify a.txt to b.txt
  | |
  o |  changeset:   1:373d507f4667
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     c_modify_c - modify a.txt
  |
  o  changeset:   0:f5a5a568022f
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     c_base_c - create a.txt
  

  $ hg cat -r . b.txt
  foo
  2
  3
  4
  5
  bar
  $ cat b.txt
  foo
  2
  3
  4
  5
  bar
  $ cd ..


Check the lack of corruption
----------------------------

  $ hg clone --pull base-repo cloned
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 4 changes to 2 files
  new changesets f5a5a568022f:a1cc2bdca0aa
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd cloned
  $ hg up -r "desc('c_merge_c')"
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved


Status is buggy, even with debugrebuilddirstate

  $ hg cat -r . b.txt
  foo
  2
  3
  4
  5
  bar
  $ cat b.txt
  foo
  2
  3
  4
  5
  bar
  $ hg status
  $ hg debugrebuilddirstate
  $ hg status

the history was altered

in theory p1/p2 order does not matter but in practice p1 == nullid is used as a
marker that some metadata are present and should be fetched.

  $ hg debugrevlogindex b.txt
     rev linkrev nodeid       p1           p2
       0       2 05b806ebe5ea 000000000000 000000000000
       1       3 a58b36ad6b65 000000000000 05b806ebe5ea

Check commit Graph

  $ hg log -G
  @    changeset:   3:a1cc2bdca0aa
  |\   tag:         tip
  | |  parent:      2:615c6ccefd15
  | |  parent:      1:373d507f4667
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     c_merge_c: commit merge
  | |
  | o  changeset:   2:615c6ccefd15
  | |  parent:      0:f5a5a568022f
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     c_rename_c - rename and modify a.txt to b.txt
  | |
  o |  changeset:   1:373d507f4667
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     c_modify_c - modify a.txt
  |
  o  changeset:   0:f5a5a568022f
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     c_base_c - create a.txt
  

  $ cat <<EOF >> $HGRCPATH
  > [extensions]
  > hooklib =
  > 
  > [phases]
  > publish = False
  > EOF
  $ hg init a
  $ hg --cwd a debugbuilddag '.:parent.:childa*parent/childa<parent@otherbranch./childa'
  $ hg --cwd a log -G
  o    changeset:   4:a9fb040caedd
  |\   branch:      otherbranch
  | |  tag:         tip
  | |  parent:      3:af739dfc49b4
  | |  parent:      1:66f7d451a68b
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 00:00:04 1970 +0000
  | |  summary:     r4
  | |
  | o  changeset:   3:af739dfc49b4
  | |  branch:      otherbranch
  | |  parent:      0:1ea73414a91b
  | |  user:        debugbuilddag
  | |  date:        Thu Jan 01 00:00:03 1970 +0000
  | |  summary:     r3
  | |
  +---o  changeset:   2:a6b287721c3b
  | |/   parent:      0:1ea73414a91b
  | |    parent:      1:66f7d451a68b
  | |    user:        debugbuilddag
  | |    date:        Thu Jan 01 00:00:02 1970 +0000
  | |    summary:     r2
  | |
  o |  changeset:   1:66f7d451a68b
  |/   tag:         childa
  |    user:        debugbuilddag
  |    date:        Thu Jan 01 00:00:01 1970 +0000
  |    summary:     r1
  |
  o  changeset:   0:1ea73414a91b
     tag:         parent
     user:        debugbuilddag
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     r0
  
  $ hg init b
  $ cat <<EOF >> b/.hg/hgrc
  > [hooks]
  > pretxnchangegroup.reject_merge_commits = \
  >   python:hgext.hooklib.reject_merge_commits.hook
  > EOF
  $ hg --cwd b pull ../a -r a6b287721c3b
  pulling from ../a
  adding changesets
  adding manifests
  adding file changes
  error: pretxnchangegroup.reject_merge_commits hook failed: a6b287721c3b rejected as merge on the same branch. Please consider rebase.
  transaction abort!
  rollback completed
  abort: a6b287721c3b rejected as merge on the same branch. Please consider rebase.
  [255]
  $ hg --cwd b pull ../a -r 1ea73414a91b
  pulling from ../a
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b (1 drafts)
  (run 'hg update' to get a working copy)
  $ hg --cwd b pull ../a -r a9fb040caedd
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 0 changes to 0 files
  new changesets 66f7d451a68b:a9fb040caedd (3 drafts)
  (run 'hg update' to get a working copy)

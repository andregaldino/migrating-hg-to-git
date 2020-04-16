  $ cat <<EOF >> $HGRCPATH
  > [extensions]
  > hooklib =
  > 
  > [phases]
  > publish = False
  > EOF
  $ hg init a
  $ hg --cwd a debugbuilddag '.:parent.*parent'
  $ hg --cwd a log -G
  o  changeset:   2:fa942426a6fd
  |  tag:         tip
  |  parent:      0:1ea73414a91b
  |  user:        debugbuilddag
  |  date:        Thu Jan 01 00:00:02 1970 +0000
  |  summary:     r2
  |
  | o  changeset:   1:66f7d451a68b
  |/   user:        debugbuilddag
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
  > pretxnclose.reject_new_heads = \
  >   python:hgext.hooklib.reject_new_heads.hook
  > EOF
  $ hg --cwd b pull ../a
  pulling from ../a
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  error: pretxnclose.reject_new_heads hook failed: Changes on branch 'default' resulted in multiple heads
  transaction abort!
  rollback completed
  abort: Changes on branch 'default' resulted in multiple heads
  [255]
  $ hg --cwd b pull ../a -r 1ea73414a91b
  pulling from ../a
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b (1 drafts)
  (run 'hg update' to get a working copy)

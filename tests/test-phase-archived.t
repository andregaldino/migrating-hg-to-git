=========================================================
Test features and behaviors related to the archived phase
=========================================================

  $ cat << EOF >> $HGRCPATH
  > [format]
  > internal-phase=yes
  > [extensions]
  > strip=
  > [experimental]
  > EOF

  $ hg init repo
  $ cd repo
  $ echo  root > a
  $ hg add a
  $ hg ci -m 'root'

Test that bundle can unarchive a changeset
------------------------------------------

  $ echo foo >> a
  $ hg st
  M a
  $ hg ci -m 'unbundletesting'
  $ hg log -G
  @  changeset:   1:883aadbbf309
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     unbundletesting
  |
  o  changeset:   0:c1863a3840c6
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     root
  
  $ hg strip --soft --rev '.'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/883aadbbf309-efc55adc-backup.hg
  $ hg log -G
  @  changeset:   0:c1863a3840c6
     tag:         tip
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     root
  
  $ hg log -G --hidden
  o  changeset:   1:883aadbbf309
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     unbundletesting
  |
  @  changeset:   0:c1863a3840c6
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     root
  
  $ hg unbundle .hg/strip-backup/883aadbbf309-efc55adc-backup.hg
  adding changesets
  adding manifests
  adding file changes
  added 0 changesets with 0 changes to 1 files
  (run 'hg update' to get a working copy)
  $ hg log -G
  o  changeset:   1:883aadbbf309
  |  tag:         tip
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     unbundletesting
  |
  @  changeset:   0:c1863a3840c6
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     root
  

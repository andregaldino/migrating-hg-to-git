========================================================
Test the ability to access a hidden revision on a server
========================================================

#require serve

  $ . $TESTDIR/testlib/obsmarker-common.sh
  $ cat >> $HGRCPATH << EOF
  > [phases]
  > # public changeset are not obsolete
  > publish=false
  > [experimental]
  > evolution=all
  > [ui]
  > logtemplate='{rev}:{node|short} {desc} [{phase}]\n'
  > EOF

Setup a simple repository with some hidden revisions
----------------------------------------------------

Testing the `served.hidden` view

  $ hg init repo-with-hidden
  $ cd repo-with-hidden

  $ echo 0 > a
  $ hg ci -qAm "c_Public"
  $ hg phase --public
  $ echo 1 > a
  $ hg ci -m "c_Amend_Old"
  $ echo 2 > a
  $ hg ci -m "c_Amend_New" --amend
  $ hg up ".^"
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo 3 > a
  $ hg ci -m "c_Pruned"
  created new head
  $ hg debugobsolete --record-parents `getid 'desc("c_Pruned")'` -d '0 0'
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg up ".^"
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo 4 > a
  $ hg ci -m "c_Secret" --secret
  created new head
  $ echo 5 > a
  $ hg ci -m "c_Secret_Pruned" --secret
  $ hg debugobsolete --record-parents `getid 'desc("c_Secret_Pruned")'` -d '0 0'
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg up null
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved

  $ hg log -G -T '{rev}:{node|short} {desc} [{phase}]\n' --hidden
  x  5:8d28cbe335f3 c_Secret_Pruned [secret]
  |
  o  4:1c6afd79eb66 c_Secret [secret]
  |
  | x  3:5d1575e42c25 c_Pruned [draft]
  |/
  | o  2:c33affeb3f6b c_Amend_New [draft]
  |/
  | x  1:be215fbb8c50 c_Amend_Old [draft]
  |/
  o  0:5f354f46e585 c_Public [public]
  
  $ hg debugobsolete
  be215fbb8c5090028b00154c1fe877ad1b376c61 c33affeb3f6b4e9621d1839d6175ddc07708807c 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '9', 'operation': 'amend', 'user': 'test'}
  5d1575e42c25b7f2db75cd4e0b881b1c35158fae 0 {5f354f46e5853535841ec7a128423e991ca4d59b} (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  8d28cbe335f311bc89332d7bbe8a07889b6914a0 0 {1c6afd79eb6663275bbe30097e162b1c24ced0f0} (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

  $ cd ..

Test the feature
================

Check cache pre-warm
--------------------

  $ ls -1 repo-with-hidden/.hg/cache
  branch2
  branch2-base
  branch2-served
  branch2-served.hidden
  branch2-visible
  rbc-names-v1
  rbc-revs-v1
  tags2
  tags2-visible

Check that the `served.hidden` repoview
---------------------------------------

  $ hg -R repo-with-hidden serve -p $HGPORT -d --pid-file hg.pid --config web.view=served.hidden
  $ cat hg.pid >> $DAEMON_PIDS

changesets in secret and higher phases are not visible through hgweb

  $ hg -R repo-with-hidden log --template "revision:    {rev}\\n" --rev "reverse(not secret())"
  revision:    2
  revision:    0
  $ hg -R repo-with-hidden log --template "revision:    {rev}\\n" --rev "reverse(not secret())" --hidden
  revision:    3
  revision:    2
  revision:    1
  revision:    0
  $ get-with-headers.py localhost:$HGPORT 'log?style=raw' | grep revision:
  revision:    3
  revision:    2
  revision:    1
  revision:    0

  $ killdaemons.py

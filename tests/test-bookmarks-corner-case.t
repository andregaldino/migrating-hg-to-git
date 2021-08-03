================================
Test corner case around bookmark
================================

This test file is meant to gather test around bookmark that are specific
 enough to not find a place elsewhere.

Test bookmark/changelog race condition
======================================

The data from the bookmark file are filtered to only contains bookmark with
node known to the changelog. If the cache invalidation between these two bits
goes wrong, bookmark can be dropped.

Setup
-----

initial repository setup

  $ hg init bookrace-server
  $ cd bookrace-server
  $ echo a > a
  $ hg add a
  $ hg commit -m root
  $ echo a >> a
  $ hg bookmark book-A
  $ hg commit -m A0
  $ hg up 'desc(root)'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (leaving bookmark book-A)
  $ echo b > b
  $ hg add b
  $ hg bookmark book-B
  $ hg commit -m B0
  created new head
  $ hg up null
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  (leaving bookmark book-B)
  $ hg phase --public --rev 'all()'
  $ hg log -G
  o  changeset:   2:c79985706978
  |  bookmark:    book-B
  |  tag:         tip
  |  parent:      0:6569b5a81c7e
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     B0
  |
  | o  changeset:   1:39c28d785860
  |/   bookmark:    book-A
  |    user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     A0
  |
  o  changeset:   0:6569b5a81c7e
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     root
  
  $ hg book
     book-A                    1:39c28d785860
     book-B                    2:c79985706978
  $ cd ..

Add new changeset on each bookmark in distinct clones

  $ hg clone ssh://user@dummy/bookrace-server client-A
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 2 files (+1 heads)
  new changesets 6569b5a81c7e:c79985706978
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R client-A update book-A
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (activating bookmark book-A)
  $ echo a >> client-A/a
  $ hg -R client-A commit -m A1
  $ hg clone ssh://user@dummy/bookrace-server client-B
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 3 changes to 2 files (+1 heads)
  new changesets 6569b5a81c7e:c79985706978
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R client-B update book-B
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (activating bookmark book-B)
  $ echo b >> client-B/b
  $ hg -R client-B commit -m B1

extension to reproduce the race
-------------------------------

If two process are pushing we want to make sure the following happens:

* process A read changelog
* process B to its full push
* process A read bookmarks
* process A proceed with rest of the push

We build a server side extension for this purpose

  $ cat > bookrace.py << EOF
  > import atexit
  > import os
  > import time
  > from mercurial import bookmarks, error, extensions
  > 
  > def wait(repo):
  >     if not os.path.exists('push-A-started'):
  >         assert repo._currentlock(repo._lockref) is None
  >         assert repo._currentlock(repo._wlockref) is None
  >         repo.ui.status(b'setting raced push up\n')
  >         with open('push-A-started', 'w'):
  >             pass
  >     clock = 300
  >     while not os.path.exists('push-B-done'):
  >         clock -= 1
  >         if clock <= 0:
  >             raise error.Abort("race scenario timed out")
  >         time.sleep(0.1)
  > 
  > def reposetup(ui, repo):
  >     class racedrepo(repo.__class__):
  >         @property
  >         def _bookmarks(self):
  >             wait(self)
  >             return super(racedrepo, self)._bookmarks
  >     repo.__class__ = racedrepo
  > 
  > def e():
  >     with open('push-A-done', 'w'):
  >         pass
  > atexit.register(e)
  > EOF

Actual test
-----------

Start the raced push.

  $ cat >> bookrace-server/.hg/hgrc << EOF
  > [extensions]
  > bookrace=$TESTTMP/bookrace.py
  > EOF
  $ hg push -R client-A -r book-A >push-output.txt 2>&1 &

Wait up to 30 seconds for that push to start.

  $ clock=30
  $ while [ ! -f push-A-started ] && [ $clock -gt 0 ] ; do
  >    clock=`expr $clock - 1`
  >    sleep 1
  > done

Do the other push.

  $ cat >> bookrace-server/.hg/hgrc << EOF
  > [extensions]
  > bookrace=!
  > EOF

  $ hg push -R client-B -r book-B
  pushing to ssh://user@dummy/bookrace-server
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 1 changesets with 1 changes to 1 files
  updating bookmark book-B

Signal the raced put that we are done (it waits up to 30 seconds).

  $ touch push-B-done

Wait for the raced push to finish (with the remaning of the initial 30 seconds).

  $ while [ ! -f push-A-done ] && [ $clock -gt 0 ] ; do
  >    clock=`expr $clock - 1`
  >    sleep 1
  > done

Check raced push output.

  $ cat push-output.txt
  pushing to ssh://user@dummy/bookrace-server
  searching for changes
  remote: setting raced push up
  remote has heads on branch 'default' that are not known locally: f26c3b5167d1
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 1 changesets with 1 changes to 1 files
  updating bookmark book-A

Check result of the push.

  $ hg -R bookrace-server log -G
  o  changeset:   4:9ce3b28c16de
  |  bookmark:    book-A
  |  tag:         tip
  |  parent:      1:39c28d785860
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     A1
  |
  | o  changeset:   3:f26c3b5167d1
  | |  bookmark:    book-B
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     B1
  | |
  | o  changeset:   2:c79985706978
  | |  parent:      0:6569b5a81c7e
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     B0
  | |
  o |  changeset:   1:39c28d785860
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     A0
  |
  o  changeset:   0:6569b5a81c7e
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     root
  
  $ hg -R bookrace-server book
     book-A                    4:9ce3b28c16de
     book-B                    3:f26c3b5167d1

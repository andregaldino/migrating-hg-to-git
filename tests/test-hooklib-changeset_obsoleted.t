  $ cat <<EOF >> $HGRCPATH
  > [experimental]
  > evolution = true
  > 
  > [extensions]
  > notify =
  > hooklib =
  > 
  > [phases]
  > publish = False
  > 
  > [notify]
  > sources = pull
  > diffstat = False
  > messageidseed = example
  > domain = example.com
  > 
  > [reposubs]
  > * = baz
  > EOF
  $ hg init a
  $ hg --cwd a debugbuilddag +2
  $ hg init b
  $ cat <<EOF >> b/.hg/hgrc
  > [hooks]
  > incoming.notify = python:hgext.notify.hook
  > txnclose.changeset_obsoleted = python:hgext.hooklib.changeset_obsoleted.hook
  > EOF
  $ hg --cwd b pull ../a | "$PYTHON" $TESTDIR/unwrap-message-id.py
  pulling from ../a
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b:66f7d451a68b (2 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  Date: * (glob)
  Subject: changeset in * (glob)
  From: debugbuilddag@example.com
  X-Hg-Notification: changeset 1ea73414a91b
  Message-Id: <hg.81c297828fd2d5afaadf2775a6a71b74143b6451dfaac09fac939e9107a50d01@example.com>
  To: baz@example.com
  
  changeset 1ea73414a91b in $TESTTMP/b
  details: $TESTTMP/b?cmd=changeset;node=1ea73414a91b
  description:
  	r0
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  Date: * (glob)
  Subject: changeset in * (glob)
  From: debugbuilddag@example.com
  X-Hg-Notification: changeset 66f7d451a68b
  Message-Id: <hg.364d03da7dc13829eb779a805be7e37f54f572e9afcea7d2626856a794d3e8f3@example.com>
  To: baz@example.com
  
  changeset 66f7d451a68b in $TESTTMP/b
  details: $TESTTMP/b?cmd=changeset;node=66f7d451a68b
  description:
  	r1
  (run 'hg update' to get a working copy)
  $ hg --cwd a debugobsolete 1ea73414a91b0920940797d8fc6a11e447f8ea1e
  1 new obsolescence markers
  obsoleted 1 changesets
  1 new orphan changesets
  $ hg --cwd a push ../b --hidden | "$PYTHON" $TESTDIR/unwrap-message-id.py
  1 new orphan changesets
  pushing to ../b
  searching for changes
  no changes found
  1 new obsolescence markers
  obsoleted 1 changesets
  Subject: changeset abandoned
  In-reply-to: <hg.81c297828fd2d5afaadf2775a6a71b74143b6451dfaac09fac939e9107a50d01@example.com>
  Message-Id: <hg.d6329e9481594f0f3c8a84362b3511318bfbce50748ab1123f909eb6fbcab018@example.com>
  Date: * (glob)
  From: test@example.com
  To: baz@example.com
  
  This changeset has been abandoned.

Check that known changesets with known successors do not result in a mail.

  $ hg init c
  $ hg init d
  $ cat <<EOF >> d/.hg/hgrc
  > [hooks]
  > incoming.notify = python:hgext.notify.hook
  > txnclose.changeset_obsoleted = python:hgext.hooklib.changeset_obsoleted.hook
  > EOF
  $ hg --cwd c debugbuilddag '.:parent.*parent'
  $ hg --cwd c push ../d -r 1
  pushing to ../d
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 0 changes to 0 files
  $ hg --cwd c debugobsolete $(hg --cwd c log -T '{node}' -r 1) $(hg --cwd c log -T '{node}' -r 2)
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg --cwd c push ../d | "$PYTHON" $TESTDIR/unwrap-message-id.py
  pushing to ../d
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files (+1 heads)
  1 new obsolescence markers
  obsoleted 1 changesets

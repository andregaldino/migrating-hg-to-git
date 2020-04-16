  $ cat <<EOF >> $HGRCPATH
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
  $ hg --cwd a debugbuilddag .
  $ hg init b
  $ cat <<EOF >> b/.hg/hgrc
  > [hooks]
  > incoming.notify = python:hgext.notify.hook
  > txnclose-phase.changeset_published = python:hgext.hooklib.changeset_published.hook
  > EOF
  $ hg --cwd b pull ../a | "$PYTHON" $TESTDIR/unwrap-message-id.py
  pulling from ../a
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b (1 drafts)
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
  (run 'hg update' to get a working copy)
  $ hg --cwd a phase --public 0
  $ hg --cwd b pull ../a | "$PYTHON" $TESTDIR/unwrap-message-id.py
  pulling from ../a
  searching for changes
  no changes found
  1 local changesets published
  Subject: changeset published
  In-reply-to: <hg.81c297828fd2d5afaadf2775a6a71b74143b6451dfaac09fac939e9107a50d01@example.com>
  Message-Id: <hg.2ec19bbddee5b542442bf5e1aed97bf706afff6aa765629883fbd1f4edd6fcb0@example.com>
  Date: * (glob)
  From: test@example.com
  To: baz@example.com
  
  This changeset has been published.
  $ hg --cwd b phase --force --draft 0
  $ cat <<EOF >> b/.hg/hgrc
  > [notify_published]
  > messageidseed = example2
  > domain = alt.example.com
  > template = Subject: changeset published
  >            From: hg@example.com\n
  >            This draft changeset has been published.\n
  > EOF
  $ hg --cwd b pull ../a | "$PYTHON" $TESTDIR/unwrap-message-id.py
  pulling from ../a
  searching for changes
  no changes found
  1 local changesets published
  Subject: changeset published
  From: hg@example.com
  In-reply-to: <hg.e3381dc41c051215e50b1c166a72949d0fff99609eb373420bcb763af80ef230@alt.example.com>
  Message-Id: <hg.c927f3d324e645a4245bfed20b0efb5b9582999d6be9bef45a37e7ec21208b24@alt.example.com>
  Date: * (glob)
  To: baz@example.com
  
  This draft changeset has been published.

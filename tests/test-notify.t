  $ cat > $TESTTMP/filter.py <<EOF
  > import io
  > import re
  > import sys
  > sys.stdout = io.TextIOWrapper(
  >     sys.stdout.buffer,
  >     sys.stdout.encoding,
  >     sys.stdout.errors,
  >     newline="\n",
  >     line_buffering=sys.stdout.line_buffering,
  > )
  > print(re.sub("\n[ \t]", " ", sys.stdin.read()), end="")
  > EOF

  $ cat <<EOF >> $HGRCPATH
  > [experimental]
  > evolution = true
  > 
  > [extensions]
  > notify=
  > strip=
  > 
  > [phases]
  > publish=False
  > 
  > [hooks]
  > incoming.notify = python:hgext.notify.hook
  > 
  > [notify]
  > sources = pull
  > diffstat = False
  > reply-to-predecessor = True
  > messageidseed = notifyseed
  > 
  > [usersubs]
  > foo@bar = *
  > 
  > [reposubs]
  > * = baz
  > EOF
  $ hg help notify
  notify extension - hooks for sending email push notifications
  
  This extension implements hooks to send email notifications when changesets
  are sent from or received by the local repository.
  
  First, enable the extension as explained in 'hg help extensions', and register
  the hook you want to run. "incoming" and "changegroup" hooks are run when
  changesets are received, while "outgoing" hooks are for changesets sent to
  another repository:
  
    [hooks]
    # one email for each incoming changeset
    incoming.notify = python:hgext.notify.hook
    # one email for all incoming changesets
    changegroup.notify = python:hgext.notify.hook
  
    # one email for all outgoing changesets
    outgoing.notify = python:hgext.notify.hook
  
  This registers the hooks. To enable notification, subscribers must be assigned
  to repositories. The "[usersubs]" section maps multiple repositories to a
  given recipient. The "[reposubs]" section maps multiple recipients to a single
  repository:
  
    [usersubs]
    # key is subscriber email, value is a comma-separated list of repo patterns
    user@host = pattern
  
    [reposubs]
    # key is repo pattern, value is a comma-separated list of subscriber emails
    pattern = user@host
  
  A "pattern" is a "glob" matching the absolute path to a repository, optionally
  combined with a revset expression. A revset expression, if present, is
  separated from the glob by a hash. Example:
  
    [reposubs]
    */widgets#branch(release) = qa-team@example.com
  
  This sends to "qa-team@example.com" whenever a changeset on the "release"
  branch triggers a notification in any repository ending in "widgets".
  
  In order to place them under direct user management, "[usersubs]" and
  "[reposubs]" sections may be placed in a separate "hgrc" file and incorporated
  by reference:
  
    [notify]
    config = /path/to/subscriptionsfile
  
  Notifications will not be sent until the "notify.test" value is set to
  "False"; see below.
  
  Notifications content can be tweaked with the following configuration entries:
  
  notify.test
    If "True", print messages to stdout instead of sending them. Default: True.
  
  notify.sources
    Space-separated list of change sources. Notifications are activated only
    when a changeset's source is in this list. Sources may be:
  
    "serve"       changesets received via http or ssh
    "pull"        changesets received via "hg pull"
    "unbundle"    changesets received via "hg unbundle"
    "push"        changesets sent or received via "hg push"
    "bundle"      changesets sent via "hg unbundle"
  
    Default: serve.
  
  notify.strip
    Number of leading slashes to strip from url paths. By default, notifications
    reference repositories with their absolute path. "notify.strip" lets you
    turn them into relative paths. For example, "notify.strip=3" will change
    "/long/path/repository" into "repository". Default: 0.
  
  notify.domain
    Default email domain for sender or recipients with no explicit domain. It is
    also used for the domain part of the "Message-Id" when using
    "notify.messageidseed".
  
  notify.messageidseed
    Create deterministic "Message-Id" headers for the mails based on the seed
    and the revision identifier of the first commit in the changeset.
  
  notify.style
    Style file to use when formatting emails.
  
  notify.template
    Template to use when formatting emails.
  
  notify.incoming
    Template to use when run as an incoming hook, overriding "notify.template".
  
  notify.outgoing
    Template to use when run as an outgoing hook, overriding "notify.template".
  
  notify.changegroup
    Template to use when running as a changegroup hook, overriding
    "notify.template".
  
  notify.maxdiff
    Maximum number of diff lines to include in notification email. Set to 0 to
    disable the diff, or -1 to include all of it. Default: 300.
  
  notify.maxdiffstat
    Maximum number of diffstat lines to include in notification email. Set to -1
    to include all of it. Default: -1.
  
  notify.maxsubject
    Maximum number of characters in email's subject line. Default: 67.
  
  notify.diffstat
    Set to True to include a diffstat before diff content. Default: True.
  
  notify.showfunc
    If set, override "diff.showfunc" for the diff content. Default: None.
  
  notify.merge
    If True, send notifications for merge changesets. Default: True.
  
  notify.mbox
    If set, append mails to this mbox file instead of sending. Default: None.
  
  notify.fromauthor
    If set, use the committer of the first changeset in a changegroup for the
    "From" field of the notification mail. If not set, take the user from the
    pushing repo.  Default: False.
  
  notify.reply-to-predecessor (EXPERIMENTAL)
    If set and the changeset has a predecessor in the repository, try to thread
    the notification mail with the predecessor. This adds the "In-Reply-To"
    header to the notification mail with a reference to the predecessor with the
    smallest revision number. Mail threads can still be torn, especially when
    changesets are folded.
  
    This option must  be used in combination with "notify.messageidseed".
  
  If set, the following entries will also be used to customize the
  notifications:
  
  email.from
    Email "From" address to use if none can be found in the generated email
    content.
  
  web.baseurl
    Root repository URL to combine with repository paths when making references.
    See also "notify.strip".
  
  no commands defined
  $ hg init a
  $ echo a > a/a
  $ echo b > a/b

commit

  $ hg --cwd a commit -Ama -d '0 0'
  adding a
  adding b

clone

  $ hg --traceback clone a b
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo a >> a/a
  $ echo b >> a/b

commit

  $ hg --traceback --cwd a commit -Amb -d '1 0'

on Mac OS X 10.5 the tmp path is very long so would get stripped in the subject line

  $ cat <<EOF >> $HGRCPATH
  > [notify]
  > maxsubject = 200
  > EOF

the python call below wraps continuation lines, which appear on Mac OS X 10.5 because
of the very long subject line
pull (minimal config)

  $ hg --traceback --cwd b --config notify.domain=example.com --config notify.messageidseed=example pull ../a | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >  "$PYTHON" $TESTTMP/filter.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  new changesets 00a13f371396 (1 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  Date: * (glob)
  Subject: changeset in $TESTTMP/b: b
  From: test@example.com
  X-Hg-Notification: changeset 00a13f371396
  Message-Id: <hg.ba3098a36bd4c297288d16788623a841f81f618ea961a0f0fd65de7eb1191b66@example.com>
  To: baz@example.com, foo@bar
  
  changeset 00a13f371396 in $TESTTMP/b
  details: $TESTTMP/b?cmd=changeset;node=00a13f371396
  description: b
  
  diffs (12 lines):
  
  diff -r 0cd96de13884 -r 00a13f371396 a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:01 1970 +0000
  @@ -1,1 +1,2 @@ a
  +a
  diff -r 0cd96de13884 -r 00a13f371396 b
  --- a/b	Thu Jan 01 00:00:00 1970 +0000
  +++ b/b	Thu Jan 01 00:00:01 1970 +0000
  @@ -1,1 +1,2 @@ b
  +b
  (run 'hg update' to get a working copy)

  $ cat <<EOF >> $HGRCPATH
  > [notify]
  > config = `pwd`/.notify.conf
  > domain = test.com
  > strip = 42
  > template = Subject: {desc|firstline|strip}\nFrom: {author}\nX-Test: foo\n\nchangeset {node|short} in {webroot}\ndescription:\n\t{desc|tabindent|strip}
  > 
  > [web]
  > baseurl = http://test/
  > EOF

fail for config file is missing

  $ hg --cwd b rollback
  repository tip rolled back to revision 0 (undo pull)
  $ hg --cwd b pull ../a 2>&1 | grep 'error.*\.notify\.conf' > /dev/null && echo pull failed
  pull failed
  $ touch ".notify.conf"

pull

  $ hg --cwd b rollback
  repository tip rolled back to revision 0 (undo pull)
  $ hg --traceback --cwd b pull ../a | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >  "$PYTHON" $TESTTMP/filter.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  new changesets 00a13f371396 (1 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  X-Test: foo
  Date: * (glob)
  Subject: b
  From: test@test.com
  X-Hg-Notification: changeset 00a13f371396
  Message-Id: <*> (glob)
  To: baz@test.com, foo@bar
  
  changeset 00a13f371396 in b
  description: b
  diffs (12 lines):
  
  diff -r 0cd96de13884 -r 00a13f371396 a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:01 1970 +0000
  @@ -1,1 +1,2 @@ a
  +a
  diff -r 0cd96de13884 -r 00a13f371396 b
  --- a/b	Thu Jan 01 00:00:00 1970 +0000
  +++ b/b	Thu Jan 01 00:00:01 1970 +0000
  @@ -1,1 +1,2 @@ b
  +b
  (run 'hg update' to get a working copy)

  $ cat << EOF >> $HGRCPATH
  > [hooks]
  > incoming.notify = python:hgext.notify.hook
  > 
  > [notify]
  > sources = pull
  > diffstat = True
  > EOF

pull

  $ hg --cwd b rollback
  repository tip rolled back to revision 0 (undo pull)
  $ hg --traceback --config notify.maxdiffstat=1 --cwd b pull ../a | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >  "$PYTHON" $TESTTMP/filter.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  new changesets 00a13f371396 (1 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  X-Test: foo
  Date: * (glob)
  Subject: b
  From: test@test.com
  X-Hg-Notification: changeset 00a13f371396
  Message-Id: <*> (glob)
  To: baz@test.com, foo@bar
  
  changeset 00a13f371396 in b
  description: b
  diffstat (truncated from 2 to 1 lines):
   a |  1 + 2 files changed, 2 insertions(+), 0 deletions(-)
  
  diffs (12 lines):
  
  diff -r 0cd96de13884 -r 00a13f371396 a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:01 1970 +0000
  @@ -1,1 +1,2 @@ a
  +a
  diff -r 0cd96de13884 -r 00a13f371396 b
  --- a/b	Thu Jan 01 00:00:00 1970 +0000
  +++ b/b	Thu Jan 01 00:00:01 1970 +0000
  @@ -1,1 +1,2 @@ b
  +b
  (run 'hg update' to get a working copy)

test merge

  $ cd a
  $ hg up -C 0
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo a >> a
  $ hg ci -Am adda2 -d '2 0'
  created new head
  $ hg merge
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg ci -m merge -d '3 0'
  $ cd ..
  $ hg --traceback --cwd b pull ../a | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >  "$PYTHON" $TESTTMP/filter.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 0 changes to 0 files
  new changesets 3332653e1f3c:fccf66cd0c35 (2 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  X-Test: foo
  Date: * (glob)
  Subject: adda2
  From: test@test.com
  X-Hg-Notification: changeset 3332653e1f3c
  Message-Id: <*> (glob)
  To: baz@test.com, foo@bar
  
  changeset 3332653e1f3c in b
  description: adda2
  diffstat:
   a |  1 + 1 files changed, 1 insertions(+), 0 deletions(-)
  
  diffs (6 lines):
  
  diff -r 0cd96de13884 -r 3332653e1f3c a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:02 1970 +0000
  @@ -1,1 +1,2 @@ a
  +a
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  X-Test: foo
  Date: * (glob)
  Subject: merge
  From: test@test.com
  X-Hg-Notification: changeset fccf66cd0c35
  Message-Id: <*> (glob)
  To: baz@test.com, foo@bar
  
  changeset fccf66cd0c35 in b
  description: merge
  diffstat:
   b |  1 + 1 files changed, 1 insertions(+), 0 deletions(-)
  
  diffs (6 lines):
  
  diff -r 3332653e1f3c -r fccf66cd0c35 b
  --- a/b	Thu Jan 01 00:00:02 1970 +0000
  +++ b/b	Thu Jan 01 00:00:03 1970 +0000
  @@ -1,1 +1,2 @@ b
  +b
  (run 'hg update' to get a working copy)

non-ascii content and truncation of multi-byte subject

  $ cat <<EOF >> $HGRCPATH
  > [notify]
  > maxsubject = 4
  > EOF
  $ echo a >> a/a
  $ hg --cwd a --encoding utf-8 commit -A -d '0 0' \
  >   -m `"$PYTHON" -c 'import sys; getattr(sys.stdout, "buffer", sys.stdout).write(b"\xc3\xa0\xc3\xa1\xc3\xa2\xc3\xa3\xc3\xa4")'`
  $ hg --traceback --cwd b --encoding utf-8 pull ../a | \
  >   "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >   "$PYTHON" $TESTTMP/filter.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 0f25f9c22b4c (1 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 8bit
  X-Test: foo
  Date: * (glob)
  Subject: =?utf-8?b?w6AuLi4=?= (py3 !)
  From: test@test.com
  X-Hg-Notification: changeset 0f25f9c22b4c
  Message-Id: <*> (glob)
  To: baz@test.com, foo@bar
  
  changeset 0f25f9c22b4c in b
  description: \xc3\xa0\xc3\xa1\xc3\xa2\xc3\xa3\xc3\xa4 (esc)
  diffstat:
   a |  1 + 1 files changed, 1 insertions(+), 0 deletions(-)
  
  diffs (7 lines):
  
  diff -r fccf66cd0c35 -r 0f25f9c22b4c a
  --- a/a	Thu Jan 01 00:00:03 1970 +0000
  +++ b/a	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,2 +1,3 @@ a a
  +a
  (run 'hg update' to get a working copy)

long lines

  $ cat <<EOF >> $HGRCPATH
  > [notify]
  > maxsubject = 67
  > test = False
  > mbox = mbox
  > EOF
  $ "$PYTHON" -c 'open("a/a", "ab").write(b"no" * 500 + b"\xd1\x84" + b"\n")'
  $ hg --cwd a commit -A -m "long line"
  $ hg --traceback --cwd b pull ../a
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets a846b5f6ebb7 (1 drafts)
  notify: sending 2 subscribers 1 changes
  (run 'hg update' to get a working copy)
  $ cat b/mbox | "$PYTHON" $TESTDIR/unwrap-message-id.py | "$PYTHON" $TESTTMP/filter.py
  From test@test.com ... ... .. ..:..:.. .... (re)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="*" (glob)
  Content-Transfer-Encoding: quoted-printable
  X-Test: foo
  Date: * (glob)
  Subject: long line
  From: test@test.com
  X-Hg-Notification: changeset a846b5f6ebb7
  Message-Id: <hg.e7dc7658565793ff33c797e72b7d1f3799347b042af3c40df6d17c8d5c3e560a@test.com>
  To: baz@test.com, foo@bar
  
  changeset a846b5f6ebb7 in b
  description: long line
  diffstat:
   a |  1 + 1 files changed, 1 insertions(+), 0 deletions(-)
  
  diffs (8 lines):
  
  diff -r 0f25f9c22b4c -r a846b5f6ebb7 a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,3 +1,4 @@ a a a
  +nonononononononononononononononononononononononononononononononononononono=
  nononononononononononononononononononononononononononononononononononononon=
  ononononononononononononononononononononononononononononononononononononono=
  nononononononononononononononononononononononononononononononononononononon=
  ononononononononononononononononononononononononononononononononononononono=
  nononononononononononononononononononononononononononononononononononononon=
  ononononononononononononononononononononononononononononononononononononono=
  nononononononononononononononononononononononononononononononononononononon=
  ononononononononononononononononononononononononononononononononononononono=
  nononononononononononononononononononononononononononononononononononononon=
  ononononononononononononononononononononononononononononononononononononono=
  nononononononononononononononononononononononononononononononononononononon=
  ononononononononononononononononononononononononononononononononononononono=
  nonononononononononononono=D1=84
  
 revset selection: send to address that matches branch and repo

  $ cat << EOF >> $HGRCPATH
  > [hooks]
  > incoming.notify = python:hgext.notify.hook
  > 
  > [notify]
  > sources = pull
  > test = True
  > diffstat = False
  > maxdiff = 0
  > 
  > [reposubs]
  > */a#branch(test) = will_no_be_send@example.com
  > */b#branch(test) = notify@example.com
  > EOF
  $ hg --cwd a branch test
  marked working directory as branch test
  (branches are permanent and global, did you want a bookmark?)
  $ echo a >> a/a
  $ hg --cwd a ci -m test -d '1 0'
  $ echo a >> a/a
  $ hg --cwd a ci -m test -d '1 0'
  $ hg --traceback --cwd b pull ../a | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >  "$PYTHON" $TESTTMP/filter.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 1 files
  new changesets f7e5aaed4080:485bf79b9464 (2 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  X-Test: foo
  Date: * (glob)
  Subject: test
  From: test@test.com
  X-Hg-Notification: changeset f7e5aaed4080
  Message-Id: <hg.12e9ae631e2529e9cfbe7a93be0dd8a401280700640f802a60f20d7be659251d@test.com>
  To: baz@test.com, foo@bar, notify@example.com
  
  changeset f7e5aaed4080 in b
  description: test
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  X-Test: foo
  Date: * (glob)
  Subject: test
  From: test@test.com
  X-Hg-Notification: changeset 485bf79b9464
  Message-Id: <hg.15281d60c27d9d5fb70435d33ebc24cb5aa580f2535988dcb9923c26e8bc5c47@test.com>
  To: baz@test.com, foo@bar, notify@example.com
  
  changeset 485bf79b9464 in b
  description: test
  (run 'hg update' to get a working copy)

revset selection: don't send to address that waits for mails
from different branch

  $ hg --cwd a update default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo a >> a/a
  $ hg --cwd a ci -m test -d '1 0'
  $ hg --traceback --cwd b pull ../a | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >  "$PYTHON" $TESTTMP/filter.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files (+1 heads)
  new changesets 645eb6690ecf (1 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  X-Test: foo
  Date: * (glob)
  Subject: test
  From: test@test.com
  X-Hg-Notification: changeset 645eb6690ecf
  Message-Id: <hg.ba26b2c63e7deb44e86c934aeea147edde12a11b6ac94bda103dcab5028dc928@test.com>
  To: baz@test.com, foo@bar
  
  changeset 645eb6690ecf in b
  description: test
  (run 'hg heads' to see heads)

default template:

  $ grep -v '^template =' $HGRCPATH > "$HGRCPATH.new"
  $ mv "$HGRCPATH.new" $HGRCPATH
  $ echo a >> a/a
  $ hg --cwd a commit -m 'default template'
  $ hg --cwd b pull ../a -q | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >  "$PYTHON" $TESTTMP/filter.py
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  Date: * (glob)
  Subject: changeset in b: default template
  From: test@test.com
  X-Hg-Notification: changeset 5cd4346eed47
  Message-Id: <hg.8caa7941b24fc673d10910cb072e2d167362a3c5111cafefa47190d9b831f0a3@test.com>
  To: baz@test.com, foo@bar
  
  changeset 5cd4346eed47 in $TESTTMP/b
  details: http://test/b?cmd=changeset;node=5cd4346eed47
  description: default template

with style:

  $ cat <<EOF > notifystyle.map
  > changeset = "Subject: {desc|firstline|strip}
  >              From: {author}
  >              {""}
  >              changeset {node|short}"
  > EOF
  $ cat <<EOF >> $HGRCPATH
  > [notify]
  > style = $TESTTMP/notifystyle.map
  > EOF
  $ echo a >> a/a
  $ hg --cwd a commit -m 'with style'
  $ hg --cwd b pull ../a -q | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >  "$PYTHON" $TESTTMP/filter.py
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  Date: * (glob)
  Subject: with style
  From: test@test.com
  X-Hg-Notification: changeset ec8d9d852f56
  Message-Id: <hg.ccd5049818a6a277251189ce1d6d0cca10723d58214199e7178894adb99ed918@test.com>
  To: baz@test.com, foo@bar
  
  changeset ec8d9d852f56

with template (overrides style):

  $ cat <<EOF >> $HGRCPATH
  > template = Subject: {node|short}: {desc|firstline|strip}
  >            From: {author}
  >            {""}
  >            {desc}
  > EOF
  $ echo a >> a/a
  $ hg --cwd a commit -m 'with template'
  $ hg --cwd b pull ../a -q | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py | \
  >  "$PYTHON" $TESTTMP/filter.py
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  Date: * (glob)
  Subject: 14721b538ae3: with template
  From: test@test.com
  X-Hg-Notification: changeset 14721b538ae3
  Message-Id: <hg.7edb9765307a5a24528f3964672e794e2d21f2479e96c099bf52e02abd17b3a2@test.com>
  To: baz@test.com, foo@bar
  
  with template

showfunc diff
  $ cat <<EOF >> $HGRCPATH
  > showfunc = True
  > template =
  > maxdiff = -1
  > EOF
  $ cd a
  $ cat > f1 << EOF
  > int main() {
  >     int a = 0;
  >     int b = 1;
  >     int c = 2;
  >     int d = 3;
  >     return a + b + c + d;
  > }
  > EOF
  $ hg commit -Am addfunction
  adding f1
  $ hg debugobsolete eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee b86bc16ff894f057d023b306936f290954857187
  1 new obsolescence markers
  $ hg --cwd ../b pull ../a | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  1 new obsolescence markers
  new changesets b86bc16ff894 (1 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  Date: * (glob)
  Subject: addfunction
  From: test@test.com
  X-Hg-Notification: changeset b86bc16ff894
  Message-Id: <hg.4c7cacfbbd6ba170656be0c8fc0d7599bd925c0d545b836816be9983e6d08448@test.com>
  To: baz@test.com, foo@bar
  
  changeset b86bc16ff894
  diffs (11 lines):
  
  diff -r 14721b538ae3 -r b86bc16ff894 f1
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/f1	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,7 @@
  +int main() {
  +    int a = 0;
  +    int b = 1;
  +    int c = 2;
  +    int d = 3;
  +    return a + b + c + d;
  +}
  (run 'hg update' to get a working copy)
  $ cat > f1 << EOF
  > int main() {
  >     int a = 0;
  >     int b = 1;
  >     int c = 2;
  >     int e = 3;
  >     return a + b + c + e;
  > }
  > EOF
  $ hg commit -m changefunction
  $ hg debugobsolete 485bf79b9464197b2ed2debd0b16252ad64ed458 e81040e9838c704d8bf17658cb11758f24e40b6b
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg --cwd ../b --config notify.showfunc=True pull ../a | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  1 new obsolescence markers
  obsoleted 1 changesets
  new changesets e81040e9838c (1 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  Date: * (glob)
  Subject: changefunction
  From: test@test.com
  X-Hg-Notification: changeset e81040e9838c
  Message-Id: <hg.99b80bf1c5d0bf8f8a7e60107c1aa1da367a5943b2a70a8b36517d701557edff@test.com>
  In-Reply-To: <hg.15281d60c27d9d5fb70435d33ebc24cb5aa580f2535988dcb9923c26e8bc5c47@test.com>
  To: baz@test.com, foo@bar
  
  changeset e81040e9838c
  diffs (12 lines):
  
  diff -r b86bc16ff894 -r e81040e9838c f1
  --- a/f1	Thu Jan 01 00:00:00 1970 +0000
  +++ b/f1	Thu Jan 01 00:00:00 1970 +0000
  @@ -2,6 +2,6 @@ int main() {
       int a = 0;
       int b = 1;
       int c = 2;
  -    int d = 3;
  -    return a + b + c + d;
  +    int e = 3;
  +    return a + b + c + e;
   }
  (run 'hg update' to get a working copy)

Retry the In-Reply-To, but make sure the oldest known change is older.
This can happen when folding commits that have been rebased by another user.

  $ hg --cwd ../b strip tip
  saved backup bundle to $TESTTMP/b/.hg/strip-backup/e81040e9838c-10aad4de-backup.hg
  $ hg debugobsolete f7e5aaed408029cfe9890318245e87ef44739fdd e81040e9838c704d8bf17658cb11758f24e40b6b
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg --cwd ../b --config notify.showfunc=True pull ../a | \
  >  "$PYTHON" $TESTDIR/unwrap-message-id.py
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  2 new obsolescence markers
  obsoleted 2 changesets
  new changesets e81040e9838c (1 drafts)
  MIME-Version: 1.0
  Content-Type: text/plain; charset="us-ascii"
  Content-Transfer-Encoding: 7bit
  Date: * (glob)
  Subject: changefunction
  From: test@test.com
  X-Hg-Notification: changeset e81040e9838c
  Message-Id: <hg.99b80bf1c5d0bf8f8a7e60107c1aa1da367a5943b2a70a8b36517d701557edff@test.com>
  In-Reply-To: <hg.12e9ae631e2529e9cfbe7a93be0dd8a401280700640f802a60f20d7be659251d@test.com>
  To: baz@test.com, foo@bar
  
  changeset e81040e9838c
  diffs (12 lines):
  
  diff -r b86bc16ff894 -r e81040e9838c f1
  --- a/f1	Thu Jan 01 00:00:00 1970 +0000
  +++ b/f1	Thu Jan 01 00:00:00 1970 +0000
  @@ -2,6 +2,6 @@ int main() {
       int a = 0;
       int b = 1;
       int c = 2;
  -    int d = 3;
  -    return a + b + c + d;
  +    int e = 3;
  +    return a + b + c + e;
   }
  (run 'hg update' to get a working copy)

#require serve

  $ hg init test
  $ cd test

  $ echo foo>foo
  $ hg addremove
  adding foo
  $ hg commit -m 1

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 1 changesets with 1 changes to 1 files

  $ hg serve -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid >> $DAEMON_PIDS
  $ cd ..

  $ hg clone --pull http://foo:bar@localhost:$HGPORT/ copy
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 340e38bdcde4
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd copy
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 1 changesets with 1 changes to 1 files

  $ hg co
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cat foo
  foo

  $ hg manifest --debug
  2ed2a3912a0b24502043eae84ee4b279c18b90dd 644   foo

  $ hg pull
  pulling from http://foo@localhost:$HGPORT/
  searching for changes
  no changes found

  $ hg rollback --dry-run --verbose
  repository tip rolled back to revision -1 (undo pull: http://foo:***@localhost:$HGPORT/)

Test pull of non-existing 20 character revision specification, making sure plain ascii identifiers
not are encoded like a node:

  $ hg pull -r 'xxxxxxxxxxxxxxxxxxxy'
  pulling from http://foo@localhost:$HGPORT/
  abort: unknown revision 'xxxxxxxxxxxxxxxxxxxy'
  [255]
  $ hg pull -r 'xxxxxxxxxxxxxxxxxx y'
  pulling from http://foo@localhost:$HGPORT/
  abort: unknown revision 'xxxxxxxxxxxxxxxxxx y'
  [255]

Test pull of working copy revision
  $ hg pull -r 'ffffffffffff'
  pulling from http://foo@localhost:$HGPORT/
  abort: unknown revision 'ffffffffffff'
  [255]

Test 'file:' uri handling:

  $ hg pull -q file://../test-does-not-exist
  abort: file:// URLs can only refer to localhost
  [255]

  $ hg pull -q file://../test
  abort: file:// URLs can only refer to localhost
  [255]

MSYS changes 'file:' into 'file;'

#if no-msys
  $ hg pull -q file:../test  # no-msys
#endif

It's tricky to make file:// URLs working on every platform with
regular shell commands.

  $ URL=`"$PYTHON" -c "import os; print('file://foobar' + ('/' + os.getcwd().replace(os.sep, '/')).replace('//', '/') + '/../test')"`
  $ hg pull -q "$URL"
  abort: file:// URLs can only refer to localhost
  [255]

  $ URL=`"$PYTHON" -c "import os; print('file://localhost' + ('/' + os.getcwd().replace(os.sep, '/')).replace('//', '/') + '/../test')"`
  $ hg pull -q "$URL"

SEC: check for unsafe ssh url

  $ cat >> $HGRCPATH << EOF
  > [ui]
  > ssh = sh -c "read l; read l; read l"
  > EOF

  $ hg pull 'ssh://-oProxyCommand=touch${IFS}owned/path'
  pulling from ssh://-oProxyCommand%3Dtouch%24%7BIFS%7Downed/path
  abort: potentially unsafe url: 'ssh://-oProxyCommand=touch${IFS}owned/path'
  [255]
  $ hg pull 'ssh://%2DoProxyCommand=touch${IFS}owned/path'
  pulling from ssh://-oProxyCommand%3Dtouch%24%7BIFS%7Downed/path
  abort: potentially unsafe url: 'ssh://-oProxyCommand=touch${IFS}owned/path'
  [255]
  $ hg pull 'ssh://fakehost|touch${IFS}owned/path'
  pulling from ssh://fakehost%7Ctouch%24%7BIFS%7Downed/path
  abort: no suitable response from remote hg
  [255]
  $ hg --config ui.timestamp-output=true pull 'ssh://fakehost%7Ctouch%20owned/path'
  \[20[2-9][0-9]-[01][0-9]-[0-3][0-9]T[0-5][0-9]:[0-5][0-9]:[0-5][0-9]\.[0-9][0-9][0-9][0-9][0-9][0-9]\] pulling from ssh://fakehost%7Ctouch%20owned/path (re)
  \[20[2-9][0-9]-[01][0-9]-[0-3][0-9]T[0-5][0-9]:[0-5][0-9]:[0-5][0-9]\.[0-9][0-9][0-9][0-9][0-9][0-9]\] abort: no suitable response from remote hg (re)
  [255]

  $ [ ! -f owned ] || echo 'you got owned'

  $ cd ..

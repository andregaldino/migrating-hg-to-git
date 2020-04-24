#require test-repo

  $ . "$TESTDIR/helpers-testrepo.sh"
  $ check_code="$TESTDIR"/../contrib/check-code.py
  $ cd "$TESTDIR"/..

New errors are not allowed. Warnings are strongly discouraged.
(The writing "no-che?k-code" is for not skipping this file when checking.)

  $ testrepohg locate \
  > -X contrib/python-zstandard \
  > -X hgext/fsmonitor/pywatchman \
  > -X mercurial/thirdparty \
  > | sed 's-\\-/-g' | "$check_code" --warnings --per-file=0 - || false
  Skipping contrib/automation/hgautomation/__init__.py it has no-che?k-code (glob)
  Skipping contrib/automation/hgautomation/aws.py it has no-che?k-code (glob)
  Skipping contrib/automation/hgautomation/cli.py it has no-che?k-code (glob)
  Skipping contrib/automation/hgautomation/linux.py it has no-che?k-code (glob)
  Skipping contrib/automation/hgautomation/pypi.py it has no-che?k-code (glob)
  Skipping contrib/automation/hgautomation/ssh.py it has no-che?k-code (glob)
  Skipping contrib/automation/hgautomation/try_server.py it has no-che?k-code (glob)
  Skipping contrib/automation/hgautomation/windows.py it has no-che?k-code (glob)
  Skipping contrib/automation/hgautomation/winrm.py it has no-che?k-code (glob)
  Skipping contrib/fuzz/FuzzedDataProvider.h it has no-che?k-code (glob)
  Skipping contrib/fuzz/standalone_fuzz_target_runner.cc it has no-che?k-code (glob)
  Skipping contrib/packaging/hgpackaging/cli.py it has no-che?k-code (glob)
  Skipping contrib/packaging/hgpackaging/downloads.py it has no-che?k-code (glob)
  Skipping contrib/packaging/hgpackaging/inno.py it has no-che?k-code (glob)
  Skipping contrib/packaging/hgpackaging/py2exe.py it has no-che?k-code (glob)
  Skipping contrib/packaging/hgpackaging/pyoxidizer.py it has no-che?k-code (glob)
  Skipping contrib/packaging/hgpackaging/util.py it has no-che?k-code (glob)
  Skipping contrib/packaging/hgpackaging/wix.py it has no-che?k-code (glob)
  Skipping i18n/polib.py it has no-che?k-code (glob)
  Skipping mercurial/statprof.py it has no-che?k-code (glob)
  Skipping tests/badserverext.py it has no-che?k-code (glob)

@commands in debugcommands.py should be in alphabetical order.

  >>> import re
  >>> commands = []
  >>> with open('mercurial/debugcommands.py', 'rb') as fh:
  ...     for line in fh:
  ...         m = re.match(br"^@command\('([a-z]+)", line)
  ...         if m:
  ...             commands.append(m.group(1))
  >>> scommands = list(sorted(commands))
  >>> for i, command in enumerate(scommands):
  ...     if command != commands[i]:
  ...         print('commands in debugcommands.py not sorted; first differing '
  ...               'command is %s; expected %s' % (commands[i], command))
  ...         break

Prevent adding new files in the root directory accidentally.

  $ testrepohg files 'glob:*'
  .arcconfig
  .clang-format
  .editorconfig
  .hgignore
  .hgsigs
  .hgtags
  .jshintrc
  CONTRIBUTING
  CONTRIBUTORS
  COPYING
  Makefile
  README.rst
  black.toml
  hg
  hgeditor
  hgweb.cgi
  setup.py

Prevent adding modules which could be shadowed by ancient .so/.dylib.

  $ testrepohg files \
  > mercurial/base85.py \
  > mercurial/bdiff.py \
  > mercurial/diffhelpers.py \
  > mercurial/mpatch.py \
  > mercurial/osutil.py \
  > mercurial/parsers.py \
  > mercurial/zstd.py
  [1]

Keep python3 tests sorted:
  $ sort < contrib/python3-whitelist > $TESTTMP/py3sorted
  $ cmp contrib/python3-whitelist $TESTTMP/py3sorted || echo 'Please sort passing tests!'

Keep Windows line endings in check

  $ hg files 'set:eol(dos)'
  contrib/win32/hg.bat
  contrib/win32/mercurial.ini

#require test-repo hg10

  $ . "$TESTDIR/helpers-testrepo.sh"
  $ import_checker="$TESTDIR"/../contrib/import-checker.py

  $ cd "$TESTDIR"/..

There are a handful of cases here that require renaming a module so it
doesn't overlap with a stdlib module name. There are also some cycles
here that we should still endeavor to fix, and some cycles will be
hidden by deduplication algorithm in the cycle detector, so fixing
these may expose other cycles.

Known-bad files are excluded by -X as some of them would produce unstable
outputs, which should be fixed later.

NOTE: the `hg locate` command here only works on files that are known to
Mercurial. If you add an import of a new file and haven't yet `hg add`ed it, you
will likely receive warnings about a direct import.

  $ testrepohg locate 'set:**.py or grep(r"^#!.*?python")' \
  > 'tests/**.t' \
  > -X hgweb.cgi \
  > -X setup.py \
  > -X contrib/automation/ \
  > -X contrib/debugshell.py \
  > -X contrib/hgweb.fcgi \
  > -X contrib/packaging/hg-docker \
  > -X contrib/packaging/hgpackaging/ \
  > -X contrib/packaging/inno/ \
  > -X contrib/phab-clean.py \
  > -X contrib/python-zstandard/ \
  > -X contrib/win32/hgwebdir_wsgi.py \
  > -X contrib/perf-utils/perf-revlog-write-plot.py \
  > -X doc/gendoc.py \
  > -X doc/hgmanpage.py \
  > -X i18n/posplit \
  > -X mercurial/thirdparty \
  > -X tests/hypothesishelpers.py \
  > -X tests/test-check-interfaces.py \
  > -X tests/test-demandimport.py \
  > -X tests/test-imports-checker.t \
  > -X tests/test-verify-repo-operations.py \
  > -X tests/test-extension.t \
  > | sed 's-\\-/-g' | "$PYTHON" "$import_checker" -

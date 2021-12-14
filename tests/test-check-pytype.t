#require pytype py3 slow

  $ cd $RUNTESTDIR/..

Many of the individual files that are excluded here confuse pytype
because they do a mix of Python 2 and Python 3 things
conditionally. There's no good way to help it out with that as far as
I can tell, so let's just hide those files from it for now. We should
endeavor to empty this list out over time, as some of these are
probably hiding real problems.

mercurial/bundlerepo.py       # no vfs and ui attrs on bundlerepo
mercurial/chgserver.py        # [attribute-error]
mercurial/context.py          # many [attribute-error]
mercurial/crecord.py          # tons of [attribute-error], [module-attr]
mercurial/debugcommands.py    # [wrong-arg-types]
mercurial/dispatch.py         # initstdio: No attribute ... on TextIO [attribute-error]
mercurial/exchange.py         # [attribute-error]
mercurial/hgweb/hgweb_mod.py  # [attribute-error], [name-error], [wrong-arg-types]
mercurial/hgweb/server.py     # [attribute-error], [name-error], [module-attr]
mercurial/hgweb/webcommands.py  # [missing-parameter]
mercurial/hgweb/wsgicgi.py    # confused values in os.environ
mercurial/httppeer.py         # [attribute-error], [wrong-arg-types]
mercurial/interfaces          # No attribute 'capabilities' on peer [attribute-error]
mercurial/keepalive.py        # [attribute-error]
mercurial/localrepo.py        # [attribute-error]
mercurial/manifest.py         # [unsupported-operands], [wrong-arg-types]
mercurial/minirst.py          # [unsupported-operands], [attribute-error]
mercurial/pure/osutil.py      # [invalid-typevar], [not-callable]
mercurial/pure/parsers.py     # [attribute-error]
mercurial/pycompat.py         # bytes vs str issues
mercurial/repoview.py         # [attribute-error]
mercurial/sslutil.py          # [attribute-error]
mercurial/testing/storage.py  # tons of [attribute-error]
mercurial/ui.py               # [attribute-error], [wrong-arg-types]
mercurial/unionrepo.py        # ui, svfs, unfiltered [attribute-error]
mercurial/utils/procutil.py   # [attribute-error], [module-attr], [bad-return-type]
mercurial/utils/memorytop.py  # not 3.6 compatible
mercurial/win32.py            # [not-callable]
mercurial/wireprotoframing.py # [unsupported-operands], [attribute-error], [import-error]
mercurial/wireprotoserver.py  # line 253, in _availableapis: No attribute '__iter__' on Callable[[Any, Any], Any] [attribute-error]
mercurial/wireprotov1peer.py  # [attribute-error]
mercurial/wireprotov1server.py  # BUG?: BundleValueError handler accesses subclass's attrs

TODO: use --no-cache on test server?  Caching the files locally helps during
development, but may be a hinderance for CI testing.

  $ pytype -V 3.6 --keep-going --jobs auto mercurial \
  >    -x mercurial/bundlerepo.py \
  >    -x mercurial/chgserver.py \
  >    -x mercurial/context.py \
  >    -x mercurial/crecord.py \
  >    -x mercurial/debugcommands.py \
  >    -x mercurial/dispatch.py \
  >    -x mercurial/exchange.py \
  >    -x mercurial/hgweb/hgweb_mod.py \
  >    -x mercurial/hgweb/server.py \
  >    -x mercurial/hgweb/webcommands.py \
  >    -x mercurial/hgweb/wsgicgi.py \
  >    -x mercurial/httppeer.py \
  >    -x mercurial/interfaces \
  >    -x mercurial/keepalive.py \
  >    -x mercurial/localrepo.py \
  >    -x mercurial/manifest.py \
  >    -x mercurial/minirst.py \
  >    -x mercurial/pure/osutil.py \
  >    -x mercurial/pure/parsers.py \
  >    -x mercurial/pycompat.py \
  >    -x mercurial/repoview.py \
  >    -x mercurial/sslutil.py \
  >    -x mercurial/testing/storage.py \
  >    -x mercurial/thirdparty \
  >    -x mercurial/ui.py \
  >    -x mercurial/unionrepo.py \
  >    -x mercurial/utils/procutil.py \
  >    -x mercurial/utils/memorytop.py \
  >    -x mercurial/win32.py \
  >    -x mercurial/wireprotoframing.py \
  >    -x mercurial/wireprotoserver.py \
  >    -x mercurial/wireprotov1peer.py \
  >    -x mercurial/wireprotov1server.py \
  >  > $TESTTMP/pytype-output.txt || cat $TESTTMP/pytype-output.txt

Only show the results on a failure, because the output on success is also
voluminous and variable.

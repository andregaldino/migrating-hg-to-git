#require vcr
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > phabricator = 
  > EOF
  $ hg init repo
  $ cd repo
  $ cat >> .hg/hgrc <<EOF
  > [phabricator]
  > url = https://phab.mercurial-scm.org/
  > callsign = HG
  > 
  > [auth]
  > hgphab.schemes = https
  > hgphab.prefix = phab.mercurial-scm.org
  > # When working on the extension and making phabricator interaction
  > # changes, edit this to be a real phabricator token. When done, edit
  > # it back. The VCR transcripts will be auto-sanitised to replace your real
  > # token with this value.
  > hgphab.phabtoken = cli-hahayouwish
  > EOF
  $ VCR="$TESTDIR/phabricator"

Error is handled reasonably. We override the phabtoken here so that
when you're developing changes to phabricator.py you can edit the
above config and have a real token in the test but not have to edit
this test.
  $ hg phabread --config auth.hgphab.phabtoken=cli-notavalidtoken \
  >  --test-vcr "$VCR/phabread-conduit-error.json" D4480 | head
  abort: Conduit Error (ERR-INVALID-AUTH): API token "cli-notavalidtoken" has the wrong length. API tokens should be 32 characters long.

Basic phabread:
  $ hg phabread --test-vcr "$VCR/phabread-4480.json" D4480 | head
  # HG changeset patch
  # Date 1536771503 0
  # Parent  a5de21c9e3703f8e8eb064bd7d893ff2f703c66a
  exchangev2: start to implement pull with wire protocol v2
  
  Wire protocol version 2 will take a substantially different
  approach to exchange than version 1 (at least as far as pulling
  is concerned).
  
  This commit establishes a new exchangev2 module for holding

phabupdate with an accept:
  $ hg phabupdate --accept D4564 \
  > -m 'I think I like where this is headed. Will read rest of series later.'\
  >  --test-vcr "$VCR/accept-4564.json"

Create a differential diff:
  $ HGENCODING=utf-8; export HGENCODING
  $ echo alpha > alpha
  $ hg ci --addremove -m 'create alpha for phabricator test €'
  adding alpha
  $ hg phabsend -r . --test-vcr "$VCR/phabsend-create-alpha.json"
  D1190 - created - d386117f30e6: create alpha for phabricator test \xe2\x82\xac (esc)
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/d386117f30e6-24ffe649-phabsend.hg
  $ echo more >> alpha
  $ HGEDITOR=true hg ci --amend
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/a86ed7d85e86-b7a54f3b-amend.hg
  $ echo beta > beta
  $ hg ci --addremove -m 'create beta for phabricator test'
  adding beta
  $ hg phabsend -r ".^::" --test-vcr "$VCR/phabsend-update-alpha-create-beta.json"
  D1190 - updated - d940d39fb603: create alpha for phabricator test \xe2\x82\xac (esc)
  D1191 - created - 4b2486dfc8c7: create beta for phabricator test
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/4b2486dfc8c7-d90584fa-phabsend.hg
  $ unset HGENCODING

The amend won't explode after posting a public commit.  The local tag is left
behind to identify it.

  $ echo 'public change' > beta
  $ hg ci -m 'create public change for phabricator testing'
  $ hg phase --public .
  $ echo 'draft change' > alpha
  $ hg ci -m 'create draft change for phabricator testing'
  $ hg phabsend --amend -r '.^::' --test-vcr "$VCR/phabsend-create-public.json"
  D1192 - created - 24ffd6bca53a: create public change for phabricator testing
  D1193 - created - ac331633be79: create draft change for phabricator testing
  warning: not updating public commit 2:24ffd6bca53a
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/ac331633be79-719b961c-phabsend.hg
  $ hg tags -v
  tip                                3:a19f1434f9a5
  D1192                              2:24ffd6bca53a local

  $ hg debugcallconduit user.search --test-vcr "$VCR/phab-conduit.json" <<EOF
  > {
  >     "constraints": {
  >         "isBot": true
  >     }
  > }
  > EOF
  {
    "cursor": {
      "after": null,
      "before": null,
      "limit": 100,
      "order": null
    },
    "data": [],
    "maps": {},
    "query": {
      "queryKey": null
    }
  }

Template keywords
  $ hg log -T'{rev} {phabreview|json}\n'
  3 {"id": "D1193", "url": "https://phab.mercurial-scm.org/D1193"}
  2 {"id": "D1192", "url": "https://phab.mercurial-scm.org/D1192"}
  1 {"id": "D1191", "url": "https://phab.mercurial-scm.org/D1191"}
  0 {"id": "D1190", "url": "https://phab.mercurial-scm.org/D1190"}

  $ hg log -T'{rev} {if(phabreview, "{phabreview.url} {phabreview.id}")}\n'
  3 https://phab.mercurial-scm.org/D1193 D1193
  2 https://phab.mercurial-scm.org/D1192 D1192
  1 https://phab.mercurial-scm.org/D1191 D1191
  0 https://phab.mercurial-scm.org/D1190 D1190

Commenting when phabsending:
  $ echo comment > comment
  $ hg ci --addremove -m "create comment for phabricator test"
  adding comment
  $ hg phabsend -r . -m "For default branch" --test-vcr "$VCR/phabsend-comment-created.json"
  D1253 - created - a7ee4bac036a: create comment for phabricator test
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/a7ee4bac036a-8009b5a0-phabsend.hg
  $ echo comment2 >> comment
  $ hg ci --amend
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/81fce7de1b7d-05339e5b-amend.hg
  $ hg phabsend -r . -m "Address review comments" --test-vcr "$VCR/phabsend-comment-updated.json"
  D1253 - updated - 1acd4b60af38: create comment for phabricator test

Phabsending a skipped commit:
#if no-py3
  $ hg phabsend --no-amend -r . --test-vcr "$VCR/phabsend-skipped.json"
  D1253 - skipped - 1acd4b60af38: create comment for phabricator test
#endif
BROKEN: shouldn't error under py3
#if py3
  $ hg phabsend --no-amend -r . --test-vcr "$VCR/phabsend-skipped.json"
  ** unknown exception encountered, please report by visiting
  ** https://mercurial-scm.org/wiki/BugTracker
  ** Python 3* (glob)
  ** Mercurial Distributed SCM (version *) (glob)
  ** Extensions loaded: phabricator
  Traceback (most recent call last):
    File "*/install/bin/hg", line *, in <module> (glob)
      dispatch.run()
    File "*/install/lib/python/mercurial/dispatch.py", line *, in run (glob)
      status = dispatch(req)
    File "*/install/lib/python/mercurial/dispatch.py", line *, in dispatch (glob)
      ret = _runcatch(req) or 0
    File "*/install/lib/python/mercurial/dispatch.py", line *, in _runcatch (glob)
      return _callcatch(ui, _runcatchfunc)
    File "*/install/lib/python/mercurial/dispatch.py", line *, in _callcatch (glob)
      return scmutil.callcatch(ui, func)
    File "*/install/lib/python/mercurial/scmutil.py", line *, in callcatch (glob)
      return func()
    File "*/install/lib/python/mercurial/dispatch.py", line *, in _runcatchfunc (glob)
      return _dispatch(req)
    File "*/install/lib/python/mercurial/dispatch.py", line *, in _dispatch (glob)
      cmdpats, cmdoptions)
    File "*/install/lib/python/mercurial/dispatch.py", line *, in runcommand (glob)
      ret = _runcommand(ui, options, cmd, d)
    File "*/install/lib/python/mercurial/dispatch.py", line *, in _runcommand (glob)
      return cmdfunc()
    File "*/install/lib/python/mercurial/dispatch.py", line *, in <lambda> (glob)
      d = lambda: util.checksignature(func)(ui, *args, **strcmdopt)
    File "*/install/lib/python/mercurial/util.py", line *, in check (glob)
      return func(*args, **kwargs)
    File "*/install/lib/python/hgext/phabricator.py", line *, in inner (glob)
      return fn(*args, **kwargs)
    File "*/install/lib/python/hgext/phabricator.py", line *, in phabsend (glob)
      newrevphid = querydrev(repo, str(revid))[0][b'phid']
    File "*/install/lib/python/hgext/phabricator.py", line *, in querydrev (glob)
      tree = _parse(spec)
    File "*/install/lib/python/hgext/phabricator.py", line *, in _parse (glob)
      tree, pos = parser.parser(_elements).parse(_tokenize(text))
    File "*/install/lib/python/mercurial/parser.py", line *, in parse (glob)
      self._advance()
    File "*/install/lib/python/mercurial/parser.py", line *, in _advance (glob)
      self.current = next(self._iter, None)
    File "*/install/lib/python/hgext/phabricator.py", line *, in _tokenize (glob)
      view = memoryview(text) # zero-copy slice
  TypeError: memoryview: a bytes-like object is required, not 'str'
  [1]
#endif

Phabreading a DREV with a local:commits time as a string:
  $ hg phabread --test-vcr "$VCR/phabread-str-time.json" D1285
  # HG changeset patch
  # User test <test>
  # Date 1562019844 0
  # Branch default
  # Node ID da5c8c6bf23a36b6e3af011bc3734460692c23ce
  # Parent  1f634396406d03e565ed645370e5fecd062cf215
  test string time
  
  Differential Revision: https://phab.mercurial-scm.org/D1285
  diff --git a/test b/test
  new file mode 100644
  --- /dev/null
  +++ b/test
  @@ * @@ (glob)
  +test
  

  $ cd ..

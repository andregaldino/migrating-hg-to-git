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

Missing arguments print the command help

  $ hg phabread
  hg phabread: invalid arguments
  hg phabread DREVSPEC [OPTIONS]
  
  print patches from Phabricator suitable for importing
  
  options:
  
    --stack read dependencies
  
  (use 'hg phabread -h' to show more help)
  [255]

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
  abort: Conduit Error (ERR-CONDUIT-CORE): Validation errors:
    - You can not accept this revision because it has already been closed. Only open revisions can be accepted.
  [255]
  $ hg phabupdate --accept D7913 -m 'LGTM' --test-vcr "$VCR/accept-7913.json"

Create a differential diff:
  $ HGENCODING=utf-8; export HGENCODING
  $ echo alpha > alpha
  $ hg ci --addremove -m 'create alpha for phabricator test €'
  adding alpha
  $ hg phabsend -r . --test-vcr "$VCR/phabsend-create-alpha.json"
  D7915 - created - d386117f30e6: create alpha for phabricator test \xe2\x82\xac (esc)
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/d386117f30e6-24ffe649-phabsend.hg
  $ echo more >> alpha
  $ HGEDITOR=true hg ci --amend
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/347bf67801e5-3bf313e4-amend.hg
  $ echo beta > beta
  $ hg ci --addremove -m 'create beta for phabricator test'
  adding beta
  $ hg phabsend -r ".^::" --test-vcr "$VCR/phabsend-update-alpha-create-beta.json"
  D7915 - updated - c44b38f24a45: create alpha for phabricator test \xe2\x82\xac (esc)
  D7916 - created - 9e6901f21d5b: create beta for phabricator test
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/9e6901f21d5b-1fcd4f0e-phabsend.hg
  $ unset HGENCODING

The amend won't explode after posting a public commit.  The local tag is left
behind to identify it.

  $ echo 'public change' > beta
  $ hg ci -m 'create public change for phabricator testing'
  $ hg phase --public .
  $ echo 'draft change' > alpha
  $ hg ci -m 'create draft change for phabricator testing'
  $ hg phabsend --amend -r '.^::' --test-vcr "$VCR/phabsend-create-public.json"
  D7917 - created - 7b4185ab5d16: create public change for phabricator testing
  D7918 - created - 251c1c333fc6: create draft change for phabricator testing
  warning: not updating public commit 2:7b4185ab5d16
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/251c1c333fc6-41cb7c3b-phabsend.hg
  $ hg tags -v
  tip                                3:3244dc4a3334
  D7917                              2:7b4185ab5d16 local

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
  3 {"id": "D7918", "url": "https://phab.mercurial-scm.org/D7918"}
  2 {"id": "D7917", "url": "https://phab.mercurial-scm.org/D7917"}
  1 {"id": "D7916", "url": "https://phab.mercurial-scm.org/D7916"}
  0 {"id": "D7915", "url": "https://phab.mercurial-scm.org/D7915"}

  $ hg log -T'{rev} {if(phabreview, "{phabreview.url} {phabreview.id}")}\n'
  3 https://phab.mercurial-scm.org/D7918 D7918
  2 https://phab.mercurial-scm.org/D7917 D7917
  1 https://phab.mercurial-scm.org/D7916 D7916
  0 https://phab.mercurial-scm.org/D7915 D7915

Commenting when phabsending:
  $ echo comment > comment
  $ hg ci --addremove -m "create comment for phabricator test"
  adding comment
  $ hg phabsend -r . -m "For default branch" --test-vcr "$VCR/phabsend-comment-created.json"
  D7919 - created - d5dddca9023d: create comment for phabricator test
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/d5dddca9023d-adf673ba-phabsend.hg
  $ echo comment2 >> comment
  $ hg ci --amend
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/f7db812bbe1d-8fcded77-amend.hg
  $ hg phabsend -r . -m "Address review comments" --test-vcr "$VCR/phabsend-comment-updated.json"
  D7919 - updated - 1849d7828727: create comment for phabricator test

Phabsending a skipped commit:
  $ hg phabsend --no-amend -r . --test-vcr "$VCR/phabsend-skipped.json"
  D7919 - skipped - 1849d7828727: create comment for phabricator test

Phabesending a new binary, a modified binary, and a removed binary

  >>> open('bin', 'wb').write(b'\0a') and None
  $ hg ci -Am 'add binary'
  adding bin
  >>> open('bin', 'wb').write(b'\0b') and None
  $ hg ci -m 'modify binary'
  $ hg rm bin
  $ hg ci -m 'remove binary'
  $ hg phabsend -r .~2:: --test-vcr "$VCR/phabsend-binary.json"
  uploading bin@aa24a81f55de
  D8007 - created - aa24a81f55de: add binary
  uploading bin@d8d62a881b54
  D8008 - created - d8d62a881b54: modify binary
  D8009 - created - af55645b2e29: remove binary
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/aa24a81f55de-a3a0cf24-phabsend.hg

Phabsend a renamed binary and a copied binary, with and without content changes
to src and dest

  >>> open('bin2', 'wb').write(b'\0c') and None
  $ hg ci -Am 'add another binary'
  adding bin2

TODO: "bin2" can't be viewed in this commit (left or right side), and the URL
looks much different than when viewing "bin2_moved".  No idea if this is a phab
bug, or phabsend bug.  The patch (as printed by phabread) look reasonable
though.

  $ hg mv bin2 bin2_moved
  $ hg ci -m "moved binary"

Note: "bin2_moved" is also not viewable in phabricator with this review

  $ hg cp bin2_moved bin2_copied
  $ hg ci -m "copied binary"

Note: "bin2_moved_again" is marked binary in phabricator, and both sides of it
are viewable in their proper state.  "bin2_copied" is not viewable, and not
listed as binary in phabricator.

  >>> open('bin2_copied', 'wb').write(b'\0move+mod') and None
  $ hg mv bin2_copied bin2_moved_again
  $ hg ci -m "move+mod copied binary"

Note: "bin2_moved" and "bin2_moved_copy" are both marked binary, and both
viewable on each side.

  >>> open('bin2_moved', 'wb').write(b'\0precopy mod') and None
  $ hg cp bin2_moved bin2_moved_copied
  >>> open('bin2_moved', 'wb').write(b'\0copy src+mod') and None
  $ hg ci -m "copy+mod moved binary"

  $ hg phabsend -r .~4:: --test-vcr "$VCR/phabsend-binary-renames.json"
  uploading bin2@f42f9195e00c
  D8128 - created - f42f9195e00c: add another binary
  D8129 - created - 834ab31d80ae: moved binary
  D8130 - created - 494b750e5194: copied binary
  uploading bin2_moved_again@25f766b50cc2
  D8131 - created - 25f766b50cc2: move+mod copied binary
  uploading bin2_moved_copied@1b87b363a5e4
  uploading bin2_moved@1b87b363a5e4
  D8132 - created - 1b87b363a5e4: copy+mod moved binary
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/f42f9195e00c-e82a0769-phabsend.hg

Phabreading a DREV with a local:commits time as a string:
  $ hg phabread --test-vcr "$VCR/phabread-str-time.json" D1285
  # HG changeset patch
  # User Pulkit Goyal <7895pulkit@gmail.com>
  # Date 1509404054 -19800
  # Node ID 44fc1c1f1774a76423b9c732af6938435099bcc5
  # Parent  8feef8ef8389a3b544e0a74624f1efc3a8d85d35
  repoview: add a new attribute _visibilityexceptions and related API
  
  Currently we don't have a defined way in core to make some hidden revisions
  visible in filtered repo. Extensions to achieve the purpose of unhiding some
  hidden commits, wrap repoview.pinnedrevs() function.
  
  To make the above task simple and have well defined API, this patch adds a new
  attribute '_visibilityexceptions' to repoview class which will contains
  the hidden revs which should be exception.
  This will allow to set different exceptions for different repoview objects
  backed by the same unfiltered repo.
  
  This patch also adds API to add revs to the attribute set and get them.
  
  Thanks to Jun for suggesting the use of repoview class instead of localrepo.
  
  Differential Revision: https://phab.mercurial-scm.org/D1285
  diff --git a/mercurial/repoview.py b/mercurial/repoview.py
  --- a/mercurial/repoview.py
  +++ b/mercurial/repoview.py
  @@ * @@ (glob)
       subclasses of `localrepo`. Eg: `bundlerepo` or `statichttprepo`.
       """
   
  +    # hidden revs which should be visible
  +    _visibilityexceptions = set()
  +
       def __init__(self, repo, filtername):
           object.__setattr__(self, r'_unfilteredrepo', repo)
           object.__setattr__(self, r'filtername', filtername)
  @@ -231,6 +234,14 @@
               return self
           return self.unfiltered().filtered(name)
   
  +    def addvisibilityexceptions(self, revs):
  +        """adds hidden revs which should be visible to set of exceptions"""
  +        self._visibilityexceptions.update(revs)
  +
  +    def getvisibilityexceptions(self):
  +        """returns the set of hidden revs which should be visible"""
  +        return self._visibilityexceptions
  +
       # everything access are forwarded to the proxied repo
       def __getattr__(self, attr):
           return getattr(self._unfilteredrepo, attr)
  diff --git a/mercurial/localrepo.py b/mercurial/localrepo.py
  --- a/mercurial/localrepo.py
  +++ b/mercurial/localrepo.py
  @@ -570,6 +570,14 @@
       def close(self):
           self._writecaches()
   
  +    def addvisibilityexceptions(self, exceptions):
  +        # should be called on a filtered repository
  +        pass
  +
  +    def getvisibilityexceptions(self):
  +        # should be called on a filtered repository
  +        return set()
  +
       def _loadextensions(self):
           extensions.loadall(self.ui)
   
  
A bad .arcconfig doesn't error out
  $ echo 'garbage' > .arcconfig
  $ hg config phabricator --debug
  invalid JSON in $TESTTMP/repo/.arcconfig
  read config from: */.hgrc (glob)
  $TESTTMP/repo/.hg/hgrc:*: phabricator.url=https://phab.mercurial-scm.org/ (glob)
  $TESTTMP/repo/.hg/hgrc:*: phabricator.callsign=HG (glob)

The .arcconfig content overrides global config
  $ cat >> $HGRCPATH << EOF
  > [phabricator]
  > url = global
  > callsign = global
  > EOF
  $ cp $TESTDIR/../.arcconfig .
  $ mv .hg/hgrc .hg/hgrc.bak
  $ hg config phabricator --debug
  read config from: */.hgrc (glob)
  $TESTTMP/repo/.arcconfig: phabricator.callsign=HG
  $TESTTMP/repo/.arcconfig: phabricator.url=https://phab.mercurial-scm.org/

But it doesn't override local config
  $ cat >> .hg/hgrc << EOF
  > [phabricator]
  > url = local
  > callsign = local
  > EOF
  $ hg config phabricator --debug
  read config from: */.hgrc (glob)
  $TESTTMP/repo/.hg/hgrc:*: phabricator.url=local (glob)
  $TESTTMP/repo/.hg/hgrc:*: phabricator.callsign=local (glob)
  $ mv .hg/hgrc.bak .hg/hgrc

Phabimport works with a stack

  $ cd ..
  $ hg clone repo repo2 -qr 1
  $ cp repo/.hg/hgrc repo2/.hg/
  $ cd repo2
  $ hg phabimport --stack 'D7918' --test-vcr "$VCR/phabimport-stack.json"
  applying patch from D7917
  applying patch from D7918
  $ hg log -G -Tcompact
  o  3[tip]   aaef04066140   1970-01-01 00:00 +0000   test
  |    create draft change for phabricator testing
  |
  o  2   8de3712202d1   1970-01-01 00:00 +0000   test
  |    create public change for phabricator testing
  |
  @  1   a692622e6937   1970-01-01 00:00 +0000   test
  |    create beta for phabricator test
  |
  o  0   c44b38f24a45   1970-01-01 00:00 +0000   test
       create alpha for phabricator test \x80 (esc)
  
Phabimport can create secret commits

  $ hg rollback --config ui.rollback=True
  repository tip rolled back to revision 1 (undo phabimport)
  $ hg phabimport --stack 'D7918' --test-vcr "$VCR/phabimport-stack.json" \
  >    --config phabimport.secret=True
  applying patch from D7917
  applying patch from D7918
  $ hg log -T phases
  changeset:   3:aaef04066140
  tag:         tip
  phase:       secret
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     create draft change for phabricator testing
  
  changeset:   2:8de3712202d1
  phase:       secret
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     create public change for phabricator testing
  
  changeset:   1:a692622e6937
  phase:       public
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     create beta for phabricator test
  
  changeset:   0:c44b38f24a45
  phase:       public
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     create alpha for phabricator test \x80 (esc)
  

  $ cd ..

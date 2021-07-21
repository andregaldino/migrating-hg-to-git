#require vcr
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > phabricator = 
  > 
  > [auth]
  > hgphab.schemes = https
  > hgphab.prefix = phab.mercurial-scm.org
  > # When working on the extension and making phabricator interaction
  > # changes, edit this to be a real phabricator token. When done, edit
  > # it back. The VCR transcripts will be auto-sanitised to replace your real
  > # token with this value.
  > hgphab.phabtoken = cli-hahayouwish
  > 
  > [phabricator]
  > debug = True
  > EOF
  $ hg init repo
  $ cd repo
  $ cat >> .hg/hgrc <<EOF
  > [phabricator]
  > url = https://phab.mercurial-scm.org/
  > callsign = HG
  > EOF
  $ VCR="$TESTDIR/phabricator"

debugcallconduit doesn't claim invalid arguments without --test-vcr:
  $ echo '{}' | HGRCSKIPREPO= hg debugcallconduit 'conduit.ping'
  abort: config phabricator.url is required
  [255]

Error is handled reasonably. We override the phabtoken here so that
when you're developing changes to phabricator.py you can edit the
above config and have a real token in the test but not have to edit
this test.
  $ hg phabread --config auth.hgphab.phabtoken=cli-notavalidtoken \
  >  --test-vcr "$VCR/phabread-conduit-error.json" D4480 | head
  abort: Conduit Error (ERR-INVALID-AUTH): API token "cli-notavalidtoken" has the wrong length. API tokens should be 32 characters long.

Missing arguments don't crash, and may print the command help

  $ hg debugcallconduit
  hg debugcallconduit: invalid arguments
  hg debugcallconduit METHOD
  
  call Conduit API
  
  options:
  
  (use 'hg debugcallconduit -h' to show more help)
  [10]
  $ hg phabread
  abort: empty DREVSPEC set
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

Phabread with multiple DREVSPEC

TODO: attempt to order related revisions like --stack?
  $ hg phabread --test-vcr "$VCR/phabread-multi-drev.json" D8205 8206 D8207 \
  >             | grep '^Differential Revision'
  Differential Revision: https://phab.mercurial-scm.org/D8205
  Differential Revision: https://phab.mercurial-scm.org/D8206
  Differential Revision: https://phab.mercurial-scm.org/D8207

Empty DREVSPECs don't crash

  $ hg phabread --test-vcr "$VCR/phabread-empty-drev.json" D7917-D7917
  abort: empty DREVSPEC set
  [255]


phabupdate with an accept:
  $ hg phabupdate --accept D4564 \
  > -m 'I think I like where this is headed. Will read rest of series later.'\
  >  --test-vcr "$VCR/accept-4564.json"
  abort: Conduit Error (ERR-CONDUIT-CORE): Validation errors:
    - You can not accept this revision because it has already been closed. Only open revisions can be accepted.
  [255]
  $ hg phabupdate --accept D7913 -m 'LGTM' --test-vcr "$VCR/accept-7913.json"

phabupdate with --plan-changes:

  $ hg phabupdate --plan-changes D6876 --test-vcr "$VCR/phabupdate-change-6876.json"

Create a differential diff:
  $ HGENCODING=utf-8; export HGENCODING
  $ echo alpha > alpha
  $ hg ci --addremove -m 'create alpha for phabricator test €'
  adding alpha
  $ hg phabsend -r . --test-vcr "$VCR/phabsend-create-alpha.json"
  D7915 - created - 0:d386117f30e6 tip "create alpha for phabricator test \xe2\x82\xac" (esc)
  new commits: ['347bf67801e5']
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/d386117f30e6-24ffe649-phabsend.hg
  $ echo more >> alpha
  $ HGEDITOR=true hg ci --amend
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/347bf67801e5-3bf313e4-amend.hg
  $ echo beta > beta
  $ hg ci --addremove -m 'create beta for phabricator test'
  adding beta
  $ hg phabsend -r ".^::" --test-vcr "$VCR/phabsend-update-alpha-create-beta.json"
  c44b38f24a45 mapped to old nodes []
  D7915 - updated - 0:c44b38f24a45 "create alpha for phabricator test \xe2\x82\xac" (esc)
  D7916 - created - 1:9e6901f21d5b tip "create beta for phabricator test"
  new commits: ['a692622e6937']
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
  D7917 - created - 2:7b4185ab5d16 "create public change for phabricator testing"
  D7918 - created - 3:251c1c333fc6 tip "create draft change for phabricator testing"
  warning: not updating public commit 2:7b4185ab5d16
  new commits: ['3244dc4a3334']
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
  D7919 - created - 4:d5dddca9023d tip "create comment for phabricator test"
  new commits: ['f7db812bbe1d']
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/d5dddca9023d-adf673ba-phabsend.hg
  $ echo comment2 >> comment
  $ hg ci --amend
  saved backup bundle to $TESTTMP/repo/.hg/strip-backup/f7db812bbe1d-8fcded77-amend.hg
  $ hg phabsend -r . -m "Address review comments" --test-vcr "$VCR/phabsend-comment-updated.json"
  1849d7828727 mapped to old nodes []
  D7919 - updated - 4:1849d7828727 tip "create comment for phabricator test"

Phabsending a skipped commit:
  $ hg phabsend --no-amend -r . --test-vcr "$VCR/phabsend-skipped.json"
  1849d7828727 mapped to old nodes ['1849d7828727']
  D7919 - skipped - 4:1849d7828727 tip "create comment for phabricator test"

Phabsend doesn't create an instability when restacking existing revisions on top
of new revisions.

  $ hg init reorder
  $ cd reorder
  $ cat >> .hg/hgrc <<EOF
  > [phabricator]
  > url = https://phab.mercurial-scm.org/
  > callsign = HG
  > [experimental]
  > evolution = all
  > EOF

  $ echo "add" > file1.txt
  $ hg ci -Aqm 'added'
  $ echo "mod1" > file1.txt
  $ hg ci -m 'modified 1'
  $ echo "mod2" > file1.txt
  $ hg ci -m 'modified 2'
  $ hg phabsend -r . --test-vcr "$VCR/phabsend-add-parent-setup.json"
  D8433 - created - 2:5d3959e20d1d tip "modified 2"
  new commits: ['2b4aa8a88d61']
  $ hg log -G -T compact
  @  3[tip]:1   2b4aa8a88d61   1970-01-01 00:00 +0000   test
  |    modified 2
  |
  o  1   d549263bcb2d   1970-01-01 00:00 +0000   test
  |    modified 1
  |
  o  0   5cbade24e0fa   1970-01-01 00:00 +0000   test
       added
  
Also check that it doesn't create more orphans outside of the stack

  $ hg up -q 1
  $ echo "mod3" > file1.txt
  $ hg ci -m 'modified 3'
  created new head
  $ hg up -q 3
  $ hg phabsend -r ".^ + ." --test-vcr "$VCR/phabsend-add-parent.json"
  2b4aa8a88d61 mapped to old nodes ['2b4aa8a88d61']
  D8434 - created - 1:d549263bcb2d "modified 1"
  D8433 - updated - 3:2b4aa8a88d61 "modified 2"
  new commits: ['876a60d024de']
  new commits: ['0c6523cb1d0f']
  restabilizing 1eda4bf55021 as d2c78c3a3e01
  $ hg log -G -T compact
  o  7[tip]:5   d2c78c3a3e01   1970-01-01 00:00 +0000   test
  |    modified 3
  |
  | @  6   0c6523cb1d0f   1970-01-01 00:00 +0000   test
  |/     modified 2
  |
  o  5:0   876a60d024de   1970-01-01 00:00 +0000   test
  |    modified 1
  |
  o  0   5cbade24e0fa   1970-01-01 00:00 +0000   test
       added
  
Posting obsolete commits is disallowed

  $ echo "mod3" > file1.txt
  $ hg ci -m 'modified A'
  $ echo "mod4" > file1.txt
  $ hg ci -m 'modified B'

  $ hg up '.^'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo 'obsolete' > file1.txt
  $ hg amend --config extensions.amend=
  1 new orphan changesets
  $ hg log -G
  @  changeset:   10:082be6c94150
  |  tag:         tip
  |  parent:      6:0c6523cb1d0f
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     modified A
  |
  | *  changeset:   9:a67643f48146
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  instability: orphan
  | |  summary:     modified B
  | |
  | x  changeset:   8:db79727cb2f7
  |/   parent:      6:0c6523cb1d0f
  |    user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    obsolete:    rewritten using amend as 10:082be6c94150
  |    summary:     modified A
  |
  | o  changeset:   7:d2c78c3a3e01
  | |  parent:      5:876a60d024de
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     modified 3
  | |
  o |  changeset:   6:0c6523cb1d0f
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     modified 2
  |
  o  changeset:   5:876a60d024de
  |  parent:      0:5cbade24e0fa
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     modified 1
  |
  o  changeset:   0:5cbade24e0fa
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     added
  
  $ hg phabsend -r 5::
  abort: obsolete commits cannot be posted for review
  [255]

Don't restack existing orphans

  $ hg phabsend -r 5::tip --test-vcr "$VCR/phabsend-no-restack-orphan.json"
  876a60d024de mapped to old nodes ['876a60d024de']
  0c6523cb1d0f mapped to old nodes ['0c6523cb1d0f']
  D8434 - updated - 5:876a60d024de "modified 1"
  D8433 - updated - 6:0c6523cb1d0f "modified 2"
  D8435 - created - 10:082be6c94150 tip "modified A"
  new commits: ['b5913193c805']
  not restabilizing unchanged d2c78c3a3e01
  $ hg log -G
  @  changeset:   11:b5913193c805
  |  tag:         tip
  |  parent:      6:0c6523cb1d0f
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     modified A
  |
  | *  changeset:   9:a67643f48146
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  instability: orphan
  | |  summary:     modified B
  | |
  | x  changeset:   8:db79727cb2f7
  |/   parent:      6:0c6523cb1d0f
  |    user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    obsolete:    rewritten using amend, phabsend as 11:b5913193c805
  |    summary:     modified A
  |
  | o  changeset:   7:d2c78c3a3e01
  | |  parent:      5:876a60d024de
  | |  user:        test
  | |  date:        Thu Jan 01 00:00:00 1970 +0000
  | |  summary:     modified 3
  | |
  o |  changeset:   6:0c6523cb1d0f
  |/   user:        test
  |    date:        Thu Jan 01 00:00:00 1970 +0000
  |    summary:     modified 2
  |
  o  changeset:   5:876a60d024de
  |  parent:      0:5cbade24e0fa
  |  user:        test
  |  date:        Thu Jan 01 00:00:00 1970 +0000
  |  summary:     modified 1
  |
  o  changeset:   0:5cbade24e0fa
     user:        test
     date:        Thu Jan 01 00:00:00 1970 +0000
     summary:     added
  
  $ cd ..

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
  D8007 - created - 5:aa24a81f55de "add binary"
  uploading bin@d8d62a881b54
  D8008 - created - 6:d8d62a881b54 "modify binary"
  D8009 - created - 7:af55645b2e29 tip "remove binary"
  new commits: ['b8139fbb4a57']
  new commits: ['c88ce4c2d2ad']
  new commits: ['75dbbc901145']
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
  D8128 - created - 8:f42f9195e00c "add another binary"
  D8129 - created - 9:834ab31d80ae "moved binary"
  D8130 - created - 10:494b750e5194 "copied binary"
  uploading bin2_moved_again@25f766b50cc2
  D8131 - created - 11:25f766b50cc2 "move+mod copied binary"
  uploading bin2_moved_copied@1b87b363a5e4
  uploading bin2_moved@1b87b363a5e4
  D8132 - created - 12:1b87b363a5e4 tip "copy+mod moved binary"
  new commits: ['90437c20312a']
  new commits: ['f391f4da4c61']
  new commits: ['da86a9f3268c']
  new commits: ['003ffc16ba66']
  new commits: ['13bd750c36fa']
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
  $ hg config phabricator --source
  invalid JSON in $TESTTMP/repo/.arcconfig
  */.hgrc:*: phabricator.debug=True (glob)
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
  $ hg config phabricator --source
  */.hgrc:*: phabricator.debug=True (glob)
  $TESTTMP/repo/.arcconfig: phabricator.callsign=HG
  $TESTTMP/repo/.arcconfig: phabricator.url=https://phab.mercurial-scm.org/

But it doesn't override local config
  $ cat >> .hg/hgrc << EOF
  > [phabricator]
  > url = local
  > callsign = local
  > EOF
  $ hg config phabricator --source
  */.hgrc:*: phabricator.debug=True (glob)
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
  $ hg log -r .: -G -Tcompact
  o  3[tip]   aaef04066140   1970-01-01 00:00 +0000   test
  |    create draft change for phabricator testing
  |
  o  2   8de3712202d1   1970-01-01 00:00 +0000   test
  |    create public change for phabricator testing
  |
  @  1   a692622e6937   1970-01-01 00:00 +0000   test
  |    create beta for phabricator test
  ~
Phabimport can create secret commits

  $ hg rollback --config ui.rollback=True
  repository tip rolled back to revision 1 (undo phabimport)
  $ hg phabimport --stack 'D7918' --test-vcr "$VCR/phabimport-stack.json" \
  >    --config phabimport.secret=True
  applying patch from D7917
  applying patch from D7918
  $ hg log -r 'reverse(.:)' -T phases
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
  
phabupdate can convert from local revisions

  $ hg phabupdate --reclaim D7917 -r '.: and not public()'
  abort: cannot specify both DREVSPEC and --rev
  [10]

  $ hg phabupdate --reclaim -r '.: and not public()' --test-vcr "$VCR/phabupdate-revs.json"

Phabimport accepts multiple DREVSPECs

  $ hg rollback --config ui.rollback=True
  repository tip rolled back to revision 1 (undo phabimport)
  $ hg phabimport --no-stack D7917 D7918 --test-vcr "$VCR/phabimport-multi-drev.json"
  applying patch from D7917
  applying patch from D7918

Phabsend requires a linear range of commits

  $ hg phabsend -r 0+2+3
  abort: cannot phabsend multiple head revisions: c44b38f24a45 aaef04066140
  (the revisions must form a linear chain)
  [255]

Validate arguments with --fold

  $ hg phabsend --fold -r 1
  abort: cannot fold a single revision
  [255]
  $ hg phabsend --fold --no-amend -r 1::
  abort: cannot fold with --no-amend
  [255]
  $ hg phabsend --fold -r 1::
  abort: cannot fold revisions with different DREV values
  [255]

Setup a series of commits to be folded, and include the Test Plan field multiple
times to test the concatenation logic.  No Test Plan field in the last one to
ensure missing fields are skipped.

  $ hg init ../folded
  $ cd ../folded
  $ cat >> .hg/hgrc <<EOF
  > [phabricator]
  > url = https://phab.mercurial-scm.org/
  > callsign = HG
  > EOF

  $ echo 'added' > file.txt
  $ hg ci -Aqm 'added file'

  $ cat > log.txt <<EOF
  > one: first commit to review
  > 
  > This file was modified with 'mod1' as its contents.
  > 
  > Test Plan:
  > LOL!  What testing?!
  > EOF
  $ echo mod1 > file.txt
  $ hg ci -l log.txt

  $ cat > log.txt <<EOF
  > two: second commit to review
  > 
  > This file was modified with 'mod2' as its contents.
  > 
  > Test Plan:
  > Haha! yeah, right.
  > 
  > EOF
  $ echo mod2 > file.txt
  $ hg ci -l log.txt

  $ echo mod3 > file.txt
  $ hg ci -m '3: a commit with no detailed message'

The folding of immutable commits works...

  $ hg phase -r tip --public
  $ hg phabsend --fold -r 1:: --test-vcr "$VCR/phabsend-fold-immutable.json"
  D8386 - created - 1:a959a3f69d8d "one: first commit to review"
  D8386 - created - 2:24a4438154ba "two: second commit to review"
  D8386 - created - 3:d235829e802c tip "3: a commit with no detailed message"
  warning: not updating public commit 1:a959a3f69d8d
  warning: not updating public commit 2:24a4438154ba
  warning: not updating public commit 3:d235829e802c
  no newnodes to update

  $ hg phase -r 0 --draft --force

... as does the initial mutable fold...

  $ echo y | hg phabsend --fold --confirm -r 1:: \
  >          --test-vcr "$VCR/phabsend-fold-initial.json"
  NEW - 1:a959a3f69d8d "one: first commit to review"
  NEW - 2:24a4438154ba "two: second commit to review"
  NEW - 3:d235829e802c tip "3: a commit with no detailed message"
  Send the above changes to https://phab.mercurial-scm.org/ (Y/n)? y
  D8387 - created - 1:a959a3f69d8d "one: first commit to review"
  D8387 - created - 2:24a4438154ba "two: second commit to review"
  D8387 - created - 3:d235829e802c tip "3: a commit with no detailed message"
  updating local commit list for D8387
  new commits: ['602c4e738243', '832553266fe8', '921f8265efbd']
  saved backup bundle to $TESTTMP/folded/.hg/strip-backup/a959a3f69d8d-a4a24136-phabsend.hg

... and doesn't mangle the local commits.

  $ hg log -T '{rev}:{node|short}\n{indent(desc, "  ")}\n'
  3:921f8265efbd
    3: a commit with no detailed message
  
    Differential Revision: https://phab.mercurial-scm.org/D8387
  2:832553266fe8
    two: second commit to review
  
    This file was modified with 'mod2' as its contents.
  
    Test Plan:
    Haha! yeah, right.
  
    Differential Revision: https://phab.mercurial-scm.org/D8387
  1:602c4e738243
    one: first commit to review
  
    This file was modified with 'mod1' as its contents.
  
    Test Plan:
    LOL!  What testing?!
  
    Differential Revision: https://phab.mercurial-scm.org/D8387
  0:98d480e0d494
    added file

Setup some obsmarkers by adding a file to the middle commit.  This stress tests
getoldnodedrevmap() in later phabsends.

  $ hg up '.^'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo 'modified' > file2.txt
  $ hg add file2.txt
  $ hg amend --config experimental.evolution=all --config extensions.amend=
  1 new orphan changesets
  $ hg up 3
  obsolete feature not enabled but 1 markers found!
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg rebase --config experimental.evolution=all --config extensions.rebase=
  note: not rebasing 2:832553266fe8 "two: second commit to review", already in destination as 4:0124e5474c88 tip "two: second commit to review"
  rebasing 3:921f8265efbd "3: a commit with no detailed message"

When commits have changed locally, the local commit list on Phabricator is
updated.

  $ echo y | hg phabsend --fold --confirm -r 1:: \
  >          --test-vcr "$VCR/phabsend-fold-updated.json"
  obsolete feature not enabled but 2 markers found!
  602c4e738243 mapped to old nodes ['602c4e738243']
  0124e5474c88 mapped to old nodes ['832553266fe8']
  e4edb1fe3565 mapped to old nodes ['921f8265efbd']
  D8387 - 1:602c4e738243 "one: first commit to review"
  D8387 - 4:0124e5474c88 "two: second commit to review"
  D8387 - 5:e4edb1fe3565 tip "3: a commit with no detailed message"
  Send the above changes to https://phab.mercurial-scm.org/ (Y/n)? y
  D8387 - updated - 1:602c4e738243 "one: first commit to review"
  D8387 - updated - 4:0124e5474c88 "two: second commit to review"
  D8387 - updated - 5:e4edb1fe3565 tip "3: a commit with no detailed message"
  obsolete feature not enabled but 2 markers found! (?)
  updating local commit list for D8387
  new commits: ['602c4e738243', '0124e5474c88', 'e4edb1fe3565']
  $ hg log -Tcompact
  obsolete feature not enabled but 2 markers found!
  5[tip]   e4edb1fe3565   1970-01-01 00:00 +0000   test
    3: a commit with no detailed message
  
  4:1   0124e5474c88   1970-01-01 00:00 +0000   test
    two: second commit to review
  
  1   602c4e738243   1970-01-01 00:00 +0000   test
    one: first commit to review
  
  0   98d480e0d494   1970-01-01 00:00 +0000   test
    added file
  
When nothing has changed locally since the last phabsend, the commit list isn't
updated, and nothing is changed locally afterward.

  $ hg phabsend --fold -r 1:: --test-vcr "$VCR/phabsend-fold-no-changes.json"
  obsolete feature not enabled but 2 markers found!
  602c4e738243 mapped to old nodes ['602c4e738243']
  0124e5474c88 mapped to old nodes ['0124e5474c88']
  e4edb1fe3565 mapped to old nodes ['e4edb1fe3565']
  D8387 - updated - 1:602c4e738243 "one: first commit to review"
  D8387 - updated - 4:0124e5474c88 "two: second commit to review"
  D8387 - updated - 5:e4edb1fe3565 tip "3: a commit with no detailed message"
  obsolete feature not enabled but 2 markers found! (?)
  local commit list for D8387 is already up-to-date
  $ hg log -Tcompact
  obsolete feature not enabled but 2 markers found!
  5[tip]   e4edb1fe3565   1970-01-01 00:00 +0000   test
    3: a commit with no detailed message
  
  4:1   0124e5474c88   1970-01-01 00:00 +0000   test
    two: second commit to review
  
  1   602c4e738243   1970-01-01 00:00 +0000   test
    one: first commit to review
  
  0   98d480e0d494   1970-01-01 00:00 +0000   test
    added file
  
Fold will accept new revisions at the end...

  $ echo 'another mod' > file2.txt
  $ hg ci -m 'four: extend the fold range'
  obsolete feature not enabled but 2 markers found!
  $ hg phabsend --fold -r 1:: --test-vcr "$VCR/phabsend-fold-extend-end.json" \
  >             --config experimental.evolution=all
  602c4e738243 mapped to old nodes ['602c4e738243']
  0124e5474c88 mapped to old nodes ['0124e5474c88']
  e4edb1fe3565 mapped to old nodes ['e4edb1fe3565']
  D8387 - updated - 1:602c4e738243 "one: first commit to review"
  D8387 - updated - 4:0124e5474c88 "two: second commit to review"
  D8387 - updated - 5:e4edb1fe3565 "3: a commit with no detailed message"
  D8387 - created - 6:94aaae213b23 tip "four: extend the fold range"
  updating local commit list for D8387
  new commits: ['602c4e738243', '0124e5474c88', 'e4edb1fe3565', '51a04fea8707']
  $ hg log -r . -T '{desc}\n'
  four: extend the fold range
  
  Differential Revision: https://phab.mercurial-scm.org/D8387
  $ hg log -T'{rev} {if(phabreview, "{phabreview.url} {phabreview.id}")}\n' -r 1::
  obsolete feature not enabled but 3 markers found!
  1 https://phab.mercurial-scm.org/D8387 D8387
  4 https://phab.mercurial-scm.org/D8387 D8387
  5 https://phab.mercurial-scm.org/D8387 D8387
  7 https://phab.mercurial-scm.org/D8387 D8387

... and also accepts new revisions at the beginning of the range

It's a bit unfortunate that not having a Differential URL on the first commit
causes a new Differential Revision to be created, though it isn't *entirely*
unreasonable.  At least this updates the subsequent commits.

TODO: See if it can reuse the existing Differential.

  $ hg phabsend --fold -r 0:: --test-vcr "$VCR/phabsend-fold-extend-front.json" \
  >             --config experimental.evolution=all
  602c4e738243 mapped to old nodes ['602c4e738243']
  0124e5474c88 mapped to old nodes ['0124e5474c88']
  e4edb1fe3565 mapped to old nodes ['e4edb1fe3565']
  51a04fea8707 mapped to old nodes ['51a04fea8707']
  D8388 - created - 0:98d480e0d494 "added file"
  D8388 - updated - 1:602c4e738243 "one: first commit to review"
  D8388 - updated - 4:0124e5474c88 "two: second commit to review"
  D8388 - updated - 5:e4edb1fe3565 "3: a commit with no detailed message"
  D8388 - updated - 7:51a04fea8707 tip "four: extend the fold range"
  updating local commit list for D8388
  new commits: ['15e9b14b4b4c', '6320b7d714cf', '3ee132d41dbc', '30682b960804', 'ac7db67f0991']

  $ hg log -T '{rev}:{node|short}\n{indent(desc, "  ")}\n'
  obsolete feature not enabled but 8 markers found!
  12:ac7db67f0991
    four: extend the fold range
  
    Differential Revision: https://phab.mercurial-scm.org/D8388
  11:30682b960804
    3: a commit with no detailed message
  
    Differential Revision: https://phab.mercurial-scm.org/D8388
  10:3ee132d41dbc
    two: second commit to review
  
    This file was modified with 'mod2' as its contents.
  
    Test Plan:
    Haha! yeah, right.
  
    Differential Revision: https://phab.mercurial-scm.org/D8388
  9:6320b7d714cf
    one: first commit to review
  
    This file was modified with 'mod1' as its contents.
  
    Test Plan:
    LOL!  What testing?!
  
    Differential Revision: https://phab.mercurial-scm.org/D8388
  8:15e9b14b4b4c
    added file
  
    Differential Revision: https://phab.mercurial-scm.org/D8388

Test phabsend --fold with an `hg split` at the end of the range

  $ echo foo > file3.txt
  $ hg add file3.txt

  $ hg log -r . -T '{desc}' > log.txt
  $ echo 'amended mod' > file2.txt
  $ hg ci --amend -l log.txt --config experimental.evolution=all

  $ cat <<EOF | hg --config extensions.split= --config ui.interactive=True \
  >                --config experimental.evolution=all split -r .
  > n
  > y
  > y
  > y
  > y
  > EOF
  diff --git a/file2.txt b/file2.txt
  1 hunks, 1 lines changed
  examine changes to 'file2.txt'?
  (enter ? for help) [Ynesfdaq?] n
  
  diff --git a/file3.txt b/file3.txt
  new file mode 100644
  examine changes to 'file3.txt'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -0,0 +1,1 @@
  +foo
  record change 2/2 to 'file3.txt'?
  (enter ? for help) [Ynesfdaq?] y
  
  created new head
  diff --git a/file2.txt b/file2.txt
  1 hunks, 1 lines changed
  examine changes to 'file2.txt'?
  (enter ? for help) [Ynesfdaq?] y
  
  @@ -1,1 +1,1 @@
  -modified
  +amended mod
  record this change to 'file2.txt'?
  (enter ? for help) [Ynesfdaq?] y
  
  $ hg phabsend --fold -r 8:: --test-vcr "$VCR/phabsend-fold-split-end.json" \
  >             --config experimental.evolution=all
  15e9b14b4b4c mapped to old nodes ['15e9b14b4b4c']
  6320b7d714cf mapped to old nodes ['6320b7d714cf']
  3ee132d41dbc mapped to old nodes ['3ee132d41dbc']
  30682b960804 mapped to old nodes ['30682b960804']
  6bc15dc99efd mapped to old nodes ['ac7db67f0991']
  b50946d5e490 mapped to old nodes ['ac7db67f0991']
  D8388 - updated - 8:15e9b14b4b4c "added file"
  D8388 - updated - 9:6320b7d714cf "one: first commit to review"
  D8388 - updated - 10:3ee132d41dbc "two: second commit to review"
  D8388 - updated - 11:30682b960804 "3: a commit with no detailed message"
  D8388 - updated - 14:6bc15dc99efd "four: extend the fold range"
  D8388 - updated - 15:b50946d5e490 tip "four: extend the fold range"
  updating local commit list for D8388
  new commits: ['15e9b14b4b4c', '6320b7d714cf', '3ee132d41dbc', '30682b960804', '6bc15dc99efd', 'b50946d5e490']

Test phabsend --fold with an `hg fold` at the end of the range

  $ hg --config experimental.evolution=all --config extensions.rebase= \
  >    rebase -r '.^' -r . -d '.^^' --collapse -l log.txt
  rebasing 14:6bc15dc99efd "four: extend the fold range"
  rebasing 15:b50946d5e490 tip "four: extend the fold range"

  $ hg phabsend --fold -r 8:: --test-vcr "$VCR/phabsend-fold-fold-end.json" \
  >             --config experimental.evolution=all
  15e9b14b4b4c mapped to old nodes ['15e9b14b4b4c']
  6320b7d714cf mapped to old nodes ['6320b7d714cf']
  3ee132d41dbc mapped to old nodes ['3ee132d41dbc']
  30682b960804 mapped to old nodes ['30682b960804']
  e919cdf3d4fe mapped to old nodes ['6bc15dc99efd', 'b50946d5e490']
  D8388 - updated - 8:15e9b14b4b4c "added file"
  D8388 - updated - 9:6320b7d714cf "one: first commit to review"
  D8388 - updated - 10:3ee132d41dbc "two: second commit to review"
  D8388 - updated - 11:30682b960804 "3: a commit with no detailed message"
  D8388 - updated - 16:e919cdf3d4fe tip "four: extend the fold range"
  updating local commit list for D8388
  new commits: ['15e9b14b4b4c', '6320b7d714cf', '3ee132d41dbc', '30682b960804', 'e919cdf3d4fe']

  $ hg log -r tip -v
  obsolete feature not enabled but 12 markers found!
  changeset:   16:e919cdf3d4fe
  tag:         tip
  parent:      11:30682b960804
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  files:       file2.txt file3.txt
  description:
  four: extend the fold range
  
  Differential Revision: https://phab.mercurial-scm.org/D8388
  
  
Hashes in the messages are updated automatically as phabsend amends and restacks
them.  This covers both commits that are posted and descendants that are
restacked.

  $ cat >> .hg/hgrc << EOF
  > [experimental]
  > evolution = all
  > EOF

  $ echo content > file.txt
  $ hg ci -m 'base review (generate test for phabsend)'
  $ echo 'more content' > file.txt
  $ hg ci -m '133c1c6c6449 is my parent (generate test for phabsend)'
  $ echo 'even more content' > file.txt
  $ hg ci -m 'c2874a398f7e is my parent (generate test for phabsend)'

  $ hg phabsend -r 17::18  --test-vcr "$VCR/phabsend-hash-fixes.json"
  D8945 - created - 17:133c1c6c6449 "base review (generate test for phabsend)"
  D8946 - created - 18:c2874a398f7e "133c1c6c6449 is my parent (generate test for phabsend)"
  new commits: ['f444f060f4d6']
  new commits: ['9c9290f945b1']
  restabilizing 1528c12fa2e4 as b28b20212bd4

  $ hg log -l 3 -Tcompact
  22[tip]   b28b20212bd4   1970-01-01 00:00 +0000   test
    9c9290f945b1 is my parent (generate test for phabsend)
  
  21   9c9290f945b1   1970-01-01 00:00 +0000   test
    f444f060f4d6 is my parent (generate test for phabsend)
  
  20:16   f444f060f4d6   1970-01-01 00:00 +0000   test
    base review (generate test for phabsend)
  
  $ cd ..

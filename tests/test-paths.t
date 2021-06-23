  $ hg init a
  $ hg clone a b
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd a

with no paths:

  $ hg paths
  $ hg paths unknown
  not found!
  [1]
  $ hg paths -Tjson
  [
  ]

with paths:

  $ echo '[paths]' >> .hg/hgrc
  $ echo 'dupe = ../b#tip' >> .hg/hgrc
  $ echo 'expand = $SOMETHING/bar' >> .hg/hgrc
  $ hg in dupe
  comparing with $TESTTMP/b
  no changes found
  [1]
  $ cd ..
  $ hg -R a in dupe
  comparing with $TESTTMP/b
  no changes found
  [1]
  $ cd a
  $ hg paths
  dupe = $TESTTMP/b#tip
  expand = $TESTTMP/a/$SOMETHING/bar
  $ SOMETHING=foo hg paths
  dupe = $TESTTMP/b#tip
  expand = $TESTTMP/a/foo/bar
#if msys
  $ SOMETHING=//foo hg paths
  dupe = $TESTTMP/b#tip
  expand = /foo/bar
#else
  $ SOMETHING=/foo hg paths
  dupe = $TESTTMP/b#tip
  expand = /foo/bar
#endif
  $ hg paths -q
  dupe
  expand
  $ hg paths dupe
  $TESTTMP/b#tip
  $ hg paths -q dupe
  $ hg paths unknown
  not found!
  [1]
  $ hg paths -q unknown
  [1]

formatter output with paths:

  $ echo 'dupe:pushurl = https://example.com/dupe' >> .hg/hgrc
  $ hg paths -Tjson | sed 's|\\\\|\\|g'
  [
   {
    "name": "dupe",
    "pushurl": "https://example.com/dupe",
    "url": "$TESTTMP/b#tip"
   },
   {
    "name": "expand",
    "url": "$TESTTMP/a/$SOMETHING/bar"
   }
  ]
  $ hg paths -Tjson dupe | sed 's|\\\\|\\|g'
  [
   {
    "name": "dupe",
    "pushurl": "https://example.com/dupe",
    "url": "$TESTTMP/b#tip"
   }
  ]
  $ hg paths -Tjson -q unknown
  [
  ]
  [1]

log template:

 (behaves as a {name: path-string} dict by default)

  $ hg log -rnull -T '{peerurls}\n'
  dupe=$TESTTMP/b#tip expand=$TESTTMP/a/$SOMETHING/bar
  $ hg log -rnull -T '{join(peerurls, "\n")}\n'
  dupe=$TESTTMP/b#tip
  expand=$TESTTMP/a/$SOMETHING/bar
  $ hg log -rnull -T '{peerurls % "{name}: {url}\n"}'
  dupe: $TESTTMP/b#tip
  expand: $TESTTMP/a/$SOMETHING/bar
  $ hg log -rnull -T '{get(peerurls, "dupe")}\n'
  $TESTTMP/b#tip
#if windows
  $ hg log -rnull -T '{peerurls % "{urls|json}\n"}'
  [{"pushurl": "https://example.com/dupe", "url": "$STR_REPR_TESTTMP\\b#tip"}]
  [{"url": "$STR_REPR_TESTTMP\\a\\$SOMETHING\\bar"}]
#else
  $ hg log -rnull -T '{peerurls % "{urls|json}\n"}'
  [{"pushurl": "https://example.com/dupe", "url": "$TESTTMP/b#tip"}]
  [{"url": "$TESTTMP/a/$SOMETHING/bar"}]
#endif

 (sub options can be populated by map/dot operation)

  $ hg log -rnull \
  > -T '{get(peerurls, "dupe") % "url: {url}\npushurl: {pushurl}\n"}'
  url: $TESTTMP/b#tip
  pushurl: https://example.com/dupe
  $ hg log -rnull -T '{peerurls.dupe.pushurl}\n'
  https://example.com/dupe

 (in JSON, it's a dict of urls)

  $ hg log -rnull -T '{peerurls|json}\n' | sed 's|\\\\|/|g'
  {"dupe": "$TESTTMP/b#tip", "expand": "$TESTTMP/a/$SOMETHING/bar"}

password should be masked in plain output, but not in machine-readable/template
output:

  $ echo 'insecure = http://foo:insecure@example.com/' >> .hg/hgrc
  $ hg paths insecure
  http://foo:***@example.com/
  $ hg paths -Tjson insecure
  [
   {
    "name": "insecure",
    "url": "http://foo:insecure@example.com/"
   }
  ]
  $ hg log -rnull -T '{get(peerurls, "insecure")}\n'
  http://foo:insecure@example.com/

zeroconf wraps ui.configitems(), which shouldn't crash at least:

  $ hg paths --config extensions.zeroconf=
  dupe = $TESTTMP/b#tip
  dupe:pushurl = https://example.com/dupe
  expand = $TESTTMP/a/$SOMETHING/bar
  insecure = http://foo:***@example.com/

  $ cd ..

sub-options for an undeclared path are ignored

  $ hg init suboptions
  $ cd suboptions

  $ cat > .hg/hgrc << EOF
  > [paths]
  > path0 = https://example.com/path0
  > path1:pushurl = https://example.com/path1
  > EOF
  $ hg paths
  path0 = https://example.com/path0

unknown sub-options aren't displayed

  $ cat > .hg/hgrc << EOF
  > [paths]
  > path0 = https://example.com/path0
  > path0:foo = https://example.com/path1
  > EOF

  $ hg paths
  path0 = https://example.com/path0

:pushurl must be a URL

  $ cat > .hg/hgrc << EOF
  > [paths]
  > default = /path/to/nothing
  > default:pushurl = /not/a/url
  > EOF

  $ hg paths
  (paths.default:pushurl not a URL; ignoring: "/not/a/url")
  default = /path/to/nothing

#fragment is not allowed in :pushurl

  $ cat > .hg/hgrc << EOF
  > [paths]
  > default = https://example.com/repo
  > invalid = https://example.com/repo
  > invalid:pushurl = https://example.com/repo#branch
  > EOF

  $ hg paths
  ("#fragment" in paths.invalid:pushurl not supported; ignoring)
  default = https://example.com/repo
  invalid = https://example.com/repo
  invalid:pushurl = https://example.com/repo

  $ cd ..

'file:' disables [paths] entries for clone destination

  $ cat >> $HGRCPATH <<EOF
  > [paths]
  > gpath1 = http://hg.example.com
  > EOF

  $ hg clone a gpath1
  abort: cannot create new http repository
  [255]

  $ hg clone a file:gpath1
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd gpath1
  $ hg -q id
  000000000000

  $ cd ..

Testing path referencing other paths
====================================

basic setup
-----------

  $ ls -1
  a
  b
  gpath1
  suboptions
  $ hg init chained_path
  $ cd chained_path
  $ cat << EOF > .hg/hgrc
  > [paths]
  > default=../a
  > other_default=path://default
  > path_with_branch=../branchy#foo
  > other_branch=path://path_with_branch
  > other_branched=path://path_with_branch#default
  > pushdest=../push-dest
  > pushdest:pushrev=default
  > pushdest2=path://pushdest
  > pushdest-overwrite=path://pushdest
  > pushdest-overwrite:pushrev=foo
  > EOF

  $ hg init ../branchy
  $ hg init ../push-dest
  $ hg debugbuilddag -R ../branchy '.:base+3<base@foo+5'
  $ hg log -G -T '{branch}\n' -R ../branchy
  o  foo
  |
  o  foo
  |
  o  foo
  |
  o  foo
  |
  o  foo
  |
  | o  default
  | |
  | o  default
  | |
  | o  default
  |/
  o  default
  

  $ hg paths
  default = $TESTTMP/a
  gpath1 = http://hg.example.com/
  other_branch = $TESTTMP/branchy#foo
  other_branched = $TESTTMP/branchy#default
  other_default = $TESTTMP/a
  path_with_branch = $TESTTMP/branchy#foo
  pushdest = $TESTTMP/push-dest
  pushdest:pushrev = default
  pushdest-overwrite = $TESTTMP/push-dest
  pushdest-overwrite:pushrev = foo
  pushdest2 = $TESTTMP/push-dest
  pushdest2:pushrev = default

test basic chaining
-------------------

  $ hg path other_default
  $TESTTMP/a
  $ hg pull default
  pulling from $TESTTMP/a
  no changes found
  $ hg pull other_default
  pulling from $TESTTMP/a
  no changes found

test inheritance of the #fragment part
--------------------------------------

  $ hg pull path_with_branch
  pulling from $TESTTMP/branchy
  adding changesets
  adding manifests
  adding file changes
  added 6 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b:bcebb50b77de
  (run 'hg update' to get a working copy)
  $ hg pull other_branch
  pulling from $TESTTMP/branchy
  no changes found
  $ hg pull other_branched
  pulling from $TESTTMP/branchy
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 0 changes to 0 files (+1 heads)
  new changesets 66f7d451a68b:2dc09a01254d
  (run 'hg heads' to see heads)

test inheritance of the suboptions
----------------------------------

  $ hg push pushdest
  pushing to $TESTTMP/push-dest
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 0 changes to 0 files
  $ hg push pushdest2
  pushing to $TESTTMP/push-dest
  searching for changes
  no changes found
  [1]
  $ hg push pushdest-overwrite --new-branch
  pushing to $TESTTMP/push-dest
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 5 changesets with 0 changes to 0 files (+1 heads)

Test chaining path:// definition
--------------------------------

This is currently unsupported, but feel free to implement the necessary
dependency detection.

  $ cat << EOF >> .hg/hgrc
  > chain_path=path://other_default
  > EOF

  $ hg id
  000000000000
  $ hg path
  abort: cannot use `path://other_default`, "other_default" is also defined as a `path://`
  [255]
  $ hg pull chain_path
  abort: cannot use `path://other_default`, "other_default" is also defined as a `path://`
  [255]

Doing an actual circle should always be an issue

  $ cat << EOF >> .hg/hgrc
  > rock=path://cissors
  > cissors=path://paper
  > paper=://rock
  > EOF

  $ hg id
  000000000000
  $ hg path
  abort: cannot use `path://other_default`, "other_default" is also defined as a `path://`
  [255]
  $ hg pull chain_path
  abort: cannot use `path://other_default`, "other_default" is also defined as a `path://`
  [255]

Test basic error cases
----------------------

  $ cat << EOF > .hg/hgrc
  > [paths]
  > error-missing=path://unknown
  > EOF
  $ hg path
  abort: cannot use `path://unknown`, "unknown" is not a known path
  [255]
  $ hg pull error-missing
  abort: cannot use `path://unknown`, "unknown" is not a known path
  [255]

Test path pointing to multiple urls
===================================

Simple cases
------------
- one layer
- one list
- no special option

  $ cat << EOF > .hg/hgrc
  > [paths]
  > one-path=foo
  > multiple-path=foo,bar,baz,https://example.org/
  > multiple-path:multi-urls=yes
  > EOF
  $ hg path
  gpath1 = http://hg.example.com/
  multiple-path = $TESTTMP/chained_path/foo
  multiple-path:multi-urls = yes
  multiple-path = $TESTTMP/chained_path/bar
  multiple-path:multi-urls = yes
  multiple-path = $TESTTMP/chained_path/baz
  multiple-path:multi-urls = yes
  multiple-path = https://example.org/
  multiple-path:multi-urls = yes
  one-path = $TESTTMP/chained_path/foo

Reference to a list
-------------------

  $ cat << EOF >> .hg/hgrc
  > ref-to-multi=path://multiple-path
  > EOF
  $ hg path | grep ref-to-multi
  ref-to-multi = $TESTTMP/chained_path/foo
  ref-to-multi:multi-urls = yes
  ref-to-multi = $TESTTMP/chained_path/bar
  ref-to-multi:multi-urls = yes
  ref-to-multi = $TESTTMP/chained_path/baz
  ref-to-multi:multi-urls = yes
  ref-to-multi = https://example.org/
  ref-to-multi:multi-urls = yes

List with a reference
---------------------

  $ cat << EOF >> .hg/hgrc
  > multi-with-ref=path://one-path, ssh://babar@savannah/celeste-ville
  > multi-with-ref:multi-urls=yes
  > EOF
  $ hg path | grep multi-with-ref
  multi-with-ref = $TESTTMP/chained_path/foo
  multi-with-ref:multi-urls = yes
  multi-with-ref = ssh://babar@savannah/celeste-ville
  multi-with-ref:multi-urls = yes

List with a reference to a list
-------------------------------

  $ cat << EOF >> .hg/hgrc
  > multi-to-multi-ref = path://multiple-path, ssh://celeste@savannah/celeste-ville
  > multi-to-multi-ref:multi-urls = yes
  > EOF
  $ hg path | grep multi-to-multi-ref
  multi-to-multi-ref = $TESTTMP/chained_path/foo
  multi-to-multi-ref:multi-urls = yes
  multi-to-multi-ref = $TESTTMP/chained_path/bar
  multi-to-multi-ref:multi-urls = yes
  multi-to-multi-ref = $TESTTMP/chained_path/baz
  multi-to-multi-ref:multi-urls = yes
  multi-to-multi-ref = https://example.org/
  multi-to-multi-ref:multi-urls = yes
  multi-to-multi-ref = ssh://celeste@savannah/celeste-ville
  multi-to-multi-ref:multi-urls = yes

individual suboptions are inherited
-----------------------------------

  $ cat << EOF >> .hg/hgrc
  > with-pushurl = foo
  > with-pushurl:pushurl = http://foo.bar/
  > with-pushrev = bar
  > with-pushrev:pushrev = draft()
  > with-both = toto
  > with-both:pushurl = http://ta.ta
  > with-both:pushrev = secret()
  > ref-all-no-opts = path://with-pushurl, path://with-pushrev, path://with-both
  > ref-all-no-opts:multi-urls = yes
  > with-overwrite = path://with-pushurl, path://with-pushrev, path://with-both
  > with-overwrite:multi-urls = yes
  > with-overwrite:pushrev = public()
  > EOF
  $ hg path | grep with-pushurl
  with-pushurl = $TESTTMP/chained_path/foo
  with-pushurl:pushurl = http://foo.bar/
  $ hg path | grep with-pushrev
  with-pushrev = $TESTTMP/chained_path/bar
  with-pushrev:pushrev = draft()
  $ hg path | grep with-both
  with-both = $TESTTMP/chained_path/toto
  with-both:pushrev = secret()
  with-both:pushurl = http://ta.ta/
  $ hg path | grep ref-all-no-opts
  ref-all-no-opts = $TESTTMP/chained_path/foo
  ref-all-no-opts:multi-urls = yes
  ref-all-no-opts:pushurl = http://foo.bar/
  ref-all-no-opts = $TESTTMP/chained_path/bar
  ref-all-no-opts:multi-urls = yes
  ref-all-no-opts:pushrev = draft()
  ref-all-no-opts = $TESTTMP/chained_path/toto
  ref-all-no-opts:multi-urls = yes
  ref-all-no-opts:pushrev = secret()
  ref-all-no-opts:pushurl = http://ta.ta/
  $ hg path | grep with-overwrite
  with-overwrite = $TESTTMP/chained_path/foo
  with-overwrite:multi-urls = yes
  with-overwrite:pushrev = public()
  with-overwrite:pushurl = http://foo.bar/
  with-overwrite = $TESTTMP/chained_path/bar
  with-overwrite:multi-urls = yes
  with-overwrite:pushrev = public()
  with-overwrite = $TESTTMP/chained_path/toto
  with-overwrite:multi-urls = yes
  with-overwrite:pushrev = public()
  with-overwrite:pushurl = http://ta.ta/

Windows needs ';' as a file separator in an environment variable, and MSYS
doesn't automatically convert it in every case.

#if windows
  $ path_list_var() {
  >     echo $1 | sed 's/:/;/'
  > }
#else
  $ path_list_var() {
  >     echo $1
  > }
#endif


hide outer repo
  $ hg init

Invalid syntax: no value

  $ cat > .hg/hgrc << EOF
  > novaluekey
  > EOF
  $ hg showconfig
  config error at $TESTTMP/.hg/hgrc:1: novaluekey
  [30]

Invalid syntax: no key

  $ cat > .hg/hgrc << EOF
  > =nokeyvalue
  > EOF
  $ hg showconfig
  config error at $TESTTMP/.hg/hgrc:1: =nokeyvalue
  [30]

Test hint about invalid syntax from leading white space

  $ cat > .hg/hgrc << EOF
  >  key=value
  > EOF
  $ hg showconfig
  config error at $TESTTMP/.hg/hgrc:1: unexpected leading whitespace:  key=value
  [30]

  $ cat > .hg/hgrc << EOF
  >  [section]
  > key=value
  > EOF
  $ hg showconfig
  config error at $TESTTMP/.hg/hgrc:1: unexpected leading whitespace:  [section]
  [30]

Reset hgrc

  $ echo > .hg/hgrc

Test case sensitive configuration

  $ cat <<EOF >> $HGRCPATH
  > [Section]
  > KeY = Case Sensitive
  > key = lower case
  > EOF

  $ hg showconfig Section
  Section.KeY=Case Sensitive
  Section.key=lower case

  $ hg showconfig Section -Tjson
  [
   {
    "defaultvalue": null,
    "name": "Section.KeY",
    "source": "*.hgrc:*", (glob)
    "value": "Case Sensitive"
   },
   {
    "defaultvalue": null,
    "name": "Section.key",
    "source": "*.hgrc:*", (glob)
    "value": "lower case"
   }
  ]
  $ hg showconfig Section.KeY -Tjson
  [
   {
    "defaultvalue": null,
    "name": "Section.KeY",
    "source": "*.hgrc:*", (glob)
    "value": "Case Sensitive"
   }
  ]
  $ hg showconfig -Tjson | tail -7
   {
    "defaultvalue": null,
    "name": "*", (glob)
    "source": "*", (glob)
    "value": "*" (glob)
   }
  ]

Test config default of various types:

 {"defaultvalue": ""} for -T'json(defaultvalue)' looks weird, but that's
 how the templater works. Unknown keywords are evaluated to "".

 dynamicdefault

  $ hg config --config alias.foo= alias -Tjson
  [
   {
    "name": "alias.foo",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config alias.foo= alias -T'json(defaultvalue)'
  [
   {"defaultvalue": ""}
  ]
  $ hg config --config alias.foo= alias -T'{defaultvalue}\n'
  

 null

  $ hg config --config auth.cookiefile= auth -Tjson
  [
   {
    "defaultvalue": null,
    "name": "auth.cookiefile",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config auth.cookiefile= auth -T'json(defaultvalue)'
  [
   {"defaultvalue": null}
  ]
  $ hg config --config auth.cookiefile= auth -T'{defaultvalue}\n'
  

 false

  $ hg config --config commands.commit.post-status= commands -Tjson
  [
   {
    "defaultvalue": false,
    "name": "commands.commit.post-status",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config commands.commit.post-status= commands -T'json(defaultvalue)'
  [
   {"defaultvalue": false}
  ]
  $ hg config --config commands.commit.post-status= commands -T'{defaultvalue}\n'
  False

 true

  $ hg config --config format.dotencode= format.dotencode -Tjson
  [
   {
    "defaultvalue": true,
    "name": "format.dotencode",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config format.dotencode= format.dotencode -T'json(defaultvalue)'
  [
   {"defaultvalue": true}
  ]
  $ hg config --config format.dotencode= format.dotencode -T'{defaultvalue}\n'
  True

 bytes

  $ hg config --config commands.resolve.mark-check= commands -Tjson
  [
   {
    "defaultvalue": "none",
    "name": "commands.resolve.mark-check",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config commands.resolve.mark-check= commands -T'json(defaultvalue)'
  [
   {"defaultvalue": "none"}
  ]
  $ hg config --config commands.resolve.mark-check= commands -T'{defaultvalue}\n'
  none

 empty list

  $ hg config --config commands.show.aliasprefix= commands -Tjson
  [
   {
    "defaultvalue": [],
    "name": "commands.show.aliasprefix",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config commands.show.aliasprefix= commands -T'json(defaultvalue)'
  [
   {"defaultvalue": []}
  ]
  $ hg config --config commands.show.aliasprefix= commands -T'{defaultvalue}\n'
  

 nonempty list

  $ hg config --config progress.format= progress -Tjson
  [
   {
    "defaultvalue": ["topic", "bar", "number", "estimate"],
    "name": "progress.format",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config progress.format= progress -T'json(defaultvalue)'
  [
   {"defaultvalue": ["topic", "bar", "number", "estimate"]}
  ]
  $ hg config --config progress.format= progress -T'{defaultvalue}\n'
  topic bar number estimate

 int

  $ hg config --config profiling.freq= profiling -Tjson
  [
   {
    "defaultvalue": 1000,
    "name": "profiling.freq",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config profiling.freq= profiling -T'json(defaultvalue)'
  [
   {"defaultvalue": 1000}
  ]
  $ hg config --config profiling.freq= profiling -T'{defaultvalue}\n'
  1000

 float

  $ hg config --config profiling.showmax= profiling -Tjson
  [
   {
    "defaultvalue": 0.999,
    "name": "profiling.showmax",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config profiling.showmax= profiling -T'json(defaultvalue)'
  [
   {"defaultvalue": 0.999}
  ]
  $ hg config --config profiling.showmax= profiling -T'{defaultvalue}\n'
  0.999

Test empty config source:

  $ cat <<EOF > emptysource.py
  > def reposetup(ui, repo):
  >     ui.setconfig(b'empty', b'source', b'value')
  > EOF
  $ cp .hg/hgrc .hg/hgrc.orig
  $ cat <<EOF >> .hg/hgrc
  > [extensions]
  > emptysource = `pwd`/emptysource.py
  > EOF

  $ hg config --source empty.source
  none: value
  $ hg config empty.source -Tjson
  [
   {
    "defaultvalue": null,
    "name": "empty.source",
    "source": "",
    "value": "value"
   }
  ]

  $ cp .hg/hgrc.orig .hg/hgrc

Test "%unset"

  $ cat >> $HGRCPATH <<EOF
  > [unsettest]
  > local-hgrcpath = should be unset (HGRCPATH)
  > %unset local-hgrcpath
  > 
  > global = should be unset (HGRCPATH)
  > 
  > both = should be unset (HGRCPATH)
  > 
  > set-after-unset = should be unset (HGRCPATH)
  > EOF

  $ cat >> .hg/hgrc <<EOF
  > [unsettest]
  > local-hgrc = should be unset (.hg/hgrc)
  > %unset local-hgrc
  > 
  > %unset global
  > 
  > both = should be unset (.hg/hgrc)
  > %unset both
  > 
  > set-after-unset = should be unset (.hg/hgrc)
  > %unset set-after-unset
  > set-after-unset = should be set (.hg/hgrc)
  > EOF

  $ hg showconfig unsettest
  unsettest.set-after-unset=should be set (.hg/hgrc)

Test exit code when no config matches

  $ hg config Section.idontexist
  [1]

sub-options in [paths] aren't expanded

  $ cat > .hg/hgrc << EOF
  > [paths]
  > foo = ~/foo
  > foo:suboption = ~/foo
  > EOF

  $ hg showconfig paths
  paths.foo=~/foo
  paths.foo:suboption=~/foo

note: The path expansion no longer happens at the config level, but the path is
still expanded:

  $ hg path | grep foo
  foo = $TESTTMP/foo

edit failure

  $ HGEDITOR=false hg config --edit
  abort: edit failed: false exited with status 1
  [10]

config affected by environment variables

  $ EDITOR=e1 VISUAL=e2 hg config --source | grep 'ui\.editor'
  $VISUAL: ui.editor=e2

  $ VISUAL=e2 hg config --source --config ui.editor=e3 | grep 'ui\.editor'
  --config: ui.editor=e3

  $ PAGER=p1 hg config --source | grep 'pager\.pager'
  $PAGER: pager.pager=p1

  $ PAGER=p1 hg config --source --config pager.pager=p2 | grep 'pager\.pager'
  --config: pager.pager=p2

verify that aliases are evaluated as well

  $ hg init aliastest
  $ cd aliastest
  $ cat > .hg/hgrc << EOF
  > [ui]
  > user = repo user
  > EOF
  $ touch index
  $ unset HGUSER
  $ hg ci -Am test
  adding index
  $ hg log --template '{author}\n'
  repo user
  $ cd ..

alias has lower priority

  $ hg init aliaspriority
  $ cd aliaspriority
  $ cat > .hg/hgrc << EOF
  > [ui]
  > user = alias user
  > username = repo user
  > EOF
  $ touch index
  $ unset HGUSER
  $ hg ci -Am test
  adding index
  $ hg log --template '{author}\n'
  repo user
  $ cd ..

configs should be read in lexicographical order

  $ mkdir configs
  $ for i in `$TESTDIR/seq.py 10 99`; do
  >    printf "[section]\nkey=$i" > configs/$i.rc
  > done
  $ HGRCPATH=configs hg config section.key
  99

Listing all config options
==========================

The feature is experimental and behavior may varies. This test exists to make sure the code is run. We grep it to avoid too much variability in its current experimental state.

  $ hg config --exp-all-known | grep commit | grep -v ssh
  commands.commit.interactive.git=False
  commands.commit.interactive.ignoreblanklines=False
  commands.commit.interactive.ignorews=False
  commands.commit.interactive.ignorewsamount=False
  commands.commit.interactive.ignorewseol=False
  commands.commit.interactive.nobinary=False
  commands.commit.interactive.nodates=False
  commands.commit.interactive.noprefix=False
  commands.commit.interactive.showfunc=False
  commands.commit.interactive.unified=None
  commands.commit.interactive.word-diff=False
  commands.commit.post-status=False
  convert.git.committeractions=[*'messagedifferent'] (glob)
  convert.svn.dangerous-set-commit-dates=False
  experimental.copytrace.sourcecommitlimit=100
  phases.new-commit=draft
  ui.allowemptycommit=False
  ui.commitsubrepos=False


Configuration priority
======================

setup necessary file

  $ cat > file-A.rc << EOF
  > [config-test]
  > basic = value-A
  > pre-include= value-A
  > %include ./included.rc
  > post-include= value-A
  > [command-templates]
  > log = "value-A\n"
  > EOF

  $ cat > file-B.rc << EOF
  > [config-test]
  > basic = value-B
  > [ui]
  > logtemplate = "value-B\n"
  > EOF


  $ cat > included.rc << EOF
  > [config-test]
  > pre-include= value-included
  > post-include= value-included
  > EOF

  $ cat > file-C.rc << EOF
  > %include ./included-alias-C.rc
  > [ui]
  > logtemplate = "value-C\n"
  > EOF

  $ cat > included-alias-C.rc << EOF
  > [command-templates]
  > log = "value-included\n"
  > EOF


  $ cat > file-D.rc << EOF
  > [command-templates]
  > log = "value-D\n"
  > %include ./included-alias-D.rc
  > EOF

  $ cat > included-alias-D.rc << EOF
  > [ui]
  > logtemplate = "value-included\n"
  > EOF

Simple order checking
---------------------

If file B is read after file A, value from B overwrite value from A.

  $ HGRCPATH=`path_list_var "file-A.rc:file-B.rc"` hg config config-test.basic
  value-B

Ordering from include
---------------------

value from an include overwrite value defined before the include, but not the one defined after the include

  $ HGRCPATH="file-A.rc" hg config config-test.pre-include
  value-included
  $ HGRCPATH="file-A.rc" hg config config-test.post-include
  value-A

command line override
---------------------

  $ HGRCPATH=`path_list_var "file-A.rc:file-B.rc"` hg config config-test.basic --config config-test.basic=value-CLI
  value-CLI

Alias ordering
--------------

The official config is now `command-templates.log`, the historical
`ui.logtemplate` is a valid alternative for it.

When both are defined, The config value read the last "win", this should keep
being true if the config have other alias. In other word, the config value read
earlier will be considered "lower level" and the config read later would be
considered "higher level". And higher level values wins.

  $ HGRCPATH="file-A.rc" hg log -r .
  value-A
  $ HGRCPATH="file-B.rc" hg log -r .
  value-B
  $ HGRCPATH=`path_list_var "file-A.rc:file-B.rc"` hg log -r .
  value-B

Alias and include
-----------------

The pre/post include priority should also apply when tie-breaking alternatives.
See the case above for details about the two config options used.

  $ HGRCPATH="file-C.rc" hg log -r .
  value-C
  $ HGRCPATH="file-D.rc" hg log -r .
  value-included

command line override
---------------------

  $ HGRCPATH=`path_list_var "file-A.rc:file-B.rc"` hg log -r . --config ui.logtemplate="value-CLI\n"
  value-CLI

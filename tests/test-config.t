hide outer repo
  $ hg init

Invalid syntax: no value

  $ cat > .hg/hgrc << EOF
  > novaluekey
  > EOF
  $ hg showconfig
  hg: parse error at $TESTTMP/.hg/hgrc:1: novaluekey
  [255]

Invalid syntax: no key

  $ cat > .hg/hgrc << EOF
  > =nokeyvalue
  > EOF
  $ hg showconfig
  hg: parse error at $TESTTMP/.hg/hgrc:1: =nokeyvalue
  [255]

Test hint about invalid syntax from leading white space

  $ cat > .hg/hgrc << EOF
  >  key=value
  > EOF
  $ hg showconfig
  hg: parse error at $TESTTMP/.hg/hgrc:1:  key=value
  unexpected leading whitespace
  [255]

  $ cat > .hg/hgrc << EOF
  >  [section]
  > key=value
  > EOF
  $ hg showconfig
  hg: parse error at $TESTTMP/.hg/hgrc:1:  [section]
  unexpected leading whitespace
  [255]

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

  $ hg config --config format.dotencode= format -Tjson
  [
   {
    "defaultvalue": true,
    "name": "format.dotencode",
    "source": "--config",
    "value": ""
   }
  ]
  $ hg config --config format.dotencode= format -T'json(defaultvalue)'
  [
   {"defaultvalue": true}
  ]
  $ hg config --config format.dotencode= format -T'{defaultvalue}\n'
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

  $ hg config --debug empty.source
  read config from: * (glob)
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
  paths.foo:suboption=~/foo
  paths.foo=$TESTTMP/foo

edit failure

  $ HGEDITOR=false hg config --edit
  abort: edit failed: false exited with status 1
  [255]

config affected by environment variables

  $ EDITOR=e1 VISUAL=e2 hg config --debug | grep 'ui\.editor'
  $VISUAL: ui.editor=e2

  $ VISUAL=e2 hg config --debug --config ui.editor=e3 | grep 'ui\.editor'
  --config: ui.editor=e3

  $ PAGER=p1 hg config --debug | grep 'pager\.pager'
  $PAGER: pager.pager=p1

  $ PAGER=p1 hg config --debug --config pager.pager=p2 | grep 'pager\.pager'
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

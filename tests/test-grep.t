  $ hg init t
  $ cd t
  $ echo import > port
  $ hg add port
  $ hg commit -m 0 -u spam -d '0 0'
  $ echo export >> port
  $ hg commit -m 1 -u eggs -d '1 0'
  $ echo export > port
  $ echo vaportight >> port
  $ echo 'import/export' >> port
  $ hg commit -m 2 -u spam -d '2 0'
  $ echo 'import/export' >> port
  $ hg commit -m 3 -u eggs -d '3 0'
  $ head -n 3 port > port1
  $ mv port1 port
  $ hg commit -m 4 -u spam -d '4 0'

pattern error

  $ hg grep '**test**'
  grep: invalid match pattern: nothing to repeat* (glob)
  [1]

invalid revset syntax

  $ hg log -r 'diffcontains()'
  hg: parse error: diffcontains takes at least 1 argument
  [10]
  $ hg log -r 'diffcontains(:)'
  hg: parse error: diffcontains requires a string pattern
  [10]
  $ hg log -r 'diffcontains("re:**test**")'
  hg: parse error: invalid regular expression: nothing to repeat* (glob)
  [10]

simple

  $ hg grep -r tip:0 '.*'
  port:4:export
  port:4:vaportight
  port:4:import/export
  port:3:export
  port:3:vaportight
  port:3:import/export
  port:3:import/export
  port:2:export
  port:2:vaportight
  port:2:import/export
  port:1:import
  port:1:export
  port:0:import
  $ hg grep -r tip:0 port port
  port:4:export
  port:4:vaportight
  port:4:import/export
  port:3:export
  port:3:vaportight
  port:3:import/export
  port:3:import/export
  port:2:export
  port:2:vaportight
  port:2:import/export
  port:1:import
  port:1:export
  port:0:import

simple from subdirectory

  $ mkdir dir
  $ cd dir
  $ hg grep -r tip:0 port
  port:4:export
  port:4:vaportight
  port:4:import/export
  port:3:export
  port:3:vaportight
  port:3:import/export
  port:3:import/export
  port:2:export
  port:2:vaportight
  port:2:import/export
  port:1:import
  port:1:export
  port:0:import
  $ hg grep -r tip:0 port --config ui.relative-paths=yes
  ../port:4:export
  ../port:4:vaportight
  ../port:4:import/export
  ../port:3:export
  ../port:3:vaportight
  ../port:3:import/export
  ../port:3:import/export
  ../port:2:export
  ../port:2:vaportight
  ../port:2:import/export
  ../port:1:import
  ../port:1:export
  ../port:0:import
  $ cd ..

simple with color

  $ hg --config extensions.color= grep --config color.mode=ansi \
  >     --color=always port port -r tip:0
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m4\x1b[0m\x1b[0;36m:\x1b[0mex\x1b[0;31;1mport\x1b[0m (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m4\x1b[0m\x1b[0;36m:\x1b[0mva\x1b[0;31;1mport\x1b[0might (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m4\x1b[0m\x1b[0;36m:\x1b[0mim\x1b[0;31;1mport\x1b[0m/ex\x1b[0;31;1mport\x1b[0m (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m3\x1b[0m\x1b[0;36m:\x1b[0mex\x1b[0;31;1mport\x1b[0m (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m3\x1b[0m\x1b[0;36m:\x1b[0mva\x1b[0;31;1mport\x1b[0might (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m3\x1b[0m\x1b[0;36m:\x1b[0mim\x1b[0;31;1mport\x1b[0m/ex\x1b[0;31;1mport\x1b[0m (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m3\x1b[0m\x1b[0;36m:\x1b[0mim\x1b[0;31;1mport\x1b[0m/ex\x1b[0;31;1mport\x1b[0m (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m2\x1b[0m\x1b[0;36m:\x1b[0mex\x1b[0;31;1mport\x1b[0m (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m2\x1b[0m\x1b[0;36m:\x1b[0mva\x1b[0;31;1mport\x1b[0might (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m2\x1b[0m\x1b[0;36m:\x1b[0mim\x1b[0;31;1mport\x1b[0m/ex\x1b[0;31;1mport\x1b[0m (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m1\x1b[0m\x1b[0;36m:\x1b[0mim\x1b[0;31;1mport\x1b[0m (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m1\x1b[0m\x1b[0;36m:\x1b[0mex\x1b[0;31;1mport\x1b[0m (esc)
  \x1b[0;35mport\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m0\x1b[0m\x1b[0;36m:\x1b[0mim\x1b[0;31;1mport\x1b[0m (esc)

simple templated

  $ hg grep port -r tip:0 \
  > -T '{path}:{rev}:{node|short}:{texts % "{if(matched, text|upper, text)}"}\n'
  port:4:914fa752cdea:exPORT
  port:4:914fa752cdea:vaPORTight
  port:4:914fa752cdea:imPORT/exPORT
  port:3:95040cfd017d:exPORT
  port:3:95040cfd017d:vaPORTight
  port:3:95040cfd017d:imPORT/exPORT
  port:3:95040cfd017d:imPORT/exPORT
  port:2:3b325e3481a1:exPORT
  port:2:3b325e3481a1:vaPORTight
  port:2:3b325e3481a1:imPORT/exPORT
  port:1:8b20f75c1585:imPORT
  port:1:8b20f75c1585:exPORT
  port:0:f31323c92170:imPORT

  $ hg grep port -r tip:0 -T '{path}:{rev}:{texts}\n'
  port:4:export
  port:4:vaportight
  port:4:import/export
  port:3:export
  port:3:vaportight
  port:3:import/export
  port:3:import/export
  port:2:export
  port:2:vaportight
  port:2:import/export
  port:1:import
  port:1:export
  port:0:import

  $ hg grep port -r tip:0 -T '{path}:{tags}:{texts}\n'
  port:tip:export
  port:tip:vaportight
  port:tip:import/export
  port::export
  port::vaportight
  port::import/export
  port::import/export
  port::export
  port::vaportight
  port::import/export
  port::import
  port::export
  port::import

simple JSON (no "change" field)

  $ hg grep -r tip:0 -Tjson port
  [
   {
    "date": [4, 0],
    "lineno": 1,
    "node": "914fa752cdea87777ac1a8d5c858b0c736218f6c",
    "path": "port",
    "rev": 4,
    "texts": [{"matched": false, "text": "ex"}, {"matched": true, "text": "port"}],
    "user": "spam"
   },
   {
    "date": [4, 0],
    "lineno": 2,
    "node": "914fa752cdea87777ac1a8d5c858b0c736218f6c",
    "path": "port",
    "rev": 4,
    "texts": [{"matched": false, "text": "va"}, {"matched": true, "text": "port"}, {"matched": false, "text": "ight"}],
    "user": "spam"
   },
   {
    "date": [4, 0],
    "lineno": 3,
    "node": "914fa752cdea87777ac1a8d5c858b0c736218f6c",
    "path": "port",
    "rev": 4,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}, {"matched": false, "text": "/ex"}, {"matched": true, "text": "port"}],
    "user": "spam"
   },
   {
    "date": [3, 0],
    "lineno": 1,
    "node": "95040cfd017d658c536071c6290230a613c4c2a6",
    "path": "port",
    "rev": 3,
    "texts": [{"matched": false, "text": "ex"}, {"matched": true, "text": "port"}],
    "user": "eggs"
   },
   {
    "date": [3, 0],
    "lineno": 2,
    "node": "95040cfd017d658c536071c6290230a613c4c2a6",
    "path": "port",
    "rev": 3,
    "texts": [{"matched": false, "text": "va"}, {"matched": true, "text": "port"}, {"matched": false, "text": "ight"}],
    "user": "eggs"
   },
   {
    "date": [3, 0],
    "lineno": 3,
    "node": "95040cfd017d658c536071c6290230a613c4c2a6",
    "path": "port",
    "rev": 3,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}, {"matched": false, "text": "/ex"}, {"matched": true, "text": "port"}],
    "user": "eggs"
   },
   {
    "date": [3, 0],
    "lineno": 4,
    "node": "95040cfd017d658c536071c6290230a613c4c2a6",
    "path": "port",
    "rev": 3,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}, {"matched": false, "text": "/ex"}, {"matched": true, "text": "port"}],
    "user": "eggs"
   },
   {
    "date": [2, 0],
    "lineno": 1,
    "node": "3b325e3481a1f07435d81dfdbfa434d9a0245b47",
    "path": "port",
    "rev": 2,
    "texts": [{"matched": false, "text": "ex"}, {"matched": true, "text": "port"}],
    "user": "spam"
   },
   {
    "date": [2, 0],
    "lineno": 2,
    "node": "3b325e3481a1f07435d81dfdbfa434d9a0245b47",
    "path": "port",
    "rev": 2,
    "texts": [{"matched": false, "text": "va"}, {"matched": true, "text": "port"}, {"matched": false, "text": "ight"}],
    "user": "spam"
   },
   {
    "date": [2, 0],
    "lineno": 3,
    "node": "3b325e3481a1f07435d81dfdbfa434d9a0245b47",
    "path": "port",
    "rev": 2,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}, {"matched": false, "text": "/ex"}, {"matched": true, "text": "port"}],
    "user": "spam"
   },
   {
    "date": [1, 0],
    "lineno": 1,
    "node": "8b20f75c158513ff5ac80bd0e5219bfb6f0eb587",
    "path": "port",
    "rev": 1,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}],
    "user": "eggs"
   },
   {
    "date": [1, 0],
    "lineno": 2,
    "node": "8b20f75c158513ff5ac80bd0e5219bfb6f0eb587",
    "path": "port",
    "rev": 1,
    "texts": [{"matched": false, "text": "ex"}, {"matched": true, "text": "port"}],
    "user": "eggs"
   },
   {
    "date": [0, 0],
    "lineno": 1,
    "node": "f31323c9217050ba245ee8b537c713ec2e8ab226",
    "path": "port",
    "rev": 0,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}],
    "user": "spam"
   }
  ]

simple JSON without matching lines

  $ hg grep -r tip:0 -Tjson -l port
  [
   {
    "date": [4, 0],
    "lineno": 1,
    "node": "914fa752cdea87777ac1a8d5c858b0c736218f6c",
    "path": "port",
    "rev": 4,
    "user": "spam"
   },
   {
    "date": [3, 0],
    "lineno": 1,
    "node": "95040cfd017d658c536071c6290230a613c4c2a6",
    "path": "port",
    "rev": 3,
    "user": "eggs"
   },
   {
    "date": [2, 0],
    "lineno": 1,
    "node": "3b325e3481a1f07435d81dfdbfa434d9a0245b47",
    "path": "port",
    "rev": 2,
    "user": "spam"
   },
   {
    "date": [1, 0],
    "lineno": 1,
    "node": "8b20f75c158513ff5ac80bd0e5219bfb6f0eb587",
    "path": "port",
    "rev": 1,
    "user": "eggs"
   },
   {
    "date": [0, 0],
    "lineno": 1,
    "node": "f31323c9217050ba245ee8b537c713ec2e8ab226",
    "path": "port",
    "rev": 0,
    "user": "spam"
   }
  ]

diff of each revision for reference

  $ hg log -p -T'== rev: {rev} ==\n'
  == rev: 4 ==
  diff -r 95040cfd017d -r 914fa752cdea port
  --- a/port	Thu Jan 01 00:00:03 1970 +0000
  +++ b/port	Thu Jan 01 00:00:04 1970 +0000
  @@ -1,4 +1,3 @@
   export
   vaportight
   import/export
  -import/export
  
  == rev: 3 ==
  diff -r 3b325e3481a1 -r 95040cfd017d port
  --- a/port	Thu Jan 01 00:00:02 1970 +0000
  +++ b/port	Thu Jan 01 00:00:03 1970 +0000
  @@ -1,3 +1,4 @@
   export
   vaportight
   import/export
  +import/export
  
  == rev: 2 ==
  diff -r 8b20f75c1585 -r 3b325e3481a1 port
  --- a/port	Thu Jan 01 00:00:01 1970 +0000
  +++ b/port	Thu Jan 01 00:00:02 1970 +0000
  @@ -1,2 +1,3 @@
  -import
   export
  +vaportight
  +import/export
  
  == rev: 1 ==
  diff -r f31323c92170 -r 8b20f75c1585 port
  --- a/port	Thu Jan 01 00:00:00 1970 +0000
  +++ b/port	Thu Jan 01 00:00:01 1970 +0000
  @@ -1,1 +1,2 @@
   import
  +export
  
  == rev: 0 ==
  diff -r 000000000000 -r f31323c92170 port
  --- /dev/null	Thu Jan 01 00:00:00 1970 +0000
  +++ b/port	Thu Jan 01 00:00:00 1970 +0000
  @@ -0,0 +1,1 @@
  +import
  

all

  $ hg grep --traceback --all -nu port port
  port:4:4:-:spam:import/export
  port:3:4:+:eggs:import/export
  port:2:1:-:spam:import
  port:2:2:+:spam:vaportight
  port:2:3:+:spam:import/export
  port:1:2:+:eggs:export
  port:0:1:+:spam:import

all JSON

  $ hg grep --all -Tjson port port
  [
   {
    "change": "-",
    "date": [4, 0],
    "lineno": 4,
    "node": "914fa752cdea87777ac1a8d5c858b0c736218f6c",
    "path": "port",
    "rev": 4,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}, {"matched": false, "text": "/ex"}, {"matched": true, "text": "port"}],
    "user": "spam"
   },
   {
    "change": "+",
    "date": [3, 0],
    "lineno": 4,
    "node": "95040cfd017d658c536071c6290230a613c4c2a6",
    "path": "port",
    "rev": 3,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}, {"matched": false, "text": "/ex"}, {"matched": true, "text": "port"}],
    "user": "eggs"
   },
   {
    "change": "-",
    "date": [2, 0],
    "lineno": 1,
    "node": "3b325e3481a1f07435d81dfdbfa434d9a0245b47",
    "path": "port",
    "rev": 2,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}],
    "user": "spam"
   },
   {
    "change": "+",
    "date": [2, 0],
    "lineno": 2,
    "node": "3b325e3481a1f07435d81dfdbfa434d9a0245b47",
    "path": "port",
    "rev": 2,
    "texts": [{"matched": false, "text": "va"}, {"matched": true, "text": "port"}, {"matched": false, "text": "ight"}],
    "user": "spam"
   },
   {
    "change": "+",
    "date": [2, 0],
    "lineno": 3,
    "node": "3b325e3481a1f07435d81dfdbfa434d9a0245b47",
    "path": "port",
    "rev": 2,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}, {"matched": false, "text": "/ex"}, {"matched": true, "text": "port"}],
    "user": "spam"
   },
   {
    "change": "+",
    "date": [1, 0],
    "lineno": 2,
    "node": "8b20f75c158513ff5ac80bd0e5219bfb6f0eb587",
    "path": "port",
    "rev": 1,
    "texts": [{"matched": false, "text": "ex"}, {"matched": true, "text": "port"}],
    "user": "eggs"
   },
   {
    "change": "+",
    "date": [0, 0],
    "lineno": 1,
    "node": "f31323c9217050ba245ee8b537c713ec2e8ab226",
    "path": "port",
    "rev": 0,
    "texts": [{"matched": false, "text": "im"}, {"matched": true, "text": "port"}],
    "user": "spam"
   }
  ]

other

  $ hg grep -r tip:0 -l port port
  port:4
  port:3
  port:2
  port:1
  port:0
  $ hg grep -r tip:0 import port
  port:4:import/export
  port:3:import/export
  port:3:import/export
  port:2:import/export
  port:1:import
  port:0:import

  $ hg cp port port2
  $ hg commit -m 4 -u spam -d '5 0'

follow

  $ hg grep -r tip:0 --traceback -f 'import\n\Z' port2
  [1]
  $ echo deport >> port2
  $ hg commit -m 5 -u eggs -d '6 0'
  $ hg grep -f --all -nu port port2
  port2:6:4:+:eggs:deport
  port:4:4:-:spam:import/export
  port:3:4:+:eggs:import/export
  port:2:1:-:spam:import
  port:2:2:+:spam:vaportight
  port:2:3:+:spam:import/export
  port:1:2:+:eggs:export
  port:0:1:+:spam:import

  $ hg up -q null
  $ hg grep -r 'reverse(:.)' -f port
  port:0:import

Test wdir
(at least, this shouldn't crash)

  $ hg up -q
  $ echo wport >> port2
  $ hg stat
  M port2
  $ hg grep -r 'wdir()' port
  port:2147483647:export
  port:2147483647:vaportight
  port:2147483647:import/export
  port2:2147483647:export
  port2:2147483647:vaportight
  port2:2147483647:import/export
  port2:2147483647:deport
  port2:2147483647:wport

  $ cd ..
  $ hg init t2
  $ cd t2
  $ hg grep -r tip:0 foobar foo
  [1]
  $ hg grep -r tip:0 foobar
  [1]
  $ echo blue >> color
  $ echo black >> color
  $ hg add color
  $ hg ci -m 0
  $ echo orange >> color
  $ hg ci -m 1
  $ echo black > color
  $ hg ci -m 2
  $ echo orange >> color
  $ echo blue >> color
  $ hg ci -m 3
  $ hg grep -r tip:0 orange
  color:3:orange
  color:1:orange
  $ hg grep --all orange
  color:3:+:orange
  color:2:-:orange
  color:1:+:orange
  $ hg grep --diff orange --color=debug
  [grep.filename|color][grep.sep|:][grep.rev|3][grep.sep|:][grep.inserted grep.change|+][grep.sep|:][grep.match|orange]
  [grep.filename|color][grep.sep|:][grep.rev|2][grep.sep|:][grep.deleted grep.change|-][grep.sep|:][grep.match|orange]
  [grep.filename|color][grep.sep|:][grep.rev|1][grep.sep|:][grep.inserted grep.change|+][grep.sep|:][grep.match|orange]

  $ hg grep --diff orange --color=yes
  \x1b[0;35mcolor\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m3\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;32;1m+\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;31;1morange\x1b[0m (esc)
  \x1b[0;35mcolor\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m2\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;31;1m-\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;31;1morange\x1b[0m (esc)
  \x1b[0;35mcolor\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;34m1\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;32;1m+\x1b[0m\x1b[0;36m:\x1b[0m\x1b[0;31;1morange\x1b[0m (esc)

  $ hg grep --diff orange
  color:3:+:orange
  color:2:-:orange
  color:1:+:orange

revset predicate for "grep --diff"

  $ hg log -qr 'diffcontains("re:^bl...$")'
  0:203191eb5e21
  $ hg log -qr 'diffcontains("orange")'
  1:7c585a21e0d1
  2:11bd8bc8d653
  3:e0116d3829f8
  $ hg log -qr '2:0 & diffcontains("orange")'
  2:11bd8bc8d653
  1:7c585a21e0d1

test substring match: '^' should only match at the beginning

  $ hg grep -r tip:0 '^.' --config extensions.color= --color debug
  [grep.filename|color][grep.sep|:][grep.rev|3][grep.sep|:][grep.match|b]lack
  [grep.filename|color][grep.sep|:][grep.rev|3][grep.sep|:][grep.match|o]range
  [grep.filename|color][grep.sep|:][grep.rev|3][grep.sep|:][grep.match|b]lue
  [grep.filename|color][grep.sep|:][grep.rev|2][grep.sep|:][grep.match|b]lack
  [grep.filename|color][grep.sep|:][grep.rev|1][grep.sep|:][grep.match|b]lue
  [grep.filename|color][grep.sep|:][grep.rev|1][grep.sep|:][grep.match|b]lack
  [grep.filename|color][grep.sep|:][grep.rev|1][grep.sep|:][grep.match|o]range
  [grep.filename|color][grep.sep|:][grep.rev|0][grep.sep|:][grep.match|b]lue
  [grep.filename|color][grep.sep|:][grep.rev|0][grep.sep|:][grep.match|b]lack

match in last "line" without newline

  $ "$PYTHON" -c 'fp = open("noeol", "wb"); fp.write(b"no infinite loop"); fp.close();'
  $ hg ci -Amnoeol
  adding noeol
  $ hg grep -r tip:0 loop
  noeol:4:no infinite loop

  $ cd ..

Issue685: traceback in grep -r after rename

Got a traceback when using grep on a single
revision with renamed files.

  $ hg init issue685
  $ cd issue685
  $ echo octarine > color
  $ hg ci -Amcolor
  adding color
  $ hg rename color colour
  $ hg ci -Am rename
  $ hg grep -r tip:0 octarine
  colour:1:octarine
  color:0:octarine

Used to crash here

  $ hg grep -r 1 octarine
  colour:1:octarine
  $ cd ..


Issue337: test that grep follows parent-child relationships instead
of just using revision numbers.

  $ hg init issue337
  $ cd issue337

  $ echo white > color
  $ hg commit -A -m "0 white"
  adding color

  $ echo red > color
  $ hg commit -A -m "1 red"

  $ hg update 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo black > color
  $ hg commit -A -m "2 black"
  created new head

  $ hg update --clean 1
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo blue > color
  $ hg commit -A -m "3 blue"

  $ hg grep --all red
  color:3:-:red
  color:1:+:red

  $ hg grep --diff red
  color:3:-:red
  color:1:+:red

Issue3885: test that changing revision order does not alter the
revisions printed, just their order.

  $ hg grep --all red -r "all()"
  color:1:+:red
  color:3:-:red

  $ hg grep --all red -r "reverse(all())"
  color:3:-:red
  color:1:+:red

  $ hg grep --diff red -r "all()"
  color:1:+:red
  color:3:-:red

  $ hg grep --diff red -r "reverse(all())"
  color:3:-:red
  color:1:+:red

  $ cd ..

  $ hg init a
  $ cd a
  $ cp "$TESTDIR/binfile.bin" .
  $ hg add binfile.bin
  $ hg ci -m 'add binfile.bin'
  $ hg grep "MaCam" --all
  binfile.bin:0:+: Binary file matches

  $ hg grep "MaCam" --diff
  binfile.bin:0:+: Binary file matches

  $ cd ..

Moved line may not be collected by "grep --diff" since it first filters
the contents to be diffed by the pattern. (i.e.
"diff <(grep pat a) <(grep pat b)", not "diff a b | grep pat".)
This is much faster than generating full diff per revision.

  $ hg init moved-line
  $ cd moved-line
  $ cat <<'EOF' > a
  > foo
  > bar
  > baz
  > EOF
  $ hg ci -Am initial
  adding a
  $ cat <<'EOF' > a
  > bar
  > baz
  > foo
  > EOF
  $ hg ci -m reorder

  $ hg diff -c 1
  diff -r a593cc55e81b -r 69789a3b6e80 a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,3 +1,3 @@
  -foo
   bar
   baz
  +foo

 can't find the move of "foo" at the revision 1:

  $ hg grep --diff foo -r1
  [1]

 "bar" isn't moved at the revisoin 1:

  $ hg grep --diff bar -r1
  [1]

  $ cd ..

Test for showing working of allfiles flag

  $ hg init sng
  $ cd sng
  $ echo "unmod" >> um
  $ echo old > old
  $ hg ci -q -A -m "adds unmod to um"
  $ echo "something else" >> new
  $ hg ci -A -m "second commit"
  adding new
  $ hg grep -r "." "unmod"
  um:1:unmod

Existing tracked files in the working directory are searched by default

  $ echo modified >> new
  $ echo 'added' > added; hg add added
  $ echo 'added, missing' > added-missing; hg add added-missing; rm added-missing
  $ echo 'untracked' > untracked
  $ hg rm old
  $ hg grep ''
  added:added
  new:something else
  new:modified
  um:unmod

#if symlink
Grepping a symlink greps its destination

  $ rm -f added; ln -s symlink-added added
  $ hg grep '' | grep added
  added:symlink-added

But we reject symlinks as directories components of a tracked file as
usual:

  $ mkdir dir; touch dir/f; hg add dir/f
  $ rm -rf dir; ln -s / dir
  $ hg grep ''
  abort: path 'dir/f' traverses symbolic link 'dir'
  [255]
#endif

But we can search files from some other revision with -rREV

  $ hg grep -r. mod
  um:1:unmod

  $ hg grep --diff mod
  um:0:+:unmod

  $ cd ..

Change Default of grep by ui.tweakdefaults, that is, the files not in current
working directory should not be grepp-ed on

  $ hg init ab
  $ cd ab
  $ cat <<'EOF' >> .hg/hgrc
  > [ui]
  > tweakdefaults = True
  > EOF
  $ echo "some text">>file1
  $ hg add file1
  $ hg commit -m "adds file1"
  $ hg mv file1 file2

wdir revision is hidden by default:

  $ hg grep "some"
  file2:some text

but it should be available in template dict:

  $ hg grep "some" -Tjson
  [
   {
    "date": [0, 0],
    "lineno": 1,
    "node": "ffffffffffffffffffffffffffffffffffffffff",
    "path": "file2",
    "rev": 2147483647,
    "texts": [{"matched": true, "text": "some"}, {"matched": false, "text": " text"}],
    "user": "test"
   }
  ]

  $ cd ..

test -rMULTIREV

  $ cd sng
  $ hg rm um
  $ hg commit -m "deletes um"
  $ hg grep -r "0:2" "unmod"
  um:0:unmod
  um:1:unmod
  $ hg grep -r "0:2" "unmod" um
  um:0:unmod
  um:1:unmod
  $ hg grep -r "0:2" "unmod" "glob:**/um" # Check that patterns also work
  um:0:unmod
  um:1:unmod
  $ cd ..

--follow with/without --diff and/or paths
-----------------------------------------

For each test case, we compare the history traversal of "hg log",
"hg grep --diff", and "hg grep" (--all-files).

"hg grep --diff" should traverse the log in the same way as "hg log".
"hg grep" (--all-files) is slightly different in that it includes
unmodified changes.

  $ hg init follow
  $ cd follow

  $ cat <<'EOF' >> .hg/hgrc
  > [command-templates]
  > log = '{rev}: {join(files % "{status} {path}", ", ")}\n'
  > EOF

  $ for f in add0 add0-mod1 add0-rm1 add0-mod2 add0-rm2 add0-mod3 add0-mod4 add0-rm4; do
  > echo data0 >> $f
  > done
  $ hg ci -qAm0

  $ hg cp add0 add0-cp1
  $ hg cp add0 add0-cp1-mod1
  $ hg cp add0 add0-cp1-mod1-rm3
  $ hg rm add0-rm1
  $ for f in *mod1*; do
  > echo data1 >> $f
  > done
  $ hg ci -qAm1

  $ hg update -q 0
  $ hg cp add0 add0-cp2
  $ hg cp add0 add0-cp2-mod2
  $ hg rm add0-rm2
  $ for f in *mod2*; do
  > echo data2 >> $f
  > done
  $ hg ci -qAm2

  $ hg update -q 1
  $ hg cp add0-cp1 add0-cp1-cp3
  $ hg cp add0-cp1-mod1 add0-cp1-mod1-cp3-mod3
  $ hg rm add0-cp1-mod1-rm3
  $ for f in *mod3*; do
  > echo data3 >> $f
  > done
  $ hg ci -qAm3

  $ hg cp add0 add0-cp4
  $ hg cp add0 add0-cp4-mod4
  $ hg rm add0-rm4
  $ for f in *mod4*; do
  > echo data4 >> $f
  > done

  $ hg log -Gr':wdir()'
  o  2147483647: A add0-cp4, A add0-cp4-mod4, M add0-mod4, R add0-rm4
  |
  @  3: A add0-cp1-cp3, A add0-cp1-mod1-cp3-mod3, R add0-cp1-mod1-rm3, M add0-mod3
  |
  | o  2: A add0-cp2, A add0-cp2-mod2, M add0-mod2, R add0-rm2
  | |
  o |  1: A add0-cp1, A add0-cp1-mod1, A add0-cp1-mod1-rm3, M add0-mod1, R add0-rm1
  |/
  o  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4
  

follow revision history from wdir parent:

  $ hg log -f
  3: A add0-cp1-cp3, A add0-cp1-mod1-cp3-mod3, R add0-cp1-mod1-rm3, M add0-mod3
  1: A add0-cp1, A add0-cp1-mod1, A add0-cp1-mod1-rm3, M add0-mod1, R add0-rm1
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -f data
  add0-cp1-mod1-cp3-mod3:3:+:data3
  add0-mod3:3:+:data3
  add0-cp1-mod1:1:+:data1
  add0-cp1-mod1-rm3:1:+:data1
  add0-mod1:1:+:data1
  add0:0:+:data0
  add0-mod1:0:+:data0
  add0-mod2:0:+:data0
  add0-mod3:0:+:data0
  add0-mod4:0:+:data0
  add0-rm1:0:+:data0
  add0-rm2:0:+:data0
  add0-rm4:0:+:data0

  $ hg grep -f data
  add0:3:data0
  add0-cp1:3:data0
  add0-cp1-cp3:3:data0
  add0-cp1-mod1:3:data0
  add0-cp1-mod1:3:data1
  add0-cp1-mod1-cp3-mod3:3:data0
  add0-cp1-mod1-cp3-mod3:3:data1
  add0-cp1-mod1-cp3-mod3:3:data3
  add0-mod1:3:data0
  add0-mod1:3:data1
  add0-mod2:3:data0
  add0-mod3:3:data0
  add0-mod3:3:data3
  add0-mod4:3:data0
  add0-rm2:3:data0
  add0-rm4:3:data0
  add0:1:data0
  add0-cp1:1:data0
  add0-cp1-mod1:1:data0
  add0-cp1-mod1:1:data1
  add0-cp1-mod1-rm3:1:data0
  add0-cp1-mod1-rm3:1:data1
  add0-mod1:1:data0
  add0-mod1:1:data1
  add0-mod2:1:data0
  add0-mod3:1:data0
  add0-mod4:1:data0
  add0-rm2:1:data0
  add0-rm4:1:data0
  add0:0:data0
  add0-mod1:0:data0
  add0-mod2:0:data0
  add0-mod3:0:data0
  add0-mod4:0:data0
  add0-rm1:0:data0
  add0-rm2:0:data0
  add0-rm4:0:data0

follow revision history from specified revision:

  $ hg log -fr2
  2: A add0-cp2, A add0-cp2-mod2, M add0-mod2, R add0-rm2
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr2 data
  add0-cp2-mod2:2:+:data2
  add0-mod2:2:+:data2
  add0:0:+:data0
  add0-mod1:0:+:data0
  add0-mod2:0:+:data0
  add0-mod3:0:+:data0
  add0-mod4:0:+:data0
  add0-rm1:0:+:data0
  add0-rm2:0:+:data0
  add0-rm4:0:+:data0

  $ hg grep -fr2 data
  add0:2:data0
  add0-cp2:2:data0
  add0-cp2-mod2:2:data0
  add0-cp2-mod2:2:data2
  add0-mod1:2:data0
  add0-mod2:2:data0
  add0-mod2:2:data2
  add0-mod3:2:data0
  add0-mod4:2:data0
  add0-rm1:2:data0
  add0-rm4:2:data0
  add0:0:data0
  add0-mod1:0:data0
  add0-mod2:0:data0
  add0-mod3:0:data0
  add0-mod4:0:data0
  add0-rm1:0:data0
  add0-rm2:0:data0
  add0-rm4:0:data0

follow revision history from wdir:

  $ hg log -fr'wdir()'
  2147483647: A add0-cp4, A add0-cp4-mod4, M add0-mod4, R add0-rm4
  3: A add0-cp1-cp3, A add0-cp1-mod1-cp3-mod3, R add0-cp1-mod1-rm3, M add0-mod3
  1: A add0-cp1, A add0-cp1-mod1, A add0-cp1-mod1-rm3, M add0-mod1, R add0-rm1
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

 BROKEN: should not abort because of removed file
  $ hg grep --diff -fr'wdir()' data
  add0-cp4-mod4:2147483647:+:data4
  add0-mod4:2147483647:+:data4
  add0-rm4:2147483647:-:abort: add0-rm4@None: not found in manifest
  [50]

  $ hg grep -fr'wdir()' data
  add0:2147483647:data0
  add0-cp1:2147483647:data0
  add0-cp1-cp3:2147483647:data0
  add0-cp1-mod1:2147483647:data0
  add0-cp1-mod1:2147483647:data1
  add0-cp1-mod1-cp3-mod3:2147483647:data0
  add0-cp1-mod1-cp3-mod3:2147483647:data1
  add0-cp1-mod1-cp3-mod3:2147483647:data3
  add0-cp4:2147483647:data0
  add0-cp4-mod4:2147483647:data0
  add0-cp4-mod4:2147483647:data4
  add0-mod1:2147483647:data0
  add0-mod1:2147483647:data1
  add0-mod2:2147483647:data0
  add0-mod3:2147483647:data0
  add0-mod3:2147483647:data3
  add0-mod4:2147483647:data0
  add0-mod4:2147483647:data4
  add0-rm2:2147483647:data0
  add0:3:data0
  add0-cp1:3:data0
  add0-cp1-cp3:3:data0
  add0-cp1-mod1:3:data0
  add0-cp1-mod1:3:data1
  add0-cp1-mod1-cp3-mod3:3:data0
  add0-cp1-mod1-cp3-mod3:3:data1
  add0-cp1-mod1-cp3-mod3:3:data3
  add0-mod1:3:data0
  add0-mod1:3:data1
  add0-mod2:3:data0
  add0-mod3:3:data0
  add0-mod3:3:data3
  add0-mod4:3:data0
  add0-rm2:3:data0
  add0-rm4:3:data0
  add0:1:data0
  add0-cp1:1:data0
  add0-cp1-mod1:1:data0
  add0-cp1-mod1:1:data1
  add0-cp1-mod1-rm3:1:data0
  add0-cp1-mod1-rm3:1:data1
  add0-mod1:1:data0
  add0-mod1:1:data1
  add0-mod2:1:data0
  add0-mod3:1:data0
  add0-mod4:1:data0
  add0-rm2:1:data0
  add0-rm4:1:data0
  add0:0:data0
  add0-mod1:0:data0
  add0-mod2:0:data0
  add0-mod3:0:data0
  add0-mod4:0:data0
  add0-rm1:0:data0
  add0-rm2:0:data0
  add0-rm4:0:data0

follow revision history from multiple revisions:

  $ hg log -fr'1+2'
  2: A add0-cp2, A add0-cp2-mod2, M add0-mod2, R add0-rm2
  1: A add0-cp1, A add0-cp1-mod1, A add0-cp1-mod1-rm3, M add0-mod1, R add0-rm1
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr'1+2' data
  add0-cp2-mod2:2:+:data2
  add0-mod2:2:+:data2
  add0-cp1-mod1:1:+:data1
  add0-cp1-mod1-rm3:1:+:data1
  add0-mod1:1:+:data1
  add0:0:+:data0
  add0-mod1:0:+:data0
  add0-mod2:0:+:data0
  add0-mod3:0:+:data0
  add0-mod4:0:+:data0
  add0-rm1:0:+:data0
  add0-rm2:0:+:data0
  add0-rm4:0:+:data0

  $ hg grep -fr'1+2' data
  add0:2:data0
  add0-cp2:2:data0
  add0-cp2-mod2:2:data0
  add0-cp2-mod2:2:data2
  add0-mod1:2:data0
  add0-mod2:2:data0
  add0-mod2:2:data2
  add0-mod3:2:data0
  add0-mod4:2:data0
  add0-rm1:2:data0
  add0-rm4:2:data0
  add0:1:data0
  add0-cp1:1:data0
  add0-cp1-mod1:1:data0
  add0-cp1-mod1:1:data1
  add0-cp1-mod1-rm3:1:data0
  add0-cp1-mod1-rm3:1:data1
  add0-mod1:1:data0
  add0-mod1:1:data1
  add0-mod2:1:data0
  add0-mod3:1:data0
  add0-mod4:1:data0
  add0-rm2:1:data0
  add0-rm4:1:data0
  add0:0:data0
  add0-mod1:0:data0
  add0-mod2:0:data0
  add0-mod3:0:data0
  add0-mod4:0:data0
  add0-rm1:0:data0
  add0-rm2:0:data0
  add0-rm4:0:data0

follow file history from wdir parent, unmodified in wdir:

  $ hg log -f add0-mod3
  3: A add0-cp1-cp3, A add0-cp1-mod1-cp3-mod3, R add0-cp1-mod1-rm3, M add0-mod3
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -f data add0-mod3
  add0-mod3:3:+:data3
  add0-mod3:0:+:data0

  $ hg grep -f data add0-mod3
  add0-mod3:3:data0
  add0-mod3:3:data3
  add0-mod3:1:data0
  add0-mod3:0:data0

follow file history from wdir parent, modified in wdir:

  $ hg log -f add0-mod4
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -f data add0-mod4
  add0-mod4:0:+:data0

  $ hg grep -f data add0-mod4
  add0-mod4:3:data0
  add0-mod4:1:data0
  add0-mod4:0:data0

follow file history from wdir parent, copied but unmodified:

  $ hg log -f add0-cp1-cp3
  3: A add0-cp1-cp3, A add0-cp1-mod1-cp3-mod3, R add0-cp1-mod1-rm3, M add0-mod3
  1: A add0-cp1, A add0-cp1-mod1, A add0-cp1-mod1-rm3, M add0-mod1, R add0-rm1
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -f data add0-cp1-cp3
  add0:0:+:data0

 BROKEN: should follow history across renames
  $ hg grep -f data add0-cp1-cp3
  add0-cp1-cp3:3:data0

follow file history from wdir parent, copied and modified:

  $ hg log -f add0-cp1-mod1-cp3-mod3
  3: A add0-cp1-cp3, A add0-cp1-mod1-cp3-mod3, R add0-cp1-mod1-rm3, M add0-mod3
  1: A add0-cp1, A add0-cp1-mod1, A add0-cp1-mod1-rm3, M add0-mod1, R add0-rm1
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -f data add0-cp1-mod1-cp3-mod3
  add0-cp1-mod1-cp3-mod3:3:+:data3
  add0-cp1-mod1:1:+:data1
  add0:0:+:data0

 BROKEN: should follow history across renames
  $ hg grep -f data add0-cp1-mod1-cp3-mod3
  add0-cp1-mod1-cp3-mod3:3:data0
  add0-cp1-mod1-cp3-mod3:3:data1
  add0-cp1-mod1-cp3-mod3:3:data3

follow file history from wdir parent, copied in wdir:

  $ hg log -f add0-cp4
  abort: cannot follow nonexistent file: "add0-cp4"
  [20]

  $ hg grep --diff -f data add0-cp4
  abort: cannot follow nonexistent file: "add0-cp4"
  [20]

 BROKEN: maybe better to abort
  $ hg grep -f data add0-cp4
  [1]

follow file history from wdir parent, removed:

  $ hg log -f add0-cp1-mod1-rm3
  abort: cannot follow file not in parent revision: "add0-cp1-mod1-rm3"
  [20]

  $ hg grep --diff -f data add0-cp1-mod1-rm3
  abort: cannot follow file not in parent revision: "add0-cp1-mod1-rm3"
  [20]

 BROKEN: maybe better to abort
  $ hg grep -f data add0-cp1-mod1-rm3
  add0-cp1-mod1-rm3:1:data0
  add0-cp1-mod1-rm3:1:data1

follow file history from wdir parent (explicit), removed:

  $ hg log -fr. add0-cp1-mod1-rm3
  abort: cannot follow file not in any of the specified revisions: "add0-cp1-mod1-rm3"
  [20]

  $ hg grep --diff -fr. data add0-cp1-mod1-rm3
  abort: cannot follow file not in any of the specified revisions: "add0-cp1-mod1-rm3"
  [20]

 BROKEN: should abort
  $ hg grep -fr. data add0-cp1-mod1-rm3
  add0-cp1-mod1-rm3:1:data0
  add0-cp1-mod1-rm3:1:data1

follow file history from wdir parent, removed in wdir:

  $ hg log -f add0-rm4
  abort: cannot follow file not in parent revision: "add0-rm4"
  [20]

  $ hg grep --diff -f data add0-rm4
  abort: cannot follow file not in parent revision: "add0-rm4"
  [20]

 BROKEN: should abort
  $ hg grep -f data add0-rm4
  add0-rm4:3:data0
  add0-rm4:1:data0
  add0-rm4:0:data0

follow file history from wdir parent (explicit), removed in wdir:

  $ hg log -fr. add0-rm4
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr. data add0-rm4
  add0-rm4:0:+:data0

  $ hg grep -fr. data add0-rm4
  add0-rm4:3:data0
  add0-rm4:1:data0
  add0-rm4:0:data0

follow file history from wdir parent, multiple files:

  $ hg log -f add0-mod3 add0-cp1-mod1
  3: A add0-cp1-cp3, A add0-cp1-mod1-cp3-mod3, R add0-cp1-mod1-rm3, M add0-mod3
  1: A add0-cp1, A add0-cp1-mod1, A add0-cp1-mod1-rm3, M add0-mod1, R add0-rm1
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -f data add0-mod3 add0-cp1-mod1
  add0-mod3:3:+:data3
  add0-cp1-mod1:1:+:data1
  add0:0:+:data0
  add0-mod3:0:+:data0

 BROKEN: should follow history across renames
  $ hg grep -f data add0-mod3 add0-cp1-mod1
  add0-cp1-mod1:3:data0
  add0-cp1-mod1:3:data1
  add0-mod3:3:data0
  add0-mod3:3:data3
  add0-cp1-mod1:1:data0
  add0-cp1-mod1:1:data1
  add0-mod3:1:data0
  add0-mod3:0:data0

follow file history from specified revision, modified:

  $ hg log -fr2 add0-mod2
  2: A add0-cp2, A add0-cp2-mod2, M add0-mod2, R add0-rm2
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr2 data add0-mod2
  add0-mod2:2:+:data2
  add0-mod2:0:+:data0

  $ hg grep -fr2 data add0-mod2
  add0-mod2:2:data0
  add0-mod2:2:data2
  add0-mod2:0:data0

follow file history from specified revision, copied but unmodified:

  $ hg log -fr2 add0-cp2
  2: A add0-cp2, A add0-cp2-mod2, M add0-mod2, R add0-rm2
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr2 data add0-cp2
  add0:0:+:data0

 BROKEN: should follow history across renames
  $ hg grep -fr2 data add0-cp2
  add0-cp2:2:data0

follow file history from specified revision, copied and modified:

  $ hg log -fr2 add0-cp2-mod2
  2: A add0-cp2, A add0-cp2-mod2, M add0-mod2, R add0-rm2
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr2 data add0-cp2-mod2
  add0-cp2-mod2:2:+:data2
  add0:0:+:data0

 BROKEN: should follow history across renames
  $ hg grep -fr2 data add0-cp2-mod2
  add0-cp2-mod2:2:data0
  add0-cp2-mod2:2:data2

follow file history from specified revision, removed:

  $ hg log -fr2 add0-rm2
  abort: cannot follow file not in any of the specified revisions: "add0-rm2"
  [20]

  $ hg grep --diff -fr2 data add0-rm2
  abort: cannot follow file not in any of the specified revisions: "add0-rm2"
  [20]

 BROKEN: should abort
  $ hg grep -fr2 data add0-rm2
  add0-rm2:0:data0

follow file history from specified revision, multiple files:

  $ hg log -fr2 add0-cp2 add0-mod2
  2: A add0-cp2, A add0-cp2-mod2, M add0-mod2, R add0-rm2
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr2 data add0-cp2 add0-mod2
  add0-mod2:2:+:data2
  add0:0:+:data0
  add0-mod2:0:+:data0

 BROKEN: should follow history across renames
  $ hg grep -fr2 data add0-cp2 add0-mod2
  add0-cp2:2:data0
  add0-mod2:2:data0
  add0-mod2:2:data2
  add0-mod2:0:data0

follow file history from wdir, unmodified:

  $ hg log -fr'wdir()' add0-mod3
  2147483647: A add0-cp4, A add0-cp4-mod4, M add0-mod4, R add0-rm4
  3: A add0-cp1-cp3, A add0-cp1-mod1-cp3-mod3, R add0-cp1-mod1-rm3, M add0-mod3
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr'wdir()' data add0-mod3
  add0-mod3:3:+:data3
  add0-mod3:0:+:data0

  $ hg grep -fr'wdir()' data add0-mod3
  add0-mod3:2147483647:data0
  add0-mod3:2147483647:data3
  add0-mod3:3:data0
  add0-mod3:3:data3
  add0-mod3:1:data0
  add0-mod3:0:data0

follow file history from wdir, modified:

  $ hg log -fr'wdir()' add0-mod4
  2147483647: A add0-cp4, A add0-cp4-mod4, M add0-mod4, R add0-rm4
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr'wdir()' data add0-mod4
  add0-mod4:2147483647:+:data4
  add0-mod4:0:+:data0

  $ hg grep -fr'wdir()' data add0-mod4
  add0-mod4:2147483647:data0
  add0-mod4:2147483647:data4
  add0-mod4:3:data0
  add0-mod4:1:data0
  add0-mod4:0:data0

follow file history from wdir, copied but unmodified:

  $ hg log -fr'wdir()' add0-cp4
  2147483647: A add0-cp4, A add0-cp4-mod4, M add0-mod4, R add0-rm4
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr'wdir()' data add0-cp4
  add0:0:+:data0

 BROKEN: should follow history across renames
  $ hg grep -fr'wdir()' data add0-cp4
  add0-cp4:2147483647:data0

follow file history from wdir, copied and modified:

  $ hg log -fr'wdir()' add0-cp4-mod4
  2147483647: A add0-cp4, A add0-cp4-mod4, M add0-mod4, R add0-rm4
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr'wdir()' data add0-cp4-mod4
  add0-cp4-mod4:2147483647:+:data4
  add0:0:+:data0

 BROKEN: should follow history across renames
  $ hg grep -fr'wdir()' data add0-cp4-mod4
  add0-cp4-mod4:2147483647:data0
  add0-cp4-mod4:2147483647:data4

follow file history from wdir, multiple files:

  $ hg log -fr'wdir()' add0-cp4 add0-mod4 add0-mod3
  2147483647: A add0-cp4, A add0-cp4-mod4, M add0-mod4, R add0-rm4
  3: A add0-cp1-cp3, A add0-cp1-mod1-cp3-mod3, R add0-cp1-mod1-rm3, M add0-mod3
  0: A add0, A add0-mod1, A add0-mod2, A add0-mod3, A add0-mod4, A add0-rm1, A add0-rm2, A add0-rm4

  $ hg grep --diff -fr'wdir()' data add0-cp4 add0-mod4 add0-mod3
  add0-mod4:2147483647:+:data4
  add0-mod3:3:+:data3
  add0:0:+:data0
  add0-mod3:0:+:data0
  add0-mod4:0:+:data0

 BROKEN: should follow history across renames
  $ hg grep -fr'wdir()' data add0-cp4 add0-mod4 add0-mod3
  add0-cp4:2147483647:data0
  add0-mod3:2147483647:data0
  add0-mod3:2147483647:data3
  add0-mod4:2147483647:data0
  add0-mod4:2147483647:data4
  add0-mod3:3:data0
  add0-mod3:3:data3
  add0-mod4:3:data0
  add0-mod3:1:data0
  add0-mod4:1:data0
  add0-mod3:0:data0
  add0-mod4:0:data0

  $ cd ..

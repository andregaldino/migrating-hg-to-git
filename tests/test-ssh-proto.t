#require no-chg

persistent-nodemap is not enabled by default. It is not relevant for this test so disable it.

  $ cat << EOF >> $HGRCPATH
  > [format]
  > use-persistent-nodemap = no
  > EOF

Helper function to run protocol tests against multiple protocol versions.
This is easier than using #testcases because managing differences between
protocols with inline conditional output is hard to read.

  $ debugwireproto() {
  >   commands=`cat -`
  >   echo 'testing ssh1'
  >   echo "${commands}" | hg --verbose debugwireproto --localssh
  > }

  $ cat >> $HGRCPATH << EOF
  > [devel]
  > debug.peer-request = true
  > [extensions]
  > sshprotoext = $TESTDIR/sshprotoext.py
  > EOF

  $ hg init server
  $ cd server
  $ echo 0 > foo
  $ hg -q add foo
  $ hg commit -m initial

A no-op connection performs a handshake

  $ hg debugwireproto --localssh << EOF
  > EOF
  creating ssh peer from handshake results

Raw peers don't perform any activity

  $ hg debugwireproto --localssh --peer raw << EOF
  > EOF
  using raw connection to peer
  $ hg debugwireproto --localssh --peer ssh1 << EOF
  > EOF
  creating ssh peer for wire protocol version 1

Test a normal behaving server, for sanity

  $ cd ..

  $ hg --debug debugpeer ssh://user@dummy/server
  running .* ".*[/\\]dummyssh" ['"]user@dummy['"] ['"]hg -R server serve --stdio['"] (re)
  devel-peer-request: hello+between
  devel-peer-request:   pairs: 81 bytes
  sending hello command
  sending between command
  remote: \d+ (re)
  remote: capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (re)
  remote: 1
  devel-peer-request: protocaps
  devel-peer-request:   caps: * bytes (glob)
  sending protocaps command
  url: ssh://user@dummy/server
  local: no
  pushable: yes

Server should answer the "hello" command in isolation

  $ hg -R server debugwireproto --localssh --peer raw << EOF
  > raw
  >     hello\n
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)

`hg debugserve --sshstdio` works

  $ cd server
  $ hg debugserve --sshstdio << EOF
  > hello
  > EOF
  \d+ (re)
  capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (re)

I/O logging works

  $ hg debugserve --sshstdio --logiofd 1 << EOF
  > hello
  > EOF
  e> flush() -> None
  o> write(4) -> 4:
  o>     \d+\\n (re)
  o> write\(\d+\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  \d+ (re)
  capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (re)
  o> flush() -> None

  $ hg debugserve --sshstdio --logiofile $TESTTMP/io << EOF
  > hello
  > EOF
  \d+ (re)
  capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (re)

  $ cat $TESTTMP/io
  e> flush() -> None
  o> write(4) -> 4:
  o>     \d+\\n (re)
  o> write\(\d+\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> flush() -> None

  $ cd ..

>=0.9.1 clients send a "hello" + "between" for the null range as part of handshake.
Server should reply with capabilities and should send "1\n\n" as a successful
reply with empty response to the "between".

  $ hg -R server debugwireproto --localssh --peer raw << EOF
  > raw
  >     hello\n
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n

SSH banner is not printed by default, ignored by clients

  $ SSHSERVERMODE=banner hg debugpeer ssh://user@dummy/server
  url: ssh://user@dummy/server
  local: no
  pushable: yes

--debug will print the banner

  $ SSHSERVERMODE=banner hg --debug debugpeer ssh://user@dummy/server
  running .* ".*[/\\]dummyssh" ['"]user@dummy['"] ['"]hg -R server serve --stdio['"] (re)
  devel-peer-request: hello+between
  devel-peer-request:   pairs: 81 bytes
  sending hello command
  sending between command
  remote: banner: line 0
  remote: banner: line 1
  remote: banner: line 2
  remote: banner: line 3
  remote: banner: line 4
  remote: banner: line 5
  remote: banner: line 6
  remote: banner: line 7
  remote: banner: line 8
  remote: banner: line 9
  remote: \d+ (re)
  remote: capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (re)
  remote: 1
  devel-peer-request: protocaps
  devel-peer-request:   caps: * bytes (glob)
  sending protocaps command
  url: ssh://user@dummy/server
  local: no
  pushable: yes

And test the banner with the raw protocol

  $ SSHSERVERMODE=banner hg -R server debugwireproto --localssh --peer raw << EOF
  > raw
  >     hello\n
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 15:
  o>     banner: line 0\n
  o> readline() -> 15:
  o>     banner: line 1\n
  o> readline() -> 15:
  o>     banner: line 2\n
  o> readline() -> 15:
  o>     banner: line 3\n
  o> readline() -> 15:
  o>     banner: line 4\n
  o> readline() -> 15:
  o>     banner: line 5\n
  o> readline() -> 15:
  o>     banner: line 6\n
  o> readline() -> 15:
  o>     banner: line 7\n
  o> readline() -> 15:
  o>     banner: line 8\n
  o> readline() -> 15:
  o>     banner: line 9\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n

Connecting to a <0.9.1 server that doesn't support the hello command.
The client should refuse, as we dropped support for connecting to such
servers.

  $ SSHSERVERMODE=no-hello hg --debug debugpeer ssh://user@dummy/server
  running .* ".*[/\\]dummyssh" ['"]user@dummy['"] ['"]hg -R server serve --stdio['"] (re)
  devel-peer-request: hello+between
  devel-peer-request:   pairs: 81 bytes
  sending hello command
  sending between command
  remote: 0
  remote: 1
  abort: no suitable response from remote hg
  [255]

Sending an unknown command to the server results in an empty response to that command

  $ hg -R server debugwireproto --localssh --peer raw << EOF
  > raw
  >     pre-hello\n
  > readline
  > raw
  >     hello\n
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(10) -> 10:
  i>     pre-hello\n
  o> readline() -> 2:
  o>     0\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n

  $ hg --config sshpeer.mode=extra-handshake-commands --config sshpeer.handshake-mode=pre-no-args --debug debugpeer ssh://user@dummy/server
  running .* ".*[/\\]dummyssh" ['"]user@dummy['"] ['"]hg -R server serve --stdio['"] (re)
  sending no-args command
  devel-peer-request: hello+between
  devel-peer-request:   pairs: 81 bytes
  sending hello command
  sending between command
  remote: 0
  remote: \d+ (re)
  remote: capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (re)
  remote: 1
  devel-peer-request: protocaps
  devel-peer-request:   caps: * bytes (glob)
  sending protocaps command
  url: ssh://user@dummy/server
  local: no
  pushable: yes

Send multiple unknown commands before hello

  $ hg -R server debugwireproto --localssh --peer raw << EOF
  > raw
  >     unknown1\n
  > readline
  > raw
  >     unknown2\n
  > readline
  > raw
  >     unknown3\n
  > readline
  > raw
  >     hello\n
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(9) -> 9:
  i>     unknown1\n
  o> readline() -> 2:
  o>     0\n
  i> write(9) -> 9:
  i>     unknown2\n
  o> readline() -> 2:
  o>     0\n
  i> write(9) -> 9:
  i>     unknown3\n
  o> readline() -> 2:
  o>     0\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n

  $ hg --config sshpeer.mode=extra-handshake-commands --config sshpeer.handshake-mode=pre-multiple-no-args --debug debugpeer ssh://user@dummy/server
  running .* ".*[/\\]dummyssh" ['"]user@dummy['"] ['"]hg -R server serve --stdio['"] (re)
  sending unknown1 command
  sending unknown2 command
  sending unknown3 command
  devel-peer-request: hello+between
  devel-peer-request:   pairs: 81 bytes
  sending hello command
  sending between command
  remote: 0
  remote: 0
  remote: 0
  remote: \d+ (re)
  remote: capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (re)
  remote: 1
  devel-peer-request: protocaps
  devel-peer-request:   caps: * bytes (glob)
  sending protocaps command
  url: ssh://user@dummy/server
  local: no
  pushable: yes

Send an unknown command before hello that has arguments

  $ cd server

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     with-args\n
  >     foo 13\n
  >     value for foo\n
  >     bar 13\n
  >     value for bar\n
  > readline
  > readline
  > readline
  > readline
  > readline
  > raw
  >     hello\n
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(52) -> 52:
  i>     with-args\n
  i>     foo 13\n
  i>     value for foo\n
  i>     bar 13\n
  i>     value for bar\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n

Send an unknown command having an argument that looks numeric

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     unknown\n
  >     foo 1\n
  >     0\n
  > readline
  > readline
  > readline
  > raw
  >     hello\n
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(16) -> 16:
  i>     unknown\n
  i>     foo 1\n
  i>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     unknown\n
  >     foo 1\n
  >     1\n
  > readline
  > readline
  > readline
  > raw
  >     hello\n
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(16) -> 16:
  i>     unknown\n
  i>     foo 1\n
  i>     1\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n

When sending a dict argument value, it is serialized to
"<arg> <item count>" followed by "<key> <len>\n<value>" for each item
in the dict.

Dictionary value for unknown command

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     unknown\n
  >     dict 3\n
  >     key1 3\n
  >     foo\n
  >     key2 3\n
  >     bar\n
  >     key3 3\n
  >     baz\n
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > readline
  > raw
  >     hello\n
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(48) -> 48:
  i>     unknown\n
  i>     dict 3\n
  i>     key1 3\n
  i>     foo\n
  i>     key2 3\n
  i>     bar\n
  i>     key3 3\n
  i>     baz\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)

Incomplete dictionary send

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     unknown\n
  >     dict 3\n
  >     key1 3\n
  >     foo\n
  > readline
  > readline
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(26) -> 26:
  i>     unknown\n
  i>     dict 3\n
  i>     key1 3\n
  i>     foo\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n

Incomplete value send

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     unknown\n
  >     dict 3\n
  >     key1 3\n
  >     fo
  > readline
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(24) -> 24:
  i>     unknown\n
  i>     dict 3\n
  i>     key1 3\n
  i>     fo
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n

Send a command line with spaces

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     unknown withspace\n
  > readline
  > raw
  >     hello\n
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(18) -> 18:
  i>     unknown withspace\n
  o> readline() -> 2:
  o>     0\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     unknown with multiple spaces\n
  > readline
  > raw
  >     hello\n
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > EOF
  using raw connection to peer
  i> write(29) -> 29:
  i>     unknown with multiple spaces\n
  o> readline() -> 2:
  o>     0\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 2:
  o>     1\n

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     unknown with spaces\n
  >     key 10\n
  >     some value\n
  > readline
  > readline
  > readline
  > raw
  >     hello\n
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(38) -> 38:
  i>     unknown with spaces\n
  i>     key 10\n
  i>     some value\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(98) -> 98:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
Send an unknown command after the "between"

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     hello\n
  > readline
  > readline
  > raw
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000unknown
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  i> write(105) -> 105:
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000unknown
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n

And one with arguments

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     hello\n
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > readline
  > readline
  > raw
  >     unknown\n
  >     foo 5\n
  >     \nvalue\n
  >     bar 3\n
  >     baz\n
  > readline
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  i> write(31) -> 31:
  i>     unknown\n
  i>     foo 5\n
  i>     \n
  i>     value\n
  i>     bar 3\n
  i>     baz\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 2:
  o>     0\n
  o> readline() -> 0: 

Send a valid command before the handshake

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     heads\n
  > readline
  > raw
  >     hello\n
  >     between\n
  >     pairs 81\n
  >     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  > readline
  > readline
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(6) -> 6:
  i>     heads\n
  o> readline() -> 3:
  o>     41\n
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  o> readline() -> 41:
  o>     68986213bd4485ea51533535e3fc9e78007a711f\n
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n

And a variation that doesn't send the between command

  $ hg debugwireproto --localssh --peer raw << EOF
  > raw
  >     heads\n
  > readline
  > raw
  >     hello\n
  > readline
  > readline
  > EOF
  using raw connection to peer
  i> write(6) -> 6:
  i>     heads\n
  o> readline() -> 3:
  o>     41\n
  i> write(6) -> 6:
  i>     hello\n
  o> readline() -> 41:
  o>     68986213bd4485ea51533535e3fc9e78007a711f\n
  o> readline() -> 4:
  o>     \d+\\n (re)

  $ cd ..

Test listkeys for listing namespaces

  $ hg init empty
  $ cd empty
  $ debugwireproto << EOF
  > command listkeys
  >     namespace namespaces
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending listkeys command
  i> write(9) -> 9:
  i>     listkeys\n
  i> write(13) -> 13:
  i>     namespace 10\n
  i> write(10) -> 10: namespaces
  i> flush() -> None
  o> bufferedreadline() -> 3:
  o>     30\n
  o> bufferedread(30) -> 30:
  o>     bookmarks\t\n
  o>     namespaces\t\n
  o>     phases\t
  response: {
    b'bookmarks': b'',
    b'namespaces': b'',
    b'phases': b''
  }

  $ cd ..

Test listkeys for bookmarks

  $ hg init bookmarkrepo
  $ cd bookmarkrepo
  $ echo 0 > foo
  $ hg add foo
  $ hg -q commit -m initial
  $ echo 1 > foo
  $ hg commit -m second

With no bookmarks set

  $ debugwireproto << EOF
  > command listkeys
  >     namespace bookmarks
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending listkeys command
  i> write(9) -> 9:
  i>     listkeys\n
  i> write(12) -> 12:
  i>     namespace 9\n
  i> write(9) -> 9: bookmarks
  i> flush() -> None
  o> bufferedreadline() -> 2:
  o>     0\n
  response: {}

With a single bookmark set

  $ hg book -r 0 bookA
  $ debugwireproto << EOF
  > command listkeys
  >     namespace bookmarks
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending listkeys command
  i> write(9) -> 9:
  i>     listkeys\n
  i> write(12) -> 12:
  i>     namespace 9\n
  i> write(9) -> 9: bookmarks
  i> flush() -> None
  o> bufferedreadline() -> 3:
  o>     46\n
  o> bufferedread(46) -> 46: bookA\t68986213bd4485ea51533535e3fc9e78007a711f
  response: {
    b'bookA': b'68986213bd4485ea51533535e3fc9e78007a711f'
  }

With multiple bookmarks set

  $ hg book -r 1 bookB
  $ debugwireproto << EOF
  > command listkeys
  >     namespace bookmarks
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending listkeys command
  i> write(9) -> 9:
  i>     listkeys\n
  i> write(12) -> 12:
  i>     namespace 9\n
  i> write(9) -> 9: bookmarks
  i> flush() -> None
  o> bufferedreadline() -> 3:
  o>     93\n
  o> bufferedread(93) -> 93:
  o>     bookA\t68986213bd4485ea51533535e3fc9e78007a711f\n
  o>     bookB\t1880f3755e2e52e3199e0ee5638128b08642f34d
  response: {
    b'bookA': b'68986213bd4485ea51533535e3fc9e78007a711f',
    b'bookB': b'1880f3755e2e52e3199e0ee5638128b08642f34d'
  }

Test pushkey for bookmarks

  $ debugwireproto << EOF
  > command pushkey
  >     namespace bookmarks
  >     key remote
  >     old
  >     new 68986213bd4485ea51533535e3fc9e78007a711f
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending pushkey command
  i> write(8) -> 8:
  i>     pushkey\n
  i> write(6) -> 6:
  i>     key 6\n
  i> write(6) -> 6: remote
  i> write(12) -> 12:
  i>     namespace 9\n
  i> write(9) -> 9: bookmarks
  i> write(7) -> 7:
  i>     new 40\n
  i> write(40) -> 40: 68986213bd4485ea51533535e3fc9e78007a711f
  i> write(6) -> 6:
  i>     old 0\n
  i> flush() -> None
  o> bufferedreadline() -> 2:
  o>     2\n
  o> bufferedread(2) -> 2:
  o>     1\n
  response: True

  $ hg bookmarks
     bookA                     0:68986213bd44
     bookB                     1:1880f3755e2e
     remote                    0:68986213bd44

  $ cd ..

Test listkeys for phases

  $ hg init phasesrepo
  $ cd phasesrepo

Phases on empty repo

  $ debugwireproto << EOF
  > command listkeys
  >     namespace phases
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending listkeys command
  i> write(9) -> 9:
  i>     listkeys\n
  i> write(12) -> 12:
  i>     namespace 6\n
  i> write(6) -> 6: phases
  i> flush() -> None
  o> bufferedreadline() -> 3:
  o>     15\n
  o> bufferedread(15) -> 15: publishing\tTrue
  response: {
    b'publishing': b'True'
  }

Create some commits

  $ echo 0 > foo
  $ hg add foo
  $ hg -q commit -m initial
  $ hg phase --public
  $ echo 1 > foo
  $ hg commit -m 'head 1 commit 1'
  $ echo 2 > foo
  $ hg commit -m 'head 1 commit 2'
  $ hg -q up 0
  $ echo 1a > foo
  $ hg commit -m 'head 2 commit 1'
  created new head
  $ echo 2a > foo
  $ hg commit -m 'head 2 commit 2'

Two draft heads

  $ debugwireproto << EOF
  > command listkeys
  >     namespace phases
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending listkeys command
  i> write(9) -> 9:
  i>     listkeys\n
  i> write(12) -> 12:
  i>     namespace 6\n
  i> write(6) -> 6: phases
  i> flush() -> None
  o> bufferedreadline() -> 4:
  o>     101\n
  o> bufferedread(101) -> 101:
  o>     20b8a89289d80036e6c4e87c2083e3bea1586637\t1\n
  o>     c4750011d906c18ea2f0527419cbc1a544435150\t1\n
  o>     publishing\tTrue
  response: {
    b'20b8a89289d80036e6c4e87c2083e3bea1586637': b'1',
    b'c4750011d906c18ea2f0527419cbc1a544435150': b'1',
    b'publishing': b'True'
  }

Single draft head

  $ hg phase --public -r 2
  $ debugwireproto << EOF
  > command listkeys
  >     namespace phases
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending listkeys command
  i> write(9) -> 9:
  i>     listkeys\n
  i> write(12) -> 12:
  i>     namespace 6\n
  i> write(6) -> 6: phases
  i> flush() -> None
  o> bufferedreadline() -> 3:
  o>     58\n
  o> bufferedread(58) -> 58:
  o>     c4750011d906c18ea2f0527419cbc1a544435150\t1\n
  o>     publishing\tTrue
  response: {
    b'c4750011d906c18ea2f0527419cbc1a544435150': b'1',
    b'publishing': b'True'
  }

All public heads

  $ hg phase --public -r 4
  $ debugwireproto << EOF
  > command listkeys
  >     namespace phases
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending listkeys command
  i> write(9) -> 9:
  i>     listkeys\n
  i> write(12) -> 12:
  i>     namespace 6\n
  i> write(6) -> 6: phases
  i> flush() -> None
  o> bufferedreadline() -> 3:
  o>     15\n
  o> bufferedread(15) -> 15: publishing\tTrue
  response: {
    b'publishing': b'True'
  }

Setting public phase via pushkey

  $ hg phase --draft --force -r .

  $ debugwireproto << EOF
  > command pushkey
  >     namespace phases
  >     key 7127240a084fd9dc86fe8d1f98e26229161ec82b
  >     old 1
  >     new 0
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending pushkey command
  i> write(8) -> 8:
  i>     pushkey\n
  i> write(7) -> 7:
  i>     key 40\n
  i> write(40) -> 40: 7127240a084fd9dc86fe8d1f98e26229161ec82b
  i> write(12) -> 12:
  i>     namespace 6\n
  i> write(6) -> 6: phases
  i> write(6) -> 6:
  i>     new 1\n
  i> write(1) -> 1: 0
  i> write(6) -> 6:
  i>     old 1\n
  i> write(1) -> 1: 1
  i> flush() -> None
  o> bufferedreadline() -> 2:
  o>     2\n
  o> bufferedread(2) -> 2:
  o>     1\n
  response: True

  $ hg phase .
  4: public

  $ cd ..

Test batching of requests

  $ hg init batching
  $ cd batching
  $ echo 0 > foo
  $ hg add foo
  $ hg -q commit -m initial
  $ hg phase --public
  $ echo 1 > foo
  $ hg commit -m 'commit 1'
  $ hg -q up 0
  $ echo 2 > foo
  $ hg commit -m 'commit 2'
  created new head
  $ hg book -r 1 bookA
  $ hg book -r 2 bookB

  $ debugwireproto << EOF
  > batchbegin
  > command heads
  > command listkeys
  >     namespace bookmarks
  > command listkeys
  >     namespace phases
  > batchsubmit
  > EOF
  testing ssh1
  creating ssh peer from handshake results
  i> write(104) -> 104:
  i>     hello\n
  i>     between\n
  i>     pairs 81\n
  i>     0000000000000000000000000000000000000000-0000000000000000000000000000000000000000
  i> flush() -> None
  o> readline() -> 4:
  o>     \d+\\n (re)
  o> readline\(\) -> \d+: (re)
  o>     capabilities: batch branchmap \$USUAL_BUNDLE2_CAPS\$ changegroupsubset getbundle known lookup protocaps pushkey streamreqs=[^ ,]+(,[^ ,]+)* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash\\n (re)
  o> readline() -> 2:
  o>     1\n
  o> readline() -> 1:
  o>     \n
  sending batch with 3 sub-commands
  i> write(6) -> 6:
  i>     batch\n
  i> write(4) -> 4:
  i>     * 0\n
  i> write(8) -> 8:
  i>     cmds 61\n
  i> write(61) -> 61: heads ;listkeys namespace=bookmarks;listkeys namespace=phases
  i> flush() -> None
  o> bufferedreadline() -> 4:
  o>     278\n
  o> bufferedread(278) -> 278:
  o>     bfebe6bd38eebc6f8202e419c1171268987ea6a6 4ee3fcef1c800fa2bf23e20af7c83ff111d9c7ab\n
  o>     ;bookA\t4ee3fcef1c800fa2bf23e20af7c83ff111d9c7ab\n
  o>     bookB\tbfebe6bd38eebc6f8202e419c1171268987ea6a6;4ee3fcef1c800fa2bf23e20af7c83ff111d9c7ab\t1\n
  o>     bfebe6bd38eebc6f8202e419c1171268987ea6a6\t1\n
  o>     publishing\tTrue
  response #0: bfebe6bd38eebc6f8202e419c1171268987ea6a6 4ee3fcef1c800fa2bf23e20af7c83ff111d9c7ab\n
  response #1: bookA\t4ee3fcef1c800fa2bf23e20af7c83ff111d9c7ab\nbookB\tbfebe6bd38eebc6f8202e419c1171268987ea6a6
  response #2: 4ee3fcef1c800fa2bf23e20af7c83ff111d9c7ab\t1\nbfebe6bd38eebc6f8202e419c1171268987ea6a6\t1\npublishing\tTrue

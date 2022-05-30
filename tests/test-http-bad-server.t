#require serve zstd

Client version is embedded in HTTP request and is effectively dynamic. Pin the
version so behavior is deterministic.

  $ cat > fakeversion.py << EOF
  > from mercurial import util
  > util.version = lambda: b'4.2'
  > EOF

  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > fakeversion = `pwd`/fakeversion.py
  > [format]
  > sparse-revlog = no
  > use-persistent-nodemap = no
  > [devel]
  > legacy.exchange = phases
  > [server]
  > concurrent-push-mode = strict
  > EOF

  $ hg init server0
  $ cd server0
  $ touch foo
  $ hg -q commit -A -m initial

Also disable compression because zstd is optional and causes output to vary
and because debugging partial responses is hard when compression is involved

  $ cat > .hg/hgrc << EOF
  > [extensions]
  > badserver = $TESTDIR/testlib/badserverext.py
  > [server]
  > compressionengines = none
  > EOF

Failure to accept() socket should result in connection related error message
----------------------------------------------------------------------------

  $ hg serve --config badserver.close-before-accept=true -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: (\$ECONNRESET\$|\$EADDRNOTAVAIL\$) (re)
  [100]

(The server exits on its own, but there is a race between that and starting a new server.
So ensure the process is dead.)

  $ killdaemons.py $DAEMON_PIDS

Failure immediately after accept() should yield connection related error message
--------------------------------------------------------------------------------

  $ hg serve --config badserver.close-after-accept=true -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid > $DAEMON_PIDS

TODO: this usually outputs good results, but sometimes emits abort:
error: '' on FreeBSD and OS X.
What we ideally want are:

abort: error: $ECONNRESET$

The flakiness in this output was observable easily with
--runs-per-test=20 on macOS 10.12 during the freeze for 4.2.
  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

Failure to read all bytes in initial HTTP request should yield connection related error message
-----------------------------------------------------------------------------------------------

  $ hg serve --config badserver.close-after-recv-bytes=1 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log
  readline(1 from ~) -> (1) G
  read limit reached; closing socket

  $ rm -f error.log

Same failure, but server reads full HTTP request line
-----------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-recv-patterns="GET /\?cmd=capabilities" \
  > --config badserver.close-after-recv-bytes=7 \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS
  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(7 from *) -> (7) Accept- (glob)
  read limit reached; closing socket

  $ rm -f error.log

Failure on subsequent HTTP request on the same socket (cmd?batch)
-----------------------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-recv-patterns="GET /\?cmd=batch,GET /\?cmd=batch" \
  > --config badserver.close-after-recv-bytes=15,197 \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS
  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (*) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py36 !)
  sendall(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py3 no-py36 !)
  write(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py3 no-py36 !)
  readline(~) -> (26) GET /?cmd=batch HTTP/1.1\r\n (glob)
  readline(*) -> (1?) Accept-Encoding* (glob)
  read limit reached; closing socket
  readline(~) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(4 from *) -> (4) host (glob)
  read limit reached; closing socket

  $ rm -f error.log

Failure to read getbundle HTTP request
--------------------------------------

  $ hg serve \
  > --config badserver.close-after-recv-patterns="GET /\?cmd=batch,user-agent: mercurial/proto-1.0,GET /\?cmd=getbundle" \
  > --config badserver.close-after-recv-bytes=110,26,274 \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS
  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log
  readline(1 from -1) -> (1) x (?)
  readline(1 from -1) -> (1) x (?)
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (*) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py36 !)
  sendall(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py3 no-py36 !)
  write(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py3 no-py36 !)
  readline(~) -> (26) GET /?cmd=batch HTTP/1.1\r\n (glob)
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (1?) x-hgproto-1:* (glob)
  read limit reached; closing socket
  readline(~) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (*) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py36 !)
  write(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  write(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py3 no-py36 !)
  readline(24 from ~) -> (*) GET /?cmd=getbundle HTTP* (glob)
  read limit reached; closing socket
  readline(~) -> (30) GET /?cmd=getbundle HTTP/1.1\r\n
  readline(274 from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(247 from *) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(218 from *) -> (218) x-hgarg-1: bookmarks=1&bundlecaps=HG20%2Cbundle2%3DHG20%250Abookmarks%250Achangegroup%253D01%252C02%250Adigests%253Dmd5%252Csha1%252Csha512%250Aerror%253Dabort%252Cunsupportedcontent%252Cpushraced%252Cpushkey%250Ahgtag (glob)
  read limit reached; closing socket

  $ rm -f error.log

Now do a variation using POST to send arguments
===============================================

  $ hg serve \
  > --config badserver.close-after-recv-patterns="x-hgargs-post:,user-agent: mercurial/proto-1.0" \
  > --config badserver.close-after-recv-bytes="14,26" \
  > --config experimental.httppostargs=true \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py36 !)
  sendall(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx httppostargs known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py3 no-py36 !)
  write(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx httppostargs known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py3 no-py36 !)
  readline(~) -> (27) POST /?cmd=batch HTTP/1.1\r\n (glob)
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (41) content-type: application/mercurial-0.1\r\n (glob)
  readline(*) -> (33) vary: X-HgArgs-Post,X-HgProto-1\r\n (glob)
  readline(*) -> (19) x-hgargs-post: 28\r\n (glob)
  readline(*) -> (1?) x-hgproto-1: * (glob)
  read limit reached; closing socket
  readline(~) -> (27) POST /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (41) content-type: application/mercurial-0.1\r\n (glob)
  readline(*) -> (33) vary: X-HgArgs-Post,X-HgProto-1\r\n (glob)
  readline(*) -> (19) x-hgargs-post: 28\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (20) content-length: 28\r\n (glob)
  readline(*) -> (*) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  read(24 from 28) -> (*) cmds=* (glob)
  read limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=batch': (glob)
  Traceback (most recent call last):
  Exception: connection closed after receiving N bytes
  
  write(126) -> HTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)

  $ rm -f error.log

Now move on to partial server responses
=======================================

Server sends a single character from the HTTP response line
-----------------------------------------------------------

  $ hg serve --config badserver.close-after-send-bytes=1 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: H
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(1 from 160) -> (0) H (py36 !)
  write(1 from 160) -> (0) H (py3 no-py36 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=capabilities': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(286) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (glob) (py3 no-py36 !)

  $ rm -f error.log

Server sends an incomplete capabilities response body
-----------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='batch branchmap bund' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: HTTP request error (incomplete response; expected * bytes got 20) (glob)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py36 !)
  sendall(20 from *) -> (0) batch branchmap bund (glob) (py36 !)
  write(160) -> (20) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py3 no-py36 !)
  write(20 from *) -> (0) batch branchmap bund (glob) (py3 no-py36 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=capabilities': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

  $ rm -f error.log

Server sends incomplete headers for batch request
-------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='(.*Content-Type: applicat){2}' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

TODO this output is horrible

  $ hg clone http://localhost:$HGPORT/ clone
  abort: 'http://localhost:$HGPORT/' does not appear to be an hg repository:
  ---%<--- (applicat)
  
  ---%<---
  
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py36 !)
  sendall(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py36 !)
  write(160) -> (568) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py3 no-py36 !)
  write(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py3 no-py36 !)
  readline(~) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(118 from 159) -> (0) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: applicat (py36 !)
  write(118 from 159) -> (0) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: applicat (py3 no-py36 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=batch': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(285) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)

  $ rm -f error.log

Server sends an incomplete HTTP response body to batch request
--------------------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns=96ee1d7354c4ad7372047672 \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: unexpected response:
  '96ee1d7354c4ad7372047672'
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py36 !)
  sendall(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py3 no-py36 !)
  write(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py3 no-py36 !)
  readline(~) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(24 from 42) -> (0) 96ee1d7354c4ad7372047672 (py36 !)
  write(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  write(24 from 42) -> (0) 96ee1d7354c4ad7372047672 (py3 no-py36 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=batch': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

  $ rm -f error.log

Server sends incomplete headers for getbundle response
------------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='(.*Content-Type: application/mercuri){3}' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

TODO this output is terrible

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: 'http://localhost:$HGPORT/' does not appear to be an hg repository:
  ---%<--- (application/mercuri)
  
  ---%<---
  
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py36 !)
  sendall(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py3 no-py36 !)
  write(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py3 no-py36 !)
  readline(~) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py36 !)
  write(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  write(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py3 no-py36 !)
  readline(~) -> (30) GET /?cmd=getbundle HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (440) x-hgarg-1: bookmarks=1&bundlecaps=HG20%2Cbundle2%3DHG20%250Abookmarks%250Achangegroup%253D01%252C02%250Adigests%253Dmd5%252Csha1%252Csha512%250Aerror%253Dabort%252Cunsupportedcontent%252Cpushraced%252Cpushkey%250Ahgtagsfnodes%250Alistkeys%250Apushkey%250Aremote-changegroup%253Dhttp%252Chttps%250Astream%253Dv2&cg=1&common=0000000000000000000000000000000000000000&heads=96ee1d7354c4ad7372047672c36a1f561e3a6a4c&listkeys=phases%2Cbookmarks\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(129 from 167) -> (0) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercuri (py36 !)
  write(129 from 167) -> (0) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercuri (py3 no-py36 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(293) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)

  $ rm -f error.log

Server stops before it sends transfer encoding
----------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns="Transfer-Encoding: chunke" \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: stream ended unexpectedly (got 0 bytes, expected 1)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -6
  sendall(162 from 167) -> (0) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunke
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -7
  write(41) -> Content-Type: application/mercurial-0.2\r\n
  write(25 from 28) -> (0) Transfer-Encoding: chunke
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  write(293) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  
#endif

  $ rm -f error.log

Server sends empty HTTP body for getbundle
------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='Transfer-Encoding: chunked\r\n\r\n' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py36 !)
  sendall(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py3 no-py36 !)
  write(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py3 no-py36 !)
  readline(~) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py36 !)
  write(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  write(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py3 no-py36 !)
  readline(~) -> (30) GET /?cmd=getbundle HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (440) x-hgarg-1: bookmarks=1&bundlecaps=HG20%2Cbundle2%3DHG20%250Abookmarks%250Achangegroup%253D01%252C02%250Adigests%253Dmd5%252Csha1%252Csha512%250Aerror%253Dabort%252Cunsupportedcontent%252Cpushraced%252Cpushkey%250Ahgtagsfnodes%250Alistkeys%250Apushkey%250Aremote-changegroup%253Dhttp%252Chttps%250Astream%253Dv2&cg=1&common=0000000000000000000000000000000000000000&heads=96ee1d7354c4ad7372047672c36a1f561e3a6a4c&listkeys=phases%2Cbookmarks\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(167 from 167) -> (0) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py36 !)
  write(167 from 167) -> (0) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(293) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)

  $ rm -f error.log

Server sends partial compression string
---------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='4\r\nHG20\r\n' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(~) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py36 !)
  sendall(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: *\r\n\r\n (glob) (py3 no-py36 !)
  write(*) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=* unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (glob) (py3 no-py36 !)
  readline(~) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py36 !)
  write(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  readline(~) -> (30) GET /?cmd=getbundle HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (440) x-hgarg-1: bookmarks=1&bundlecaps=HG20%2Cbundle2%3DHG20%250Abookmarks%250Achangegroup%253D01%252C02%250Adigests%253Dmd5%252Csha1%252Csha512%250Aerror%253Dabort%252Cunsupportedcontent%252Cpushraced%252Cpushkey%250Ahgtagsfnodes%250Alistkeys%250Apushkey%250Aremote-changegroup%253Dhttp%252Chttps%250Astream%253Dv2&cg=1&common=0000000000000000000000000000000000000000&heads=96ee1d7354c4ad7372047672c36a1f561e3a6a4c&listkeys=phases%2Cbookmarks\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py36 !)
  sendall(6) -> 1\\r\\n\x04\\r\\n (esc) (py36 !)
  sendall(9) -> 4\r\nnone\r\n (py36 !)
  sendall(9 from 9) -> (0) 4\r\nHG20\r\n (py36 !)
  write(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

  $ rm -f error.log

Server sends partial bundle2 header magic
-----------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='4\r\nHG2' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response) (py3 !)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -9
  sendall(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6) -> 1\\r\\n\x04\\r\\n (esc)
  sendall(9) -> 4\r\nnone\r\n
  sendall(6 from 9) -> (0) 4\r\nHG2
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -11
  readline(~) -> (2) \r\n (py3 !)
  write(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(6) -> 1\\r\\n\x04\\r\\n (esc)
  write(9) -> 4\r\nnone\r\n
  write(6 from 9) -> (0) 4\r\nHG2
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log

Server sends incomplete bundle2 stream params length
----------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='4\r\n\0\0\0' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response) (py3 !)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -10
  sendall(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6) -> 1\\r\\n\x04\\r\\n (esc)
  sendall(9) -> 4\r\nnone\r\n
  sendall(9) -> 4\r\nHG20\r\n
  sendall(6 from 9) -> (0) 4\\r\\n\x00\x00\x00 (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -12
  readline(~) -> (2) \r\n (py3 !)
  write(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(41) -> Content-Type: application/mercurial-0.2\r\n
  write(6) -> 1\\r\\n\x04\\r\\n (esc)
  write(9) -> 4\r\nnone\r\n
  write(9) -> 4\r\nHG20\r\n
  write(6 from 9) -> (0) 4\\r\\n\x00\x00\x00 (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log

Servers stops after bundle2 stream params header
------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='4\r\n\0\0\0\0\r\n' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -10
  sendall(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6) -> 1\\r\\n\x04\\r\\n (esc)
  sendall(9) -> 4\r\nnone\r\n
  sendall(9) -> 4\r\nHG20\r\n
  sendall(9 from 9) -> (0) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -12
  readline(~) -> (2) \r\n (py3 !)
  write(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(41) -> Content-Type: application/mercurial-0.2\r\n
  write(6) -> 1\\r\\n\x04\\r\\n (esc)
  write(9) -> 4\r\nnone\r\n
  write(9) -> 4\r\nHG20\r\n
  write(9 from 9) -> (0) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log

Server stops sending after bundle2 part header length
-----------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='4\r\n\0\0\0\)\r\n' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -11
  sendall(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6) -> 1\\r\\n\x04\\r\\n (esc)
  sendall(9) -> 4\r\nnone\r\n
  sendall(9) -> 4\r\nHG20\r\n
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (0) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else

  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -13
  readline(~) -> (2) \r\n (py3 !)
  write(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(41) -> Content-Type: application/mercurial-0.2\r\n
  write(6) -> 1\\r\\n\x04\\r\\n (esc)
  write(9) -> 4\r\nnone\r\n
  write(9) -> 4\r\nHG20\r\n
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (0) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log

Server stops sending after bundle2 part header
----------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns="version02nbchanges1\\r\\n" \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  adding changesets
  transaction abort!
  rollback completed
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -12
  sendall(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6) -> 1\\r\\n\x04\\r\\n (esc)
  sendall(9) -> 4\r\nnone\r\n
  sendall(9) -> 4\r\nHG20\r\n
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47 from 47) -> (0) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -14
  readline(~) -> (2) \r\n (py3 !)
  write(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(41) -> Content-Type: application/mercurial-0.2\r\n
  write(6) -> 1\\r\\n\x04\\r\\n (esc)
  write(9) -> 4\r\nnone\r\n
  write(9) -> 4\r\nHG20\r\n
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47 from 47) -> (0) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log

Server stops after bundle2 part payload chunk size
--------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns='1d2\r\n.......' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  adding changesets
  transaction abort!
  rollback completed
  abort: HTTP request error (incomplete response) (py3 !)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -14
  sendall(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6) -> 1\\r\\n\x04\\r\\n (esc)
  sendall(9) -> 4\r\nnone\r\n
  sendall(9) -> 4\r\nHG20\r\n
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(12 from 473) -> (0) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1d (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -15
  write(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(28) -> Transfer-Encoding: chunked\r\n
  write(6) -> 1\\r\\n\x04\\r\\n (esc)
  write(9) -> 4\r\nnone\r\n
  write(9) -> 4\r\nHG20\r\n
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(12 from 473) -> (0) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1d (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log

Server stops sending in middle of bundle2 payload chunk
-------------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns=':jL\0\0\x00\0\0\0\0\0\r\n' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  adding changesets
  transaction abort!
  rollback completed
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -14
  sendall(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6) -> 1\\r\\n\x04\\r\\n (esc)
  sendall(9) -> 4\r\nnone\r\n
  sendall(9) -> 4\r\nHG20\r\n
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(473 from 473) -> (0) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -16
  readline(~) -> (2) \r\n (py3 !)
  write(167) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(41) -> Content-Type: application/mercurial-0.2\r\n
  write(6) -> 1\\r\\n\x04\\r\\n (esc)
  write(9) -> 4\r\nnone\r\n
  write(9) -> 4\r\nHG20\r\n
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(473 from 473) -> (0) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log

Server stops sending after 0 length payload chunk size
------------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns=LISTKEYS \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  transaction abort!
  rollback completed
  abort: HTTP request error (incomplete response) (py3 !)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -16
  sendall(6) -> 1\\r\\n\x04\\r\\n (esc)
  sendall(9) -> 4\r\nnone\r\n
  sendall(9) -> 4\r\nHG20\r\n
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(473) -> 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  sendall(13 from 38) -> (0) 20\\r\\n\x08LISTKEYS (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -17
  write(2) -> \r\n
  write(6) -> 1\\r\\n\x04\\r\\n (esc)
  write(9) -> 4\r\nnone\r\n
  write(9) -> 4\r\nHG20\r\n
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(473) -> 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  write(13 from 38) -> (0) 20\\r\\n\x08LISTKEYS (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log

Server stops sending after 0 part bundle part header (indicating end of bundle2 payload)
----------------------------------------------------------------------------------------

This is before the 0 size chunked transfer part that signals end of HTTP response.

  $ hg serve \
  > --config badserver.close-after-send-patterns='(.*4\r\n\0\0\0\0\r\n){5}' \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 96ee1d7354c4
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -20
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(473) -> 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  sendall(38) -> 20\\r\\n\x08LISTKEYS\x00\x00\x00\x01\x01\x00	\x06namespacephases\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00:\\r\\n (esc)
  sendall(64) -> 3a\r\n96ee1d7354c4ad7372047672c36a1f561e3a6a4c	1\npublishing	True\r\n
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00#\\r\\n (esc)
  sendall(41) -> 23\\r\\n\x08LISTKEYS\x00\x00\x00\x02\x01\x00		namespacebookmarks\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (0) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -21
  write(9) -> 4\r\nHG20\r\n
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(473) -> 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  write(38) -> 20\\r\\n\x08LISTKEYS\x00\x00\x00\x01\x01\x00	\x06namespacephases\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00:\\r\\n (esc)
  write(64) -> 3a\r\n96ee1d7354c4ad7372047672c36a1f561e3a6a4c	1\npublishing	True\r\n
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00#\\r\\n (esc)
  write(41) -> 23\\r\\n\x08LISTKEYS\x00\x00\x00\x02\x01\x00		namespacebookmarks\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (0) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log
  $ rm -rf clone

Server sends a size 0 chunked-transfer size without terminating \r\n
--------------------------------------------------------------------

  $ hg serve \
  > --config badserver.close-after-send-patterns="(.*4\\r\\n\0\0\0\0\\r\\n0\r\n)" \
  > -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 96ee1d7354c4
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -21
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(473) -> 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  sendall(38) -> 20\\r\\n\x08LISTKEYS\x00\x00\x00\x01\x01\x00	\x06namespacephases\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00:\\r\\n (esc)
  sendall(64) -> 3a\r\n96ee1d7354c4ad7372047672c36a1f561e3a6a4c	1\npublishing	True\r\n
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00#\\r\\n (esc)
  sendall(41) -> 23\\r\\n\x08LISTKEYS\x00\x00\x00\x02\x01\x00		namespacebookmarks\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(3 from 5) -> (0) 0\r\n
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -22
  write(9) -> 4\r\nHG20\r\n
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47) -> 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(473) -> 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  write(38) -> 20\\r\\n\x08LISTKEYS\x00\x00\x00\x01\x01\x00	\x06namespacephases\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00:\\r\\n (esc)
  write(64) -> 3a\r\n96ee1d7354c4ad7372047672c36a1f561e3a6a4c	1\npublishing	True\r\n
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00#\\r\\n (esc)
  write(41) -> 23\\r\\n\x08LISTKEYS\x00\x00\x00\x02\x01\x00		namespacebookmarks\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9) -> 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(3 from 5) -> (0) 0\r\n
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
#endif

  $ rm -f error.log
  $ rm -rf clone

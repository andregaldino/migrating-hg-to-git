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
  > badserver = $TESTDIR/badserverext.py
  > [server]
  > compressionengines = none
  > EOF

Failure to accept() socket should result in connection related error message

  $ hg serve --config badserver.closebeforeaccept=true -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: (\$ECONNRESET\$|\$EADDRNOTAVAIL\$) (re)
  [100]

(The server exits on its own, but there is a race between that and starting a new server.
So ensure the process is dead.)

  $ killdaemons.py $DAEMON_PIDS

Failure immediately after accept() should yield connection related error message

  $ hg serve --config badserver.closeafteraccept=true -p $HGPORT -d --pid-file=hg.pid
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

  $ hg serve --config badserver.closeafterrecvbytes=1 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log
  readline(1 from 65537) -> (1) G
  read limit reached; closing socket

  $ rm -f error.log

Same failure, but server reads full HTTP request line

  $ hg serve --config badserver.closeafterrecvbytes=40 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS
  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log
  readline(40 from 65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(7 from *) -> (7) Accept- (glob)
  read limit reached; closing socket

  $ rm -f error.log

Failure on subsequent HTTP request on the same socket (cmd?batch)

  $ hg serve --config badserver.closeafterrecvbytes=210,223 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS
  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log
  readline(210 from 65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(177 from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(150 from *) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(115 from *) -> (*) host: localhost:$HGPORT\r\n (glob)
  readline(* from *) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(* from *) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py36 !)
  sendall(431) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py3 no-py36 !)
  write(431) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py3 no-py36 !)
  write(36) -> HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23) -> Server: badhttpserver\r\n (no-py3 !)
  write(37) -> Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41) -> Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(21) -> Content-Length: 431\r\n (no-py3 !)
  write(2) -> \r\n (no-py3 !)
  write(431) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (no-py3 !)
  readline(4? from 65537) -> (26) GET /?cmd=batch HTTP/1.1\r\n (glob)
  readline(1? from *) -> (1?) Accept-Encoding* (glob)
  read limit reached; closing socket
  readline(223 from 65537) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(197 from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(170 from *) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(141 from *) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(100 from *) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(39 from *) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(4 from *) -> (4) host (glob)
  read limit reached; closing socket

  $ rm -f error.log

Failure to read getbundle HTTP request

  $ hg serve --config badserver.closeafterrecvbytes=308,317,304 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS
  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log
  readline(1 from -1) -> (1) x (?)
  readline(1 from -1) -> (1) x (?)
  readline(308 from 65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(275 from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(248 from *) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(213 from *) -> (*) host: localhost:$HGPORT\r\n (glob)
  readline(* from *) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(* from *) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py36 !)
  sendall(431) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py3 no-py36 !)
  write(431) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py3 no-py36 !)
  write(36) -> HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23) -> Server: badhttpserver\r\n (no-py3 !)
  write(37) -> Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41) -> Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(21) -> Content-Length: 431\r\n (no-py3 !)
  write(2) -> \r\n (no-py3 !)
  write(431) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (no-py3 !)
  readline(13? from 65537) -> (26) GET /?cmd=batch HTTP/1.1\r\n (glob)
  readline(1?? from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(8? from *) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(5? from *) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(1? from *) -> (1?) x-hgproto-1:* (glob)
  read limit reached; closing socket
  readline(317 from 65537) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(291 from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(264 from *) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(235 from *) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(194 from *) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(133 from *) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(98 from *) -> (*) host: localhost:$HGPORT\r\n (glob)
  readline(* from *) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(* from *) -> (2) \r\n (glob)
  sendall(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py36 !)
  write(159) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  write(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py3 no-py36 !)
  write(36) -> HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23) -> Server: badhttpserver\r\n (no-py3 !)
  write(37) -> Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41) -> Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(20) -> Content-Length: 42\r\n (no-py3 !)
  write(2) -> \r\n (no-py3 !)
  write(42) -> 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (no-py3 !)
  readline(* from 65537) -> (*) GET /?cmd=getbundle HTTP* (glob)
  read limit reached; closing socket
  readline(304 from 65537) -> (30) GET /?cmd=getbundle HTTP/1.1\r\n
  readline(274 from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(247 from *) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(218 from *) -> (218) x-hgarg-1: bookmarks=1&bundlecaps=HG20%2Cbundle2%3DHG20%250Abookmarks%250Achangegroup%253D01%252C02%250Adigests%253Dmd5%252Csha1%252Csha512%250Aerror%253Dabort%252Cunsupportedcontent%252Cpushraced%252Cpushkey%250Ahgtag (glob)
  read limit reached; closing socket

  $ rm -f error.log

Now do a variation using POST to send arguments

  $ hg serve --config experimental.httppostargs=true --config badserver.closeafterrecvbytes=329,344 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: * (glob)
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(329 from 65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(296 from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(269 from *) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(234 from *) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(* from *) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(* from *) -> (2) \r\n (glob)
  sendall(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 444\r\n\r\n (py36 !)
  sendall(444) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx httppostargs known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py36 !)
  write(160) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 444\r\n\r\n (py3 no-py36 !)
  write(444) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx httppostargs known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py3 no-py36 !)
  write(36) -> HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23) -> Server: badhttpserver\r\n (no-py3 !)
  write(37) -> Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41) -> Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(21) -> Content-Length: 444\r\n (no-py3 !)
  write(2) -> \r\n (no-py3 !)
  write(444) -> batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx httppostargs known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (no-py3 !)
  readline(1?? from 65537) -> (27) POST /?cmd=batch HTTP/1.1\r\n (glob)
  readline(1?? from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(1?? from *) -> (41) content-type: application/mercurial-0.1\r\n (glob)
  readline(6? from *) -> (33) vary: X-HgArgs-Post,X-HgProto-1\r\n (glob)
  readline(3? from *) -> (19) x-hgargs-post: 28\r\n (glob)
  readline(1? from *) -> (1?) x-hgproto-1: * (glob)
  read limit reached; closing socket
  readline(344 from 65537) -> (27) POST /?cmd=batch HTTP/1.1\r\n
  readline(317 from *) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(290 from *) -> (41) content-type: application/mercurial-0.1\r\n (glob)
  readline(249 from *) -> (33) vary: X-HgArgs-Post,X-HgProto-1\r\n (glob)
  readline(216 from *) -> (19) x-hgargs-post: 28\r\n (glob)
  readline(197 from *) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(136 from *) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(101 from *) -> (20) content-length: 28\r\n (glob)
  readline(81 from *) -> (*) host: localhost:$HGPORT\r\n (glob)
  readline(* from *) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(* from *) -> (2) \r\n (glob)
  read(* from 28) -> (*) cmds=* (glob)
  read limit reached, closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=batch': (glob)
  Traceback (most recent call last):
  Exception: connection closed after receiving N bytes
  
  write(126) -> HTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)
  write(36) -> HTTP/1.1 500 Internal Server Error\r\n (no-py3 !)

  $ rm -f error.log

Now move on to partial server responses

Server sends a single character from the HTTP response line

  $ hg serve --config badserver.closeaftersendbytes=1 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: error: bad HTTP status line: H
  [100]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(1 from 160) -> (0) H (py36 !)
  write(1 from 160) -> (0) H (py3 no-py36 !)
  write(1 from 36) -> (0) H (no-py3 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=capabilities': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(286) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)
  write(36) -> HTTP/1.1 500 Internal Server Error\r\n (no-py3 !)

  $ rm -f error.log

Server sends an incomplete capabilities response body

  $ hg serve --config badserver.closeaftersendbytes=180 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  abort: HTTP request error (incomplete response; expected 431 bytes got 20)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160 from 160) -> (20) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py36 !)
  sendall(20 from 431) -> (0) batch branchmap bund (py36 !)
  write(160 from 160) -> (20) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py3 no-py36 !)
  write(20 from 431) -> (0) batch branchmap bund (py3 no-py36 !)
  write(36 from 36) -> (144) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (121) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (84) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (43) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(21 from 21) -> (22) Content-Length: 431\r\n (no-py3 !)
  write(2 from 2) -> (20) \r\n (no-py3 !)
  write(20 from 431) -> (0) batch branchmap bund (no-py3 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=capabilities': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

  $ rm -f error.log

Server sends incomplete headers for batch request

  $ hg serve --config badserver.closeaftersendbytes=709 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

TODO this output is horrible

  $ hg clone http://localhost:$HGPORT/ clone
  abort: 'http://localhost:$HGPORT/' does not appear to be an hg repository:
  ---%<--- (applicat)
  
  ---%<---
  
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160 from 160) -> (549) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py36 !)
  sendall(431 from 431) -> (118) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py36 !)
  write(160 from 160) -> (568) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py3 no-py36 !)
  write(431 from 431) -> (118) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py3 no-py36 !)
  write(36 from 36) -> (673) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (650) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (613) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (572) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(21 from 21) -> (551) Content-Length: 431\r\n (no-py3 !)
  write(2 from 2) -> (549) \r\n (no-py3 !)
  write(431 from 431) -> (118) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (no-py3 !)
  readline(65537) -> (26) GET /?cmd=batch HTTP/1.1\r\n
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
  write(36 from 36) -> (82) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (59) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (22) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(22 from 41) -> (0) Content-Type: applicat (no-py3 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=batch': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(285) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)
  write(36) -> HTTP/1.1 500 Internal Server Error\r\n (no-py3 !)

  $ rm -f error.log

Server sends an incomplete HTTP response body to batch request

  $ hg serve --config badserver.closeaftersendbytes=774 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

TODO client spews a stack due to uncaught ValueError in batch.results()
#if no-chg
  $ hg clone http://localhost:$HGPORT/ clone 2> /dev/null
  [1]
#else
  $ hg clone http://localhost:$HGPORT/ clone 2> /dev/null
  [255]
#endif

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160 from 160) -> (614) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py36 !)
  sendall(431 from 431) -> (183) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py36 !)
  write(160 from 160) -> (633) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py3 no-py36 !)
  write(431 from 431) -> (183) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py3 no-py36 !)
  write(36 from 36) -> (738) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (715) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (678) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (637) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(21 from 21) -> (616) Content-Length: 431\r\n (no-py3 !)
  write(2 from 2) -> (614) \r\n (no-py3 !)
  write(431 from 431) -> (183) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (no-py3 !)
  readline(65537) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(159 from 159) -> (24) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(24 from 42) -> (0) 96ee1d7354c4ad7372047672 (py36 !)
  write(159 from 159) -> (24) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  write(24 from 42) -> (0) 96ee1d7354c4ad7372047672 (py3 no-py36 !)
  write(36 from 36) -> (147) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (124) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (87) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (46) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(20 from 20) -> (26) Content-Length: 42\r\n (no-py3 !)
  write(2 from 2) -> (24) \r\n (no-py3 !)
  write(24 from 42) -> (0) 96ee1d7354c4ad7372047672 (no-py3 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=batch': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

  $ rm -f error.log

Server sends incomplete headers for getbundle response

  $ hg serve --config badserver.closeaftersendbytes=921 -p $HGPORT -d --pid-file=hg.pid -E error.log
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
  readline(65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160 from 160) -> (761) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py36 !)
  sendall(431 from 431) -> (330) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py36 !)
  write(160 from 160) -> (780) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py3 no-py36 !)
  write(431 from 431) -> (330) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py3 no-py36 !)
  write(36 from 36) -> (885) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (862) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (825) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (784) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(21 from 21) -> (763) Content-Length: 431\r\n (no-py3 !)
  write(2 from 2) -> (761) \r\n (no-py3 !)
  write(431 from 431) -> (330) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (no-py3 !)
  readline(65537) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(159 from 159) -> (171) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(42 from 42) -> (129) 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py36 !)
  write(159 from 159) -> (171) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  write(42 from 42) -> (129) 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py3 no-py36 !)
  write(36 from 36) -> (294) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (271) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (234) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (193) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(20 from 20) -> (173) Content-Length: 42\r\n (no-py3 !)
  write(2 from 2) -> (171) \r\n (no-py3 !)
  write(42 from 42) -> (129) 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (no-py3 !)
  readline(65537) -> (30) GET /?cmd=getbundle HTTP/1.1\r\n
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
  write(36 from 36) -> (93) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (70) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (33) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(33 from 41) -> (0) Content-Type: application/mercuri (no-py3 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(293) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)
  write(36) -> HTTP/1.1 500 Internal Server Error\r\n (no-py3 !)

  $ rm -f error.log

Server stops before it sends transfer encoding

  $ hg serve --config badserver.closeaftersendbytes=954 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: stream ended unexpectedly (got 0 bytes, expected 1)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -3
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -4
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(293) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(36) -> HTTP/1.1 500 Internal Server Error\r\n (no-py3 !)
#endif

  $ rm -f error.log

Server sends empty HTTP body for getbundle

  $ hg serve --config badserver.closeaftersendbytes=959 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160 from 160) -> (799) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py36 !)
  sendall(431 from 431) -> (368) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py36 !)
  write(160 from 160) -> (818) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py3 no-py36 !)
  write(431 from 431) -> (368) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py3 no-py36 !)
  write(36 from 36) -> (923) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (900) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (863) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (822) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(21 from 21) -> (801) Content-Length: 431\r\n (no-py3 !)
  write(2 from 2) -> (799) \r\n (no-py3 !)
  write(431 from 431) -> (368) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (no-py3 !)
  readline(65537) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(159 from 159) -> (209) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(42 from 42) -> (167) 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py36 !)
  write(159 from 159) -> (209) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  write(42 from 42) -> (167) 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py3 no-py36 !)
  write(36 from 36) -> (332) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (309) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (272) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (231) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(20 from 20) -> (211) Content-Length: 42\r\n (no-py3 !)
  write(2 from 2) -> (209) \r\n (no-py3 !)
  write(42 from 42) -> (167) 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (no-py3 !)
  readline(65537) -> (30) GET /?cmd=getbundle HTTP/1.1\r\n
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
  write(36 from 36) -> (131) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (108) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (71) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (30) Content-Type: application/mercurial-0.2\r\n (no-py3 !)
  write(28 from 28) -> (2) Transfer-Encoding: chunked\r\n (no-py3 !)
  write(2 from 2) -> (0) \r\n (no-py3 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(293) -> HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\nHTTP/1.1 500 Internal Server Error\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)
  write(36) -> HTTP/1.1 500 Internal Server Error\r\n (no-py3 !)

  $ rm -f error.log

Server sends partial compression string

  $ hg serve --config badserver.closeaftersendbytes=983 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

  $ cat error.log | "$PYTHON" $TESTDIR/filtertraceback.py
  readline(65537) -> (33) GET /?cmd=capabilities HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(160 from 160) -> (823) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py36 !)
  sendall(431 from 431) -> (392) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py36 !)
  write(160 from 160) -> (842) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 431\r\n\r\n (py3 no-py36 !)
  write(431 from 431) -> (392) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (py3 no-py36 !)
  write(36 from 36) -> (947) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (924) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (887) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (846) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(21 from 21) -> (825) Content-Length: 431\r\n (no-py3 !)
  write(2 from 2) -> (823) \r\n (no-py3 !)
  write(431 from 431) -> (392) batch branchmap $USUAL_BUNDLE2_CAPS_NO_PHASES$ changegroupsubset compression=none getbundle httpheader=1024 httpmediatype=0.1rx,0.1tx,0.2tx known lookup pushkey streamreqs=generaldelta,revlogv1 unbundle=HG10GZ,HG10BZ,HG10UN unbundlehash (no-py3 !)
  readline(65537) -> (26) GET /?cmd=batch HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (41) x-hgarg-1: cmds=heads+%3Bknown+nodes%3D\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(159 from 159) -> (233) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py36 !)
  sendall(42 from 42) -> (191) 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (py36 !)
  write(159 from 159) -> (233) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.1\r\nContent-Length: 42\r\n\r\n (py3 no-py36 !)
  write(36 from 36) -> (356) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (333) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (296) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (255) Content-Type: application/mercurial-0.1\r\n (no-py3 !)
  write(20 from 20) -> (235) Content-Length: 42\r\n (no-py3 !)
  write(2 from 2) -> (233) \r\n (no-py3 !)
  write(42 from 42) -> (191) 96ee1d7354c4ad7372047672c36a1f561e3a6a4c\n; (no-py3 !)
  readline(65537) -> (30) GET /?cmd=getbundle HTTP/1.1\r\n
  readline(*) -> (27) Accept-Encoding: identity\r\n (glob)
  readline(*) -> (29) vary: X-HgArg-1,X-HgProto-1\r\n (glob)
  readline(*) -> (440) x-hgarg-1: bookmarks=1&bundlecaps=HG20%2Cbundle2%3DHG20%250Abookmarks%250Achangegroup%253D01%252C02%250Adigests%253Dmd5%252Csha1%252Csha512%250Aerror%253Dabort%252Cunsupportedcontent%252Cpushraced%252Cpushkey%250Ahgtagsfnodes%250Alistkeys%250Apushkey%250Aremote-changegroup%253Dhttp%252Chttps%250Astream%253Dv2&cg=1&common=0000000000000000000000000000000000000000&heads=96ee1d7354c4ad7372047672c36a1f561e3a6a4c&listkeys=phases%2Cbookmarks\r\n (glob)
  readline(*) -> (61) x-hgproto-1: 0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull\r\n (glob)
  readline(*) -> (35) accept: application/mercurial-0.1\r\n (glob)
  readline(*) -> (2?) host: localhost:$HGPORT\r\n (glob)
  readline(*) -> (49) user-agent: mercurial/proto-1.0 (Mercurial 4.2)\r\n (glob)
  readline(*) -> (2) \r\n (glob)
  sendall(167 from 167) -> (24) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py36 !)
  sendall(6 from 6) -> (18) 1\\r\\n\x04\\r\\n (esc) (py36 !)
  sendall(9 from 9) -> (9) 4\r\nnone\r\n (py36 !)
  sendall(9 from 9) -> (0) 4\r\nHG20\r\n (py36 !)
  write(167 from 167) -> (24) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 no-py36 !)
  write(36 from 36) -> (155) HTTP/1.1 200 Script output follows\r\n (no-py3 !)
  write(23 from 23) -> (132) Server: badhttpserver\r\n (no-py3 !)
  write(37 from 37) -> (95) Date: $HTTP_DATE$\r\n (no-py3 !)
  write(41 from 41) -> (54) Content-Type: application/mercurial-0.2\r\n (no-py3 !)
  write(28 from 28) -> (26) Transfer-Encoding: chunked\r\n (no-py3 !)
  write(2 from 2) -> (24) \r\n (no-py3 !)
  write(6 from 6) -> (18) 1\\r\\n\x04\\r\\n (esc) (no-py3 !)
  write(9 from 9) -> (9) 4\r\nnone\r\n (no-py3 !)
  write(9 from 9) -> (0) 4\r\nHG20\r\n (no-py3 !)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n (no-py3 !)

  $ rm -f error.log

Server sends partial bundle2 header magic

  $ hg serve --config badserver.closeaftersendbytes=980 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response) (py3 !)
  abort: HTTP request error (incomplete response; expected 4 bytes got 3) (no-py3 !)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -9
  sendall(167 from 167) -> (21) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6 from 6) -> (15) 1\\r\\n\x04\\r\\n (esc)
  sendall(9 from 9) -> (6) 4\r\nnone\r\n
  sendall(6 from 9) -> (0) 4\r\nHG2
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -11
  readline(65537) -> (2) \r\n (py3 !)
  write(167 from 167) -> (21) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(28 from 28) -> (23) Transfer-Encoding: chunked\r\n (no-py3 !)
  write(2 from 2) -> (21) \r\n (no-py3 !)
  write(6 from 6) -> (15) 1\\r\\n\x04\\r\\n (esc)
  write(9 from 9) -> (6) 4\r\nnone\r\n
  write(6 from 9) -> (0) 4\r\nHG2
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log

Server sends incomplete bundle2 stream params length

  $ hg serve --config badserver.closeaftersendbytes=989 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response) (py3 !)
  abort: HTTP request error (incomplete response; expected 4 bytes got 3) (no-py3 !)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -10
  sendall(167 from 167) -> (30) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6 from 6) -> (24) 1\\r\\n\x04\\r\\n (esc)
  sendall(9 from 9) -> (15) 4\r\nnone\r\n
  sendall(9 from 9) -> (6) 4\r\nHG20\r\n
  sendall(6 from 9) -> (0) 4\\r\\n\x00\x00\x00 (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -12
  readline(65537) -> (2) \r\n (py3 !)
  write(167 from 167) -> (30) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(28 from 28) -> (32) Transfer-Encoding: chunked\r\n (no-py3 !)
  write(2 from 2) -> (30) \r\n (no-py3 !)
  write(6 from 6) -> (24) 1\\r\\n\x04\\r\\n (esc)
  write(9 from 9) -> (15) 4\r\nnone\r\n
  write(9 from 9) -> (6) 4\r\nHG20\r\n
  write(6 from 9) -> (0) 4\\r\\n\x00\x00\x00 (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log

Servers stops after bundle2 stream params header

  $ hg serve --config badserver.closeaftersendbytes=992 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -10
  sendall(167 from 167) -> (33) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6 from 6) -> (27) 1\\r\\n\x04\\r\\n (esc)
  sendall(9 from 9) -> (18) 4\r\nnone\r\n
  sendall(9 from 9) -> (9) 4\r\nHG20\r\n
  sendall(9 from 9) -> (0) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -12
  readline(65537) -> (2) \r\n (py3 !)
  write(167 from 167) -> (33) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(28 from 28) -> (35) Transfer-Encoding: chunked\r\n (no-py3 !)
  write(2 from 2) -> (33) \r\n (no-py3 !)
  write(6 from 6) -> (27) 1\\r\\n\x04\\r\\n (esc)
  write(9 from 9) -> (18) 4\r\nnone\r\n
  write(9 from 9) -> (9) 4\r\nHG20\r\n
  write(9 from 9) -> (0) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log

Server stops sending after bundle2 part header length

  $ hg serve --config badserver.closeaftersendbytes=1001 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  abort: HTTP request error (incomplete response)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -11
  sendall(167 from 167) -> (42) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6 from 6) -> (36) 1\\r\\n\x04\\r\\n (esc)
  sendall(9 from 9) -> (27) 4\r\nnone\r\n
  sendall(9 from 9) -> (18) 4\r\nHG20\r\n
  sendall(9 from 9) -> (9) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (0) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else

  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -13
  readline(65537) -> (2) \r\n (py3 !)
  write(167 from 167) -> (42) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(28 from 28) -> (44) Transfer-Encoding: chunked\r\n (no-py3 !)
  write(2 from 2) -> (42) \r\n (no-py3 !)
  write(6 from 6) -> (36) 1\\r\\n\x04\\r\\n (esc)
  write(9 from 9) -> (27) 4\r\nnone\r\n
  write(9 from 9) -> (18) 4\r\nHG20\r\n
  write(9 from 9) -> (9) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (0) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log

Server stops sending after bundle2 part header

  $ hg serve --config badserver.closeaftersendbytes=1048 -p $HGPORT -d --pid-file=hg.pid -E error.log
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
  sendall(167 from 167) -> (89) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6 from 6) -> (83) 1\\r\\n\x04\\r\\n (esc)
  sendall(9 from 9) -> (74) 4\r\nnone\r\n
  sendall(9 from 9) -> (65) 4\r\nHG20\r\n
  sendall(9 from 9) -> (56) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (47) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47 from 47) -> (0) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -14
  readline(65537) -> (2) \r\n (py3 !)
  write(167 from 167) -> (89) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(28 from 28) -> (91) Transfer-Encoding: chunked\r\n (no-py3 !)
  write(2 from 2) -> (89) \r\n (no-py3 !)
  write(6 from 6) -> (83) 1\\r\\n\x04\\r\\n (esc)
  write(9 from 9) -> (74) 4\r\nnone\r\n
  write(9 from 9) -> (65) 4\r\nHG20\r\n
  write(9 from 9) -> (56) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (47) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47 from 47) -> (0) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log

Server stops after bundle2 part payload chunk size

  $ hg serve --config badserver.closeaftersendbytes=1069 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  adding changesets
  transaction abort!
  rollback completed
  abort: HTTP request error (incomplete response) (py3 !)
  abort: HTTP request error (incomplete response; expected 466 bytes got 7) (no-py3 !)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -14
  sendall(167 from 167) -> (110) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6 from 6) -> (104) 1\\r\\n\x04\\r\\n (esc)
  sendall(9 from 9) -> (95) 4\r\nnone\r\n
  sendall(9 from 9) -> (86) 4\r\nHG20\r\n
  sendall(9 from 9) -> (77) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (68) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47 from 47) -> (21) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9 from 9) -> (12) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(12 from 473) -> (0) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1d (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -15
  write(167 from 167) -> (110) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(2 from 2) -> (110) \r\n (no-py3 !)
  write(6 from 6) -> (104) 1\\r\\n\x04\\r\\n (esc)
  write(9 from 9) -> (95) 4\r\nnone\r\n
  write(9 from 9) -> (86) 4\r\nHG20\r\n
  write(9 from 9) -> (77) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (68) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47 from 47) -> (21) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9 from 9) -> (12) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(12 from 473) -> (0) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1d (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log

Server stops sending in middle of bundle2 payload chunk

  $ hg serve --config badserver.closeaftersendbytes=1530 -p $HGPORT -d --pid-file=hg.pid -E error.log
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
  sendall(167 from 167) -> (571) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n
  sendall(6 from 6) -> (565) 1\\r\\n\x04\\r\\n (esc)
  sendall(9 from 9) -> (556) 4\r\nnone\r\n
  sendall(9 from 9) -> (547) 4\r\nHG20\r\n
  sendall(9 from 9) -> (538) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (529) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47 from 47) -> (482) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9 from 9) -> (473) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(473 from 473) -> (0) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -16
  readline(65537) -> (2) \r\n (py3 !)
  write(167 from 167) -> (571) HTTP/1.1 200 Script output follows\r\nServer: badhttpserver\r\nDate: $HTTP_DATE$\r\nContent-Type: application/mercurial-0.2\r\nTransfer-Encoding: chunked\r\n\r\n (py3 !)
  write(28 from 28) -> (573) Transfer-Encoding: chunked\r\n (no-py3 !)
  write(2 from 2) -> (571) \r\n (no-py3 !)
  write(6 from 6) -> (565) 1\\r\\n\x04\\r\\n (esc)
  write(9 from 9) -> (556) 4\r\nnone\r\n
  write(9 from 9) -> (547) 4\r\nHG20\r\n
  write(9 from 9) -> (538) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (529) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47 from 47) -> (482) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9 from 9) -> (473) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(473 from 473) -> (0) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log

Server stops sending after 0 length payload chunk size

  $ hg serve --config badserver.closeaftersendbytes=1561 -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid > $DAEMON_PIDS

  $ hg clone http://localhost:$HGPORT/ clone
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  transaction abort!
  rollback completed
  abort: HTTP request error (incomplete response) (py3 !)
  abort: HTTP request error (incomplete response; expected 32 bytes got 9) (no-py3 !)
  (this may be an intermittent network failure; if the error persists, consider contacting the network or server operator)
  [255]

  $ killdaemons.py $DAEMON_PIDS

#if py36
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -16
  sendall(6 from 6) -> (596) 1\\r\\n\x04\\r\\n (esc)
  sendall(9 from 9) -> (587) 4\r\nnone\r\n
  sendall(9 from 9) -> (578) 4\r\nHG20\r\n
  sendall(9 from 9) -> (569) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (560) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47 from 47) -> (513) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9 from 9) -> (504) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(473 from 473) -> (31) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (22) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (13) 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  sendall(13 from 38) -> (0) 20\\r\\n\x08LISTKEYS (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -17
  write(6 from 6) -> (596) 1\\r\\n\x04\\r\\n (esc)
  write(9 from 9) -> (587) 4\r\nnone\r\n
  write(9 from 9) -> (578) 4\r\nHG20\r\n
  write(9 from 9) -> (569) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (560) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47 from 47) -> (513) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9 from 9) -> (504) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(473 from 473) -> (31) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (22) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (13) 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  write(13 from 38) -> (0) 20\\r\\n\x08LISTKEYS (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log

Server stops sending after 0 part bundle part header (indicating end of bundle2 payload)
This is before the 0 size chunked transfer part that signals end of HTTP response.

  $ hg serve --config badserver.closeaftersendbytes=1736 -p $HGPORT -d --pid-file=hg.pid -E error.log
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
  sendall(9 from 9) -> (744) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (735) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47 from 47) -> (688) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9 from 9) -> (679) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(473 from 473) -> (206) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (197) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (188) 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  sendall(38 from 38) -> (150) 20\\r\\n\x08LISTKEYS\x00\x00\x00\x01\x01\x00	\x06namespacephases\\r\\n (esc)
  sendall(9 from 9) -> (141) 4\\r\\n\x00\x00\x00:\\r\\n (esc)
  sendall(64 from 64) -> (77) 3a\r\n96ee1d7354c4ad7372047672c36a1f561e3a6a4c	1\npublishing	True\r\n
  sendall(9 from 9) -> (68) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (59) 4\\r\\n\x00\x00\x00#\\r\\n (esc)
  sendall(41 from 41) -> (18) 23\\r\\n\x08LISTKEYS\x00\x00\x00\x02\x01\x00		namespacebookmarks\\r\\n (esc)
  sendall(9 from 9) -> (9) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (0) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -21
  write(9 from 9) -> (744) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (735) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47 from 47) -> (688) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9 from 9) -> (679) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(473 from 473) -> (206) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (197) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (188) 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  write(38 from 38) -> (150) 20\\r\\n\x08LISTKEYS\x00\x00\x00\x01\x01\x00	\x06namespacephases\\r\\n (esc)
  write(9 from 9) -> (141) 4\\r\\n\x00\x00\x00:\\r\\n (esc)
  write(64 from 64) -> (77) 3a\r\n96ee1d7354c4ad7372047672c36a1f561e3a6a4c	1\npublishing	True\r\n
  write(9 from 9) -> (68) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (59) 4\\r\\n\x00\x00\x00#\\r\\n (esc)
  write(41 from 41) -> (18) 23\\r\\n\x08LISTKEYS\x00\x00\x00\x02\x01\x00		namespacebookmarks\\r\\n (esc)
  write(9 from 9) -> (9) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (0) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log
  $ rm -rf clone

Server sends a size 0 chunked-transfer size without terminating \r\n

  $ hg serve --config badserver.closeaftersendbytes=1739 -p $HGPORT -d --pid-file=hg.pid -E error.log
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
  sendall(9 from 9) -> (747) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (738) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  sendall(47 from 47) -> (691) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  sendall(9 from 9) -> (682) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  sendall(473 from 473) -> (209) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (200) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (191) 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  sendall(38 from 38) -> (153) 20\\r\\n\x08LISTKEYS\x00\x00\x00\x01\x01\x00	\x06namespacephases\\r\\n (esc)
  sendall(9 from 9) -> (144) 4\\r\\n\x00\x00\x00:\\r\\n (esc)
  sendall(64 from 64) -> (80) 3a\r\n96ee1d7354c4ad7372047672c36a1f561e3a6a4c	1\npublishing	True\r\n
  sendall(9 from 9) -> (71) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (62) 4\\r\\n\x00\x00\x00#\\r\\n (esc)
  sendall(41 from 41) -> (21) 23\\r\\n\x08LISTKEYS\x00\x00\x00\x02\x01\x00		namespacebookmarks\\r\\n (esc)
  sendall(9 from 9) -> (12) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(9 from 9) -> (3) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  sendall(3 from 5) -> (0) 0\r\n
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  

#else
  $ "$PYTHON" $TESTDIR/filtertraceback.py < error.log | tail -22
  write(9 from 9) -> (747) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (738) 4\\r\\n\x00\x00\x00)\\r\\n (esc)
  write(47 from 47) -> (691) 29\\r\\n\x0bCHANGEGROUP\x00\x00\x00\x00\x01\x01\x07\x02	\x01version02nbchanges1\\r\\n (esc)
  write(9 from 9) -> (682) 4\\r\\n\x00\x00\x01\xd2\\r\\n (esc)
  write(473 from 473) -> (209) 1d2\\r\\n\x00\x00\x00\xb2\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00>6a3df4de388f3c4f8e28f4f9a814299a3cbb5f50\\ntest\\n0 0\\nfoo\\n\\ninitial\x00\x00\x00\x00\x00\x00\x00\xa1j=\xf4\xde8\x8f<O\x8e(\xf4\xf9\xa8\x14)\x9a<\xbb_P\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00-foo\x00b80de5d138758541c5f05265ad144ab9fa86d1db\\n\x00\x00\x00\x00\x00\x00\x00\x07foo\x00\x00\x00h\xb8\\r\xe5\xd18u\x85A\xc5\xf0Re\xad\x14J\xb9\xfa\x86\xd1\xdb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x96\xee\x1dsT\xc4\xadsr\x04vr\xc3j\x1fV\x1e:jL\x00\x00\x00\x00\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (200) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (191) 4\\r\\n\x00\x00\x00 \\r\\n (esc)
  write(38 from 38) -> (153) 20\\r\\n\x08LISTKEYS\x00\x00\x00\x01\x01\x00	\x06namespacephases\\r\\n (esc)
  write(9 from 9) -> (144) 4\\r\\n\x00\x00\x00:\\r\\n (esc)
  write(64 from 64) -> (80) 3a\r\n96ee1d7354c4ad7372047672c36a1f561e3a6a4c	1\npublishing	True\r\n
  write(9 from 9) -> (71) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (62) 4\\r\\n\x00\x00\x00#\\r\\n (esc)
  write(41 from 41) -> (21) 23\\r\\n\x08LISTKEYS\x00\x00\x00\x02\x01\x00		namespacebookmarks\\r\\n (esc)
  write(9 from 9) -> (12) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(9 from 9) -> (3) 4\\r\\n\x00\x00\x00\x00\\r\\n (esc)
  write(3 from 5) -> (0) 0\r\n
  write limit reached; closing socket
  $LOCALIP - - [$ERRDATE$] Exception happened during processing request '/?cmd=getbundle': (glob)
  Traceback (most recent call last):
  Exception: connection closed after sending N bytes
  
  write(27) -> 15\r\nInternal Server Error\r\n
#endif

  $ rm -f error.log
  $ rm -rf clone

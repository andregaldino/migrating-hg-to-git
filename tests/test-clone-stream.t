#require serve no-reposimplestore no-chg

#testcases stream-legacy stream-bundle2

#if stream-legacy
  $ cat << EOF >> $HGRCPATH
  > [server]
  > bundle2.stream = no
  > EOF
#endif

Initialize repository

  $ hg init server
  $ cd server
  $ sh $TESTDIR/testlib/stream_clone_setup.sh
  adding 00changelog-ab349180a0405010.nd
  adding 00changelog.d
  adding 00changelog.i
  adding 00changelog.n
  adding 00manifest.d
  adding 00manifest.i
  adding container/isam-build-centos7/bazel-coverage-generator-sandboxfs-compatibility-0758e3e4f6057904d44399bd666faba9e7f40686.patch
  adding data/foo.d
  adding data/foo.i
  adding data/foo.n
  adding data/undo.babar
  adding data/undo.d
  adding data/undo.foo.d
  adding data/undo.foo.i
  adding data/undo.foo.n
  adding data/undo.i
  adding data/undo.n
  adding data/undo.py
  adding foo.d
  adding foo.i
  adding foo.n
  adding meta/foo.d
  adding meta/foo.i
  adding meta/foo.n
  adding meta/undo.babar
  adding meta/undo.d
  adding meta/undo.foo.d
  adding meta/undo.foo.i
  adding meta/undo.foo.n
  adding meta/undo.i
  adding meta/undo.n
  adding meta/undo.py
  adding savanah/foo.d
  adding savanah/foo.i
  adding savanah/foo.n
  adding savanah/undo.babar
  adding savanah/undo.d
  adding savanah/undo.foo.d
  adding savanah/undo.foo.i
  adding savanah/undo.foo.n
  adding savanah/undo.i
  adding savanah/undo.n
  adding savanah/undo.py
  adding store/C\xc3\xa9lesteVille_is_a_Capital_City (esc)
  adding store/foo.d
  adding store/foo.i
  adding store/foo.n
  adding store/undo.babar
  adding store/undo.d
  adding store/undo.foo.d
  adding store/undo.foo.i
  adding store/undo.foo.n
  adding store/undo.i
  adding store/undo.n
  adding store/undo.py
  adding undo.babar
  adding undo.d
  adding undo.foo.d
  adding undo.foo.i
  adding undo.foo.n
  adding undo.i
  adding undo.n
  adding undo.py

  $ hg --config server.uncompressed=false serve -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid > $DAEMON_PIDS
  $ cd ..

Check local clone
==================

The logic is close enough of uncompressed.
This is present here to reuse the testing around file with "special" names.

  $ hg clone server local-clone
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved

Check that the clone went well

  $ hg verify -R local-clone
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files

Check uncompressed
==================

Cannot stream clone when server.uncompressed is set

  $ get-with-headers.py $LOCALIP:$HGPORT '?cmd=stream_out'
  200 Script output follows
  
  1

#if stream-legacy
  $ hg debugcapabilities http://localhost:$HGPORT
  Main capabilities:
    batch
    branchmap
    $USUAL_BUNDLE2_CAPS_SERVER$
    changegroupsubset
    compression=$BUNDLE2_COMPRESSIONS$
    getbundle
    httpheader=1024
    httpmediatype=0.1rx,0.1tx,0.2tx
    known
    lookup
    pushkey
    unbundle=HG10GZ,HG10BZ,HG10UN
    unbundlehash
  Bundle2 capabilities:
    HG20
    bookmarks
    changegroup
      01
      02
    checkheads
      related
    digests
      md5
      sha1
      sha512
    error
      abort
      unsupportedcontent
      pushraced
      pushkey
    hgtagsfnodes
    listkeys
    phases
      heads
    pushkey
    remote-changegroup
      http
      https

  $ hg clone --stream -U http://localhost:$HGPORT server-disabled
  warning: stream clone requested but server has them disabled
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 1088 changes to 1088 files
  new changesets 96ee1d7354c4:5223b5e3265f

  $ get-with-headers.py $LOCALIP:$HGPORT '?cmd=getbundle' content-type --bodyfile body --hgproto 0.2 --requestheader "x-hgarg-1=bundlecaps=HG20%2Cbundle2%3DHG20%250Abookmarks%250Achangegroup%253D01%252C02%250Adigests%253Dmd5%252Csha1%252Csha512%250Aerror%253Dabort%252Cunsupportedcontent%252Cpushraced%252Cpushkey%250Ahgtagsfnodes%250Alistkeys%250Aphases%253Dheads%250Apushkey%250Aremote-changegroup%253Dhttp%252Chttps&cg=0&common=0000000000000000000000000000000000000000&heads=c17445101a72edac06facd130d14808dfbd5c7c2&stream=1"
  200 Script output follows
  content-type: application/mercurial-0.2
  

  $ f --size body --hexdump --bytes 100
  body: size=232
  0000: 04 6e 6f 6e 65 48 47 32 30 00 00 00 00 00 00 00 |.noneHG20.......|
  0010: cf 0b 45 52 52 4f 52 3a 41 42 4f 52 54 00 00 00 |..ERROR:ABORT...|
  0020: 00 01 01 07 3c 04 72 6d 65 73 73 61 67 65 73 74 |....<.rmessagest|
  0030: 72 65 61 6d 20 64 61 74 61 20 72 65 71 75 65 73 |ream data reques|
  0040: 74 65 64 20 62 75 74 20 73 65 72 76 65 72 20 64 |ted but server d|
  0050: 6f 65 73 20 6e 6f 74 20 61 6c 6c 6f 77 20 74 68 |oes not allow th|
  0060: 69 73 20 66                                     |is f|

#endif
#if stream-bundle2
  $ hg debugcapabilities http://localhost:$HGPORT
  Main capabilities:
    batch
    branchmap
    $USUAL_BUNDLE2_CAPS_SERVER$
    changegroupsubset
    compression=$BUNDLE2_COMPRESSIONS$
    getbundle
    httpheader=1024
    httpmediatype=0.1rx,0.1tx,0.2tx
    known
    lookup
    pushkey
    unbundle=HG10GZ,HG10BZ,HG10UN
    unbundlehash
  Bundle2 capabilities:
    HG20
    bookmarks
    changegroup
      01
      02
    checkheads
      related
    digests
      md5
      sha1
      sha512
    error
      abort
      unsupportedcontent
      pushraced
      pushkey
    hgtagsfnodes
    listkeys
    phases
      heads
    pushkey
    remote-changegroup
      http
      https

  $ hg clone --stream -U http://localhost:$HGPORT server-disabled
  warning: stream clone requested but server has them disabled
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 1088 changes to 1088 files
  new changesets 96ee1d7354c4:5223b5e3265f

  $ get-with-headers.py $LOCALIP:$HGPORT '?cmd=getbundle' content-type --bodyfile body --hgproto 0.2 --requestheader "x-hgarg-1=bundlecaps=HG20%2Cbundle2%3DHG20%250Abookmarks%250Achangegroup%253D01%252C02%250Adigests%253Dmd5%252Csha1%252Csha512%250Aerror%253Dabort%252Cunsupportedcontent%252Cpushraced%252Cpushkey%250Ahgtagsfnodes%250Alistkeys%250Aphases%253Dheads%250Apushkey%250Aremote-changegroup%253Dhttp%252Chttps&cg=0&common=0000000000000000000000000000000000000000&heads=c17445101a72edac06facd130d14808dfbd5c7c2&stream=1"
  200 Script output follows
  content-type: application/mercurial-0.2
  

  $ f --size body --hexdump --bytes 100
  body: size=232
  0000: 04 6e 6f 6e 65 48 47 32 30 00 00 00 00 00 00 00 |.noneHG20.......|
  0010: cf 0b 45 52 52 4f 52 3a 41 42 4f 52 54 00 00 00 |..ERROR:ABORT...|
  0020: 00 01 01 07 3c 04 72 6d 65 73 73 61 67 65 73 74 |....<.rmessagest|
  0030: 72 65 61 6d 20 64 61 74 61 20 72 65 71 75 65 73 |ream data reques|
  0040: 74 65 64 20 62 75 74 20 73 65 72 76 65 72 20 64 |ted but server d|
  0050: 6f 65 73 20 6e 6f 74 20 61 6c 6c 6f 77 20 74 68 |oes not allow th|
  0060: 69 73 20 66                                     |is f|

#endif

  $ killdaemons.py
  $ cd server
  $ hg serve -p $HGPORT -d --pid-file=hg.pid --error errors.txt
  $ cat hg.pid > $DAEMON_PIDS
  $ cd ..

Basic clone

#if stream-legacy
  $ hg clone --stream -U http://localhost:$HGPORT clone1
  streaming all changes
  1090 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1090 files to transfer, 98.8 KB of data (zstd !)
  transferred 98.8 KB in * seconds (* */sec) (glob) (zstd !)
  searching for changes
  no changes found
  $ cat server/errors.txt
#endif
#if stream-bundle2
  $ hg clone --stream -U http://localhost:$HGPORT clone1
  streaming all changes
  1093 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1093 files to transfer, 98.9 KB of data (zstd !)
  transferred 98.9 KB in * seconds (* */sec) (glob) (zstd !)

  $ ls -1 clone1/.hg/cache
  branch2-base
  branch2-immutable
  branch2-served
  branch2-served.hidden
  branch2-visible
  branch2-visible-hidden
  rbc-names-v1
  rbc-revs-v1
  tags2
  tags2-served
  $ cat server/errors.txt
#endif

getbundle requests with stream=1 are uncompressed

  $ get-with-headers.py $LOCALIP:$HGPORT '?cmd=getbundle' content-type --bodyfile body --hgproto '0.1 0.2 comp=zlib,none' --requestheader "x-hgarg-1=bundlecaps=HG20%2Cbundle2%3DHG20%250Abookmarks%250Achangegroup%253D01%252C02%250Adigests%253Dmd5%252Csha1%252Csha512%250Aerror%253Dabort%252Cunsupportedcontent%252Cpushraced%252Cpushkey%250Ahgtagsfnodes%250Alistkeys%250Aphases%253Dheads%250Apushkey%250Aremote-changegroup%253Dhttp%252Chttps&cg=0&common=0000000000000000000000000000000000000000&heads=c17445101a72edac06facd130d14808dfbd5c7c2&stream=1"
  200 Script output follows
  content-type: application/mercurial-0.2
  

#if no-zstd no-rust
  $ f --size --hex --bytes 256 body
  body: size=119123
  0000: 04 6e 6f 6e 65 48 47 32 30 00 00 00 00 00 00 00 |.noneHG20.......|
  0010: 62 07 53 54 52 45 41 4d 32 00 00 00 00 03 00 09 |b.STREAM2.......|
  0020: 06 09 04 0c 26 62 79 74 65 63 6f 75 6e 74 31 30 |....&bytecount10|
  0030: 34 31 31 35 66 69 6c 65 63 6f 75 6e 74 31 30 39 |4115filecount109|
  0040: 33 72 65 71 75 69 72 65 6d 65 6e 74 73 67 65 6e |3requirementsgen|
  0050: 65 72 61 6c 64 65 6c 74 61 25 32 43 72 65 76 6c |eraldelta%2Crevl|
  0060: 6f 67 76 31 25 32 43 73 70 61 72 73 65 72 65 76 |ogv1%2Csparserev|
  0070: 6c 6f 67 00 00 80 00 73 08 42 64 61 74 61 2f 30 |log....s.Bdata/0|
  0080: 2e 69 00 03 00 01 00 00 00 00 00 00 00 02 00 00 |.i..............|
  0090: 00 01 00 00 00 00 00 00 00 01 ff ff ff ff ff ff |................|
  00a0: ff ff 80 29 63 a0 49 d3 23 87 bf ce fe 56 67 92 |...)c.I.#....Vg.|
  00b0: 67 2c 69 d1 ec 39 00 00 00 00 00 00 00 00 00 00 |g,i..9..........|
  00c0: 00 00 75 30 73 26 45 64 61 74 61 2f 30 30 63 68 |..u0s&Edata/00ch|
  00d0: 61 6e 67 65 6c 6f 67 2d 61 62 33 34 39 31 38 30 |angelog-ab349180|
  00e0: 61 30 34 30 35 30 31 30 2e 6e 64 2e 69 00 03 00 |a0405010.nd.i...|
  00f0: 01 00 00 00 00 00 00 00 05 00 00 00 04 00 00 00 |................|
#endif
#if zstd no-rust
  $ f --size --hex --bytes 256 body
  body: size=116310 (no-bigendian !)
  body: size=116305 (bigendian !)
  0000: 04 6e 6f 6e 65 48 47 32 30 00 00 00 00 00 00 00 |.noneHG20.......|
  0010: 7c 07 53 54 52 45 41 4d 32 00 00 00 00 03 00 09 ||.STREAM2.......|
  0020: 06 09 04 0c 40 62 79 74 65 63 6f 75 6e 74 31 30 |....@bytecount10|
  0030: 31 32 37 36 66 69 6c 65 63 6f 75 6e 74 31 30 39 |1276filecount109| (no-bigendian !)
  0030: 31 32 37 31 66 69 6c 65 63 6f 75 6e 74 31 30 39 |1271filecount109| (bigendian !)
  0040: 33 72 65 71 75 69 72 65 6d 65 6e 74 73 67 65 6e |3requirementsgen|
  0050: 65 72 61 6c 64 65 6c 74 61 25 32 43 72 65 76 6c |eraldelta%2Crevl|
  0060: 6f 67 2d 63 6f 6d 70 72 65 73 73 69 6f 6e 2d 7a |og-compression-z|
  0070: 73 74 64 25 32 43 72 65 76 6c 6f 67 76 31 25 32 |std%2Crevlogv1%2|
  0080: 43 73 70 61 72 73 65 72 65 76 6c 6f 67 00 00 80 |Csparserevlog...|
  0090: 00 73 08 42 64 61 74 61 2f 30 2e 69 00 03 00 01 |.s.Bdata/0.i....|
  00a0: 00 00 00 00 00 00 00 02 00 00 00 01 00 00 00 00 |................|
  00b0: 00 00 00 01 ff ff ff ff ff ff ff ff 80 29 63 a0 |.............)c.|
  00c0: 49 d3 23 87 bf ce fe 56 67 92 67 2c 69 d1 ec 39 |I.#....Vg.g,i..9|
  00d0: 00 00 00 00 00 00 00 00 00 00 00 00 75 30 73 26 |............u0s&|
  00e0: 45 64 61 74 61 2f 30 30 63 68 61 6e 67 65 6c 6f |Edata/00changelo|
  00f0: 67 2d 61 62 33 34 39 31 38 30 61 30 34 30 35 30 |g-ab349180a04050|
#endif
#if zstd rust no-dirstate-v2
  $ f --size --hex --bytes 256 body
  body: size=116310
  0000: 04 6e 6f 6e 65 48 47 32 30 00 00 00 00 00 00 00 |.noneHG20.......|
  0010: 7c 07 53 54 52 45 41 4d 32 00 00 00 00 03 00 09 ||.STREAM2.......|
  0020: 06 09 04 0c 40 62 79 74 65 63 6f 75 6e 74 31 30 |....@bytecount10|
  0030: 31 32 37 36 66 69 6c 65 63 6f 75 6e 74 31 30 39 |1276filecount109|
  0040: 33 72 65 71 75 69 72 65 6d 65 6e 74 73 67 65 6e |3requirementsgen|
  0050: 65 72 61 6c 64 65 6c 74 61 25 32 43 72 65 76 6c |eraldelta%2Crevl|
  0060: 6f 67 2d 63 6f 6d 70 72 65 73 73 69 6f 6e 2d 7a |og-compression-z|
  0070: 73 74 64 25 32 43 72 65 76 6c 6f 67 76 31 25 32 |std%2Crevlogv1%2|
  0080: 43 73 70 61 72 73 65 72 65 76 6c 6f 67 00 00 80 |Csparserevlog...|
  0090: 00 73 08 42 64 61 74 61 2f 30 2e 69 00 03 00 01 |.s.Bdata/0.i....|
  00a0: 00 00 00 00 00 00 00 02 00 00 00 01 00 00 00 00 |................|
  00b0: 00 00 00 01 ff ff ff ff ff ff ff ff 80 29 63 a0 |.............)c.|
  00c0: 49 d3 23 87 bf ce fe 56 67 92 67 2c 69 d1 ec 39 |I.#....Vg.g,i..9|
  00d0: 00 00 00 00 00 00 00 00 00 00 00 00 75 30 73 26 |............u0s&|
  00e0: 45 64 61 74 61 2f 30 30 63 68 61 6e 67 65 6c 6f |Edata/00changelo|
  00f0: 67 2d 61 62 33 34 39 31 38 30 61 30 34 30 35 30 |g-ab349180a04050|
#endif
#if zstd dirstate-v2
  $ f --size --hex --bytes 256 body
  body: size=109549
  0000: 04 6e 6f 6e 65 48 47 32 30 00 00 00 00 00 00 00 |.noneHG20.......|
  0010: c0 07 53 54 52 45 41 4d 32 00 00 00 00 03 00 09 |..STREAM2.......|
  0020: 05 09 04 0c 85 62 79 74 65 63 6f 75 6e 74 39 35 |.....bytecount95|
  0030: 38 39 37 66 69 6c 65 63 6f 75 6e 74 31 30 33 30 |897filecount1030|
  0040: 72 65 71 75 69 72 65 6d 65 6e 74 73 64 6f 74 65 |requirementsdote|
  0050: 6e 63 6f 64 65 25 32 43 65 78 70 2d 64 69 72 73 |ncode%2Cexp-dirs|
  0060: 74 61 74 65 2d 76 32 25 32 43 66 6e 63 61 63 68 |tate-v2%2Cfncach|
  0070: 65 25 32 43 67 65 6e 65 72 61 6c 64 65 6c 74 61 |e%2Cgeneraldelta|
  0080: 25 32 43 70 65 72 73 69 73 74 65 6e 74 2d 6e 6f |%2Cpersistent-no|
  0090: 64 65 6d 61 70 25 32 43 72 65 76 6c 6f 67 2d 63 |demap%2Crevlog-c|
  00a0: 6f 6d 70 72 65 73 73 69 6f 6e 2d 7a 73 74 64 25 |ompression-zstd%|
  00b0: 32 43 72 65 76 6c 6f 67 76 31 25 32 43 73 70 61 |2Crevlogv1%2Cspa|
  00c0: 72 73 65 72 65 76 6c 6f 67 25 32 43 73 74 6f 72 |rserevlog%2Cstor|
  00d0: 65 00 00 80 00 73 08 42 64 61 74 61 2f 30 2e 69 |e....s.Bdata/0.i|
  00e0: 00 03 00 01 00 00 00 00 00 00 00 02 00 00 00 01 |................|
  00f0: 00 00 00 00 00 00 00 01 ff ff ff ff ff ff ff ff |................|
#endif

--uncompressed is an alias to --stream

#if stream-legacy
  $ hg clone --uncompressed -U http://localhost:$HGPORT clone1-uncompressed
  streaming all changes
  1090 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1090 files to transfer, 98.8 KB of data (zstd !)
  transferred 98.8 KB in * seconds (* */sec) (glob) (zstd !)
  searching for changes
  no changes found
#endif
#if stream-bundle2
  $ hg clone --uncompressed -U http://localhost:$HGPORT clone1-uncompressed
  streaming all changes
  1093 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1093 files to transfer, 98.9 KB of data (zstd !)
  transferred 98.9 KB in * seconds (* */sec) (glob) (zstd !)
#endif

Clone with background file closing enabled

#if stream-legacy
  $ hg --debug --config worker.backgroundclose=true --config worker.backgroundcloseminfilecount=1 clone --stream -U http://localhost:$HGPORT clone-background | grep -v adding
  using http://localhost:$HGPORT/
  sending capabilities command
  sending branchmap command
  streaming all changes
  sending stream_out command
  1090 files to transfer, 102 KB of data (no-zstd !)
  1090 files to transfer, 98.8 KB of data (zstd !)
  starting 4 threads for background file closing
  updating the branch cache
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  transferred 98.8 KB in * seconds (* */sec) (glob) (zstd !)
  query 1; heads
  sending batch command
  searching for changes
  all remote heads known locally
  no changes found
  sending getbundle command
  bundle2-input-bundle: with-transaction
  bundle2-input-part: "listkeys" (params: 1 mandatory) supported
  bundle2-input-part: "phase-heads" supported
  bundle2-input-part: total payload size 24
  bundle2-input-bundle: 2 parts total
  checking for updated bookmarks
  updating the branch cache
  (sent 5 HTTP requests and * bytes; received * bytes in responses) (glob)
#endif
#if stream-bundle2
  $ hg --debug --config worker.backgroundclose=true --config worker.backgroundcloseminfilecount=1 clone --stream -U http://localhost:$HGPORT clone-background | grep -v adding
  using http://localhost:$HGPORT/
  sending capabilities command
  query 1; heads
  sending batch command
  streaming all changes
  sending getbundle command
  bundle2-input-bundle: with-transaction
  bundle2-input-part: "stream2" (params: 3 mandatory) supported
  applying stream bundle
  1093 files to transfer, 102 KB of data (no-zstd !)
  1093 files to transfer, 98.9 KB of data (zstd !)
  starting 4 threads for background file closing
  starting 4 threads for background file closing
  updating the branch cache
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  bundle2-input-part: total payload size 118984 (no-zstd !)
  transferred 98.9 KB in * seconds (* */sec) (glob) (zstd !)
  bundle2-input-part: total payload size 116145 (zstd no-bigendian !)
  bundle2-input-part: total payload size 116140 (zstd bigendian !)
  bundle2-input-part: "listkeys" (params: 1 mandatory) supported
  bundle2-input-bundle: 2 parts total
  checking for updated bookmarks
  updating the branch cache
  (sent 3 HTTP requests and * bytes; received * bytes in responses) (glob)
#endif

Cannot stream clone when there are secret changesets

  $ hg -R server phase --force --secret -r tip
  $ hg clone --stream -U http://localhost:$HGPORT secret-denied
  warning: stream clone requested but server has them disabled
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 1025 changes to 1025 files
  new changesets 96ee1d7354c4:c17445101a72

  $ killdaemons.py

Streaming of secrets can be overridden by server config

  $ cd server
  $ hg serve --config server.uncompressedallowsecret=true -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid > $DAEMON_PIDS
  $ cd ..

#if stream-legacy
  $ hg clone --stream -U http://localhost:$HGPORT secret-allowed
  streaming all changes
  1090 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1090 files to transfer, 98.8 KB of data (zstd !)
  transferred 98.8 KB in * seconds (* */sec) (glob) (zstd !)
  searching for changes
  no changes found
#endif
#if stream-bundle2
  $ hg clone --stream -U http://localhost:$HGPORT secret-allowed
  streaming all changes
  1093 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1093 files to transfer, 98.9 KB of data (zstd !)
  transferred 98.9 KB in * seconds (* */sec) (glob) (zstd !)
#endif

  $ killdaemons.py

Verify interaction between preferuncompressed and secret presence

  $ cd server
  $ hg serve --config server.preferuncompressed=true -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid > $DAEMON_PIDS
  $ cd ..

  $ hg clone -U http://localhost:$HGPORT preferuncompressed-secret
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 1025 changes to 1025 files
  new changesets 96ee1d7354c4:c17445101a72

  $ killdaemons.py

Clone not allowed when full bundles disabled and can't serve secrets

  $ cd server
  $ hg serve --config server.disablefullbundle=true -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid > $DAEMON_PIDS
  $ cd ..

  $ hg clone --stream http://localhost:$HGPORT secret-full-disabled
  warning: stream clone requested but server has them disabled
  requesting all changes
  remote: abort: server has pull-based clones disabled
  abort: pull failed on remote
  (remove --pull if specified or upgrade Mercurial)
  [100]

Local stream clone with secrets involved
(This is just a test over behavior: if you have access to the repo's files,
there is no security so it isn't important to prevent a clone here.)

  $ hg clone -U --stream server local-secret
  warning: stream clone requested but server has them disabled
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 1025 changes to 1025 files
  new changesets 96ee1d7354c4:c17445101a72

Stream clone while repo is changing:

  $ mkdir changing
  $ cd changing

extension for delaying the server process so we reliably can modify the repo
while cloning

  $ cat > stream_steps.py <<EOF
  > import os
  > import sys
  > from mercurial import (
  >     encoding,
  >     extensions,
  >     streamclone,
  >     testing,
  > )
  > WALKED_FILE_1 = encoding.environ[b'HG_TEST_STREAM_WALKED_FILE_1']
  > WALKED_FILE_2 = encoding.environ[b'HG_TEST_STREAM_WALKED_FILE_2']
  > 
  > def _test_sync_point_walk_1(orig, repo):
  >     testing.write_file(WALKED_FILE_1)
  > 
  > def _test_sync_point_walk_2(orig, repo):
  >     assert repo._currentlock(repo._lockref) is None
  >     testing.wait_file(WALKED_FILE_2)
  > 
  > extensions.wrapfunction(
  >     streamclone,
  >     '_test_sync_point_walk_1',
  >     _test_sync_point_walk_1
  > )
  > extensions.wrapfunction(
  >     streamclone,
  >     '_test_sync_point_walk_2',
  >     _test_sync_point_walk_2
  > )
  > EOF

prepare repo with small and big file to cover both code paths in emitrevlogdata

  $ hg init repo
  $ touch repo/f1
  $ $TESTDIR/seq.py 50000 > repo/f2
  $ hg -R repo ci -Aqm "0"
  $ HG_TEST_STREAM_WALKED_FILE_1="$TESTTMP/sync_file_walked_1"
  $ export HG_TEST_STREAM_WALKED_FILE_1
  $ HG_TEST_STREAM_WALKED_FILE_2="$TESTTMP/sync_file_walked_2"
  $ export HG_TEST_STREAM_WALKED_FILE_2
  $ HG_TEST_STREAM_WALKED_FILE_3="$TESTTMP/sync_file_walked_3"
  $ export HG_TEST_STREAM_WALKED_FILE_3
#   $ cat << EOF >> $HGRCPATH
#   > [hooks]
#   > pre-clone=rm -f "$TESTTMP/sync_file_walked_*"
#   > EOF
  $ hg serve -R repo -p $HGPORT1 -d --error errors.log --pid-file=hg.pid --config extensions.stream_steps="$RUNTESTDIR/testlib/ext-stream-clone-steps.py"
  $ cat hg.pid >> $DAEMON_PIDS

clone while modifying the repo between stating file with write lock and
actually serving file content

  $ (hg clone -q --stream -U http://localhost:$HGPORT1 clone; touch "$HG_TEST_STREAM_WALKED_FILE_3") &
  $ $RUNTESTDIR/testlib/wait-on-file 10 $HG_TEST_STREAM_WALKED_FILE_1
  $ echo >> repo/f1
  $ echo >> repo/f2
  $ hg -R repo ci -m "1" --config ui.timeout.warn=-1
  $ touch $HG_TEST_STREAM_WALKED_FILE_2
  $ $RUNTESTDIR/testlib/wait-on-file 10 $HG_TEST_STREAM_WALKED_FILE_3
  $ hg -R clone id
  000000000000
  $ cat errors.log
  $ cd ..

Stream repository with bookmarks
--------------------------------

(revert introduction of secret changeset)

  $ hg -R server phase --draft 'secret()'

add a bookmark

  $ hg -R server bookmark -r tip some-bookmark

clone it

#if stream-legacy
  $ hg clone --stream http://localhost:$HGPORT with-bookmarks
  streaming all changes
  1090 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1090 files to transfer, 98.8 KB of data (zstd !)
  transferred 98.8 KB in * seconds (* */sec) (glob) (zstd !)
  searching for changes
  no changes found
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved
#endif
#if stream-bundle2
  $ hg clone --stream http://localhost:$HGPORT with-bookmarks
  streaming all changes
  1096 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1096 files to transfer, 99.1 KB of data (zstd !)
  transferred 99.1 KB in * seconds (* */sec) (glob) (zstd !)
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved
#endif
  $ hg verify -R with-bookmarks
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg -R with-bookmarks bookmarks
     some-bookmark             2:5223b5e3265f

Stream repository with phases
-----------------------------

Clone as publishing

  $ hg -R server phase -r 'all()'
  0: draft
  1: draft
  2: draft

#if stream-legacy
  $ hg clone --stream http://localhost:$HGPORT phase-publish
  streaming all changes
  1090 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1090 files to transfer, 98.8 KB of data (zstd !)
  transferred 98.8 KB in * seconds (* */sec) (glob) (zstd !)
  searching for changes
  no changes found
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved
#endif
#if stream-bundle2
  $ hg clone --stream http://localhost:$HGPORT phase-publish
  streaming all changes
  1096 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1096 files to transfer, 99.1 KB of data (zstd !)
  transferred 99.1 KB in * seconds (* */sec) (glob) (zstd !)
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved
#endif
  $ hg verify -R phase-publish
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files
  $ hg -R phase-publish phase -r 'all()'
  0: public
  1: public
  2: public

Clone as non publishing

  $ cat << EOF >> server/.hg/hgrc
  > [phases]
  > publish = False
  > EOF
  $ killdaemons.py
  $ hg -R server serve -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid > $DAEMON_PIDS

#if stream-legacy

With v1 of the stream protocol, changeset are always cloned as public. It make
stream v1 unsuitable for non-publishing repository.

  $ hg clone --stream http://localhost:$HGPORT phase-no-publish
  streaming all changes
  1090 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1090 files to transfer, 98.8 KB of data (zstd !)
  transferred 98.8 KB in * seconds (* */sec) (glob) (zstd !)
  searching for changes
  no changes found
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R phase-no-publish phase -r 'all()'
  0: public
  1: public
  2: public
#endif
#if stream-bundle2
  $ hg clone --stream http://localhost:$HGPORT phase-no-publish
  streaming all changes
  1097 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1097 files to transfer, 99.1 KB of data (zstd !)
  transferred 99.1 KB in * seconds (* */sec) (glob) (zstd !)
  updating to branch default
  1088 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R phase-no-publish phase -r 'all()'
  0: draft
  1: draft
  2: draft
#endif
  $ hg verify -R phase-no-publish
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 3 changesets with 1088 changes to 1088 files

  $ killdaemons.py

#if stream-legacy

With v1 of the stream protocol, changeset are always cloned as public. There's
no obsolescence markers exchange in stream v1.

#endif
#if stream-bundle2

Stream repository with obsolescence
-----------------------------------

Clone non-publishing with obsolescence

  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > evolution=all
  > EOF

  $ cd server
  $ echo foo > foo
  $ hg -q commit -m 'about to be pruned'
  $ hg debugobsolete `hg log -r . -T '{node}'` -d '0 0' -u test --record-parents
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg up null -q
  $ hg log -T '{rev}: {phase}\n'
  2: draft
  1: draft
  0: draft
  $ hg serve -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid > $DAEMON_PIDS
  $ cd ..

  $ hg clone -U --stream http://localhost:$HGPORT with-obsolescence
  streaming all changes
  1098 files to transfer, 102 KB of data (no-zstd !)
  transferred 102 KB in * seconds (* */sec) (glob) (no-zstd !)
  1098 files to transfer, 99.5 KB of data (zstd !)
  transferred 99.5 KB in * seconds (* */sec) (glob) (zstd !)
  $ hg -R with-obsolescence log -T '{rev}: {phase}\n'
  2: draft
  1: draft
  0: draft
  $ hg debugobsolete -R with-obsolescence
  8c206a663911c1f97f2f9d7382e417ae55872cfa 0 {5223b5e3265f0df40bb743da62249413d74ac70f} (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  $ hg verify -R with-obsolescence
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 4 changesets with 1089 changes to 1088 files

  $ hg clone -U --stream --config experimental.evolution=0 http://localhost:$HGPORT with-obsolescence-no-evolution
  streaming all changes
  remote: abort: server has obsolescence markers, but client cannot receive them via stream clone
  abort: pull failed on remote
  [100]

  $ killdaemons.py

#endif

Cloning a repo with no requirements doesn't give some obscure error

  $ mkdir -p empty-repo/.hg
  $ hg clone -q --stream ssh://user@dummy/empty-repo empty-repo2
  $ hg --cwd empty-repo2 verify -q

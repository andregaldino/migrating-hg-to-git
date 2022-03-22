#require no-chg

  $ hg init repo
  $ cd repo
  $ hg debugbuilddag '+3<3+1'

  $ hg log
  changeset:   3:6100d3090acf
  tag:         tip
  parent:      0:1ea73414a91b
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:03 1970 +0000
  summary:     r3
  
  changeset:   2:01241442b3c2
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:02 1970 +0000
  summary:     r2
  
  changeset:   1:66f7d451a68b
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:01 1970 +0000
  summary:     r1
  
  changeset:   0:1ea73414a91b
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     r0
  
  $ cd ..

Test pullbundle functionality

  $ cd repo
  $ cat <<EOF > .hg/hgrc
  > [server]
  > pullbundle = True
  > [experimental]
  > evolution = True
  > [extensions]
  > blackbox =
  > EOF
  $ hg bundle --base null -r 0 .hg/0.hg
  1 changesets found
  $ hg bundle --base 0 -r 1 .hg/1.hg
  1 changesets found
  $ hg bundle --base 1 -r 2 .hg/2.hg
  1 changesets found
  $ hg bundle --base 1 -r 3 .hg/3.hg
  1 changesets found
  $ cat <<EOF > .hg/pullbundles.manifest
  > 3.hg BUNDLESPEC=none-v2 heads=6100d3090acf50ed11ec23196cec20f5bd7323aa bases=1ea73414a91b0920940797d8fc6a11e447f8ea1e
  > 2.hg BUNDLESPEC=none-v2 heads=01241442b3c2bf3211e593b549c655ea65b295e3 bases=66f7d451a68b85ed82ff5fcc254daf50c74144bd
  > 1.hg BUNDLESPEC=bzip2-v2 heads=66f7d451a68b85ed82ff5fcc254daf50c74144bd bases=1ea73414a91b0920940797d8fc6a11e447f8ea1e
  > 0.hg BUNDLESPEC=gzip-v2 heads=1ea73414a91b0920940797d8fc6a11e447f8ea1e
  > EOF
  $ hg --config blackbox.track=debug --debug serve -p $HGPORT2 -d --pid-file=../repo.pid -E ../error.txt
  listening at http://*:$HGPORT2/ (bound to $LOCALIP:$HGPORT2) (glob) (?)
  $ cat ../repo.pid >> $DAEMON_PIDS
  $ cd ..
  $ hg clone -r 0 http://localhost:$HGPORT2/ repo.pullbundle
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b (1 drafts)
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cat error.txt
  $ cd repo.pullbundle
  $ hg pull -r 1
  pulling from http://localhost:$HGPORT2/
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  new changesets 66f7d451a68b (1 drafts)
  (run 'hg update' to get a working copy)
  $ hg pull -r 3
  pulling from http://localhost:$HGPORT2/
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files (+1 heads)
  new changesets 6100d3090acf (1 drafts)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ cd ..
  $ killdaemons.py
  $ grep 'sending pullbundle ' repo/.hg/blackbox.log
  * sending pullbundle "0.hg" (glob)
  * sending pullbundle "1.hg" (glob)
  * sending pullbundle "3.hg" (glob)
  $ rm repo/.hg/blackbox.log

Test pullbundle functionality for incremental pulls

  $ cd repo
  $ hg --config blackbox.track=debug --debug serve -p $HGPORT2 -d --pid-file=../repo.pid
  listening at http://*:$HGPORT2/ (bound to $LOCALIP:$HGPORT2) (glob) (?)
  $ cat ../repo.pid >> $DAEMON_PIDS
  $ cd ..
  $ hg clone http://localhost:$HGPORT2/ repo.pullbundle2
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  adding changesets
  adding manifests
  adding file changes
  adding changesets
  adding manifests
  adding file changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 0 changes to 0 files (+1 heads)
  new changesets 1ea73414a91b:01241442b3c2 (4 drafts)
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ killdaemons.py
  $ grep 'sending pullbundle ' repo/.hg/blackbox.log
  * sending pullbundle "0.hg" (glob)
  * sending pullbundle "3.hg" (glob)
  * sending pullbundle "1.hg" (glob)
  * sending pullbundle "2.hg" (glob)
  $ rm repo/.hg/blackbox.log

Test pullbundle functionality for incoming

  $ cd repo
  $ hg --config blackbox.track=debug --debug serve -p $HGPORT2 -d --pid-file=../repo.pid
  listening at http://*:$HGPORT2/ (bound to $LOCALIP:$HGPORT2) (glob) (?)
  $ cat ../repo.pid >> $DAEMON_PIDS
  $ cd ..
  $ hg clone http://localhost:$HGPORT2/ repo.pullbundle2a -r 0
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b (1 drafts)
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd repo.pullbundle2a
  $ hg incoming -r 66f7d451a68b
  comparing with http://localhost:$HGPORT2/
  searching for changes
  changeset:   1:66f7d451a68b
  tag:         tip
  user:        debugbuilddag
  date:        Thu Jan 01 00:00:01 1970 +0000
  summary:     r1
  
  $ cd ..
  $ killdaemons.py
  $ grep 'sending pullbundle ' repo/.hg/blackbox.log
  * sending pullbundle "0.hg" (glob)
  * sending pullbundle "1.hg" (glob)
  $ rm repo/.hg/blackbox.log

Test recovery from misconfigured server sending no new data

  $ cd repo
  $ cat <<EOF > .hg/pullbundles.manifest
  > 0.hg heads=66f7d451a68b85ed82ff5fcc254daf50c74144bd bases=1ea73414a91b0920940797d8fc6a11e447f8ea1e
  > 0.hg heads=1ea73414a91b0920940797d8fc6a11e447f8ea1e
  > EOF
  $ hg --config blackbox.track=debug --debug serve -p $HGPORT2 -d --pid-file=../repo.pid
  listening at http://*:$HGPORT2/ (bound to $LOCALIP:$HGPORT2) (glob) (?)
  $ cat ../repo.pid >> $DAEMON_PIDS
  $ cd ..
  $ hg clone -r 0 http://localhost:$HGPORT2/ repo.pullbundle3
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b (1 drafts)
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd repo.pullbundle3
  $ hg pull -r 1
  pulling from http://localhost:$HGPORT2/
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  abort: 00changelog@66f7d451a68b85ed82ff5fcc254daf50c74144bd: no node
  [50]
  $ cd ..
  $ killdaemons.py
  $ grep 'sending pullbundle ' repo/.hg/blackbox.log
  * sending pullbundle "0.hg" (glob)
  * sending pullbundle "0.hg" (glob)
  $ rm repo/.hg/blackbox.log

Test processing when nodes used in the pullbundles.manifest end up being hidden

  $ hg --repo repo debugobsolete ed1b79f46b9a29f5a6efa59cf12fcfca43bead5a
  1 new obsolescence markers
  $ hg serve --repo repo --config server.view=visible -p $HGPORT -d --pid-file=hg.pid -E errors.log
  $ cat hg.pid >> $DAEMON_PIDS
  $ hg clone http://localhost:$HGPORT repo-obs
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b (1 drafts)
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ killdaemons.py

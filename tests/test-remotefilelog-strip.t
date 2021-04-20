#require no-windows

  $ . "$TESTDIR/remotefilelog-library.sh"

  $ hg init master
  $ cd master
  $ cat >> .hg/hgrc <<EOF
  > [remotefilelog]
  > server=True
  > EOF
  $ echo x > x
  $ hg commit -qAm x

  $ cd ..

  $ hgcloneshallow ssh://user@dummy/master shallow -q
  1 files fetched over 1 fetches - (1 misses, 0.00% hit ratio) over *s (glob)
  $ cd shallow

  $ cat >> $TESTTMP/get_file_linknode.py <<EOF
  > from mercurial import node, registrar, scmutil
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'debug-file-linknode', [(b'r', b'rev', b'.', b'rev')], b'hg debug-file-linknode FILE')
  > def debug_file_linknode(ui, repo, file, **opts):
  >   rflctx = scmutil.revsingle(repo.unfiltered(), opts['rev']).filectx(file)
  >   ui.status(b'%s\n' % node.hex(rflctx.ancestormap()[rflctx._filenode][2]))
  > EOF

  $ cat >> .hg/hgrc <<EOF
  > [ui]
  > interactive=1
  > [extensions]
  > strip=
  > get_file_linknode=$TESTTMP/get_file_linknode.py
  > [experimental]
  > evolution=createmarkers,allowunstable
  > EOF
  $ echo a > a
  $ hg commit -qAm msg1
  $ hg commit --amend 're:^$' -m msg2
  $ hg commit --amend 're:^$' -m msg3
  $ hg --hidden log -G -T '{rev} {node|short}'
  @  3 df91f74b871e
  |
  | x  2 70494d7ec5ef
  |/
  | x  1 1e423846dde0
  |/
  o  0 b292c1e3311f
  
  $ hg debug-file-linknode -r 70494d a
  df91f74b871e064c89afa1fe9e2f66afa2c125df
  $ hg --hidden strip -r 1 3
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  saved backup bundle to $TESTTMP/shallow/.hg/strip-backup/df91f74b871e-c94d67be-backup.hg

  $ hg --hidden log -G -T '{rev} {node|short}'
  o  1 70494d7ec5ef
  |
  @  0 b292c1e3311f
  
Demonstrate that the linknode points to a commit that is actually in the repo
after the strip operation. Otherwise remotefilelog has to search every commit in
the repository looking for a valid linkrev every time it's queried, such as
during push.
  $ hg debug-file-linknode -r 70494d a
  70494d7ec5ef6cd3cd6939a9fd2812f9956bf553

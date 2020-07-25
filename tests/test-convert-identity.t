Testing that convert.hg.preserve-hash=true can be used to make hg
convert from hg repo to hg repo preserve hashes, even if the
computation of the files list in commits change slightly between hg
versions.

  $ cat <<'EOF' >> "$HGRCPATH"
  > [extensions]
  > convert =
  > EOF
  $ cat <<'EOF' > changefileslist.py
  > from mercurial import (changelog, extensions, metadata)
  > def wrap(orig, clog, manifest, files, *args, **kwargs):
  >   files = metadata.ChangingFiles(touched=[b"a"])
  >   return orig(clog, manifest, files, *args, **kwargs)
  > def extsetup(ui):
  >   extensions.wrapfunction(changelog.changelog, 'add', wrap)
  > EOF

  $ hg init repo
  $ cd repo
  $ echo a > a; hg commit -qAm a
  $ echo b > a; hg commit -qAm b
  $ hg up -qr 0; echo c > c; hg commit -qAm c
  $ hg merge -qr 1
  $ hg commit -m_ --config extensions.x=../changefileslist.py
  $ hg log -r . -T '{node|short} {files|json}\n'
  c085bbe93d59 ["a"]

Now that we have a commit with a files list that's not what the
current hg version would create, check that convert either fixes it or
keeps it depending on config:

  $ hg convert -q . ../convert
  $ hg --cwd ../convert log -r tip -T '{node|short} {files|json}\n'
  b7c4d4bbacd3 []
  $ rm -rf ../convert

  $ hg convert -q . ../convert --config convert.hg.preserve-hash=true
  $ hg --cwd ../convert log -r tip -T '{node|short} {files|json}\n'
  c085bbe93d59 ["a"]
  $ rm -rf ../convert

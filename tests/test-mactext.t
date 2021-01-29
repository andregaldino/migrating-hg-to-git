
  $ cat > unix2mac.py <<EOF
  > import sys
  > 
  > for path in sys.argv[1:]:
  >     data = open(path, 'rb').read()
  >     data = data.replace(b'\n', b'\r')
  >     open(path, 'wb').write(data)
  > EOF
  $ hg init
  $ echo '[hooks]' >> .hg/hgrc
  $ echo 'pretxncommit.cr = python:hgext.win32text.forbidcr' >> .hg/hgrc
  $ echo 'pretxnchangegroup.cr = python:hgext.win32text.forbidcr' >> .hg/hgrc
  $ cat .hg/hgrc
  [hooks]
  pretxncommit.cr = python:hgext.win32text.forbidcr
  pretxnchangegroup.cr = python:hgext.win32text.forbidcr

  $ echo hello > f
  $ hg add f
  $ hg ci -m 1

  $ "$PYTHON" unix2mac.py f
  $ hg ci -m 2
  attempt to commit or push text file(s) using CR line endings
  in dea860dc51ec: f
  transaction abort!
  rollback completed
  abort: pretxncommit.cr hook failed
  [40]
  $ hg cat f | f --hexdump
  
  0000: 68 65 6c 6c 6f 0a                               |hello.|
  $ f --hexdump f
  f:
  0000: 68 65 6c 6c 6f 0d                               |hello.|

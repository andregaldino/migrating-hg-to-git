MEDIATYPE=application/mercurial-exp-framing-0006

sendhttpraw() {
  hg --verbose debugwireproto --peer raw http://$LOCALIP:$HGPORT/
}

cat > dummycommands.py << EOF
from mercurial import (
    wireprototypes,
    wireprotov1server,
)

@wireprotov1server.wireprotocommand(b'customreadonly', permission=b'pull')
def customreadonlyv1(repo, proto):
    return wireprototypes.bytesresponse(b'customreadonly bytes response')

@wireprotov1server.wireprotocommand(b'customreadwrite', permission=b'push')
def customreadwrite(repo, proto):
    return wireprototypes.bytesresponse(b'customreadwrite bytes response')

EOF

cat >> $HGRCPATH << EOF
[extensions]
drawdag = $TESTDIR/drawdag.py
EOF

enabledummycommands() {
  cat >> $HGRCPATH << EOF
[extensions]
dummycommands = $TESTTMP/dummycommands.py
EOF
}


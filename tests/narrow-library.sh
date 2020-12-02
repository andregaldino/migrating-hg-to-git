cat >> $HGRCPATH <<EOF
[extensions]
narrow=
[ui]
ssh=$PYTHON "$RUNTESTDIR/dummyssh"
[experimental]
changegroup3 = True
EOF

  abort: cannot specify both --user and --currentuser
  abort: cannot specify both --date and --currentdate
graft skips ancestors
  $ hg graft 21 3
  grafting 3:4c60f11aa304 "3"
  merging b and c to c
  $ hg ci -m 26
  $ hg backout 26
  changeset 27:e25e17192dc4 backs out changeset 26:44f862488a35
  $ hg graft 26
  skipping ancestor revision 26:44f862488a35
  $ hg graft 26 --force
  grafting 26:44f862488a35 "26"
  $ hg ci -m 29
  $ hg graft 26 --force --tool internal:fail
  grafting 26:44f862488a35 "26"
  grafting 26:44f862488a35 "26"
  $ hg up -qr 24
  $ hg graft -qr 25
  $ hg graft -f 25
  grafting 25:bd0c98709948 "26"
  note: graft of 25:bd0c98709948 created no changes to commit
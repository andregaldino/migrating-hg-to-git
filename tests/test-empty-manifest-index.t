Test null revisions (node 0000000000000000000000000000000000000000, aka rev -1)
in various circumstances.

Make an empty repo:

  $ hg init a
  $ cd a

  $ hg files -r 0000000000000000000000000000000000000000
  [1]
  $ hg files -r .
  [1]

Add an empty commit (this makes the changelog refer to a null manifest node):


  $ hg commit -m "init" --config ui.allowemptycommit=true

  $ hg files -r .
  [1]

Strip that empty commit (this makes the changelog file empty, as opposed to missing):

  $ hg --config 'extensions.strip=' strip . > /dev/null

  $ hg files -r .
  [1]

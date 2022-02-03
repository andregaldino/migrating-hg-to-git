===================================================================
Test merge behavior with narrow for item outside of the narrow spec
===================================================================

This test currently check for  simple "outside of narrow" merge case. I suspect
there might be more corner case that need testing, so extending this tests, or
replacing it by a more "generative" version, comparing behavior with and without narow.

This the feature is currently working with flat manifest only. This is the only
case tested. Consider using test-case if tree start supporting this case of
merge.

Create some initial setup

  $ . "$TESTDIR/narrow-library.sh"

  $ hg init server
  $ echo root > server/root
  $ mkdir server/inside
  $ mkdir server/outside
  $ echo babar > server/inside/inside-change
  $ echo pom > server/outside/outside-changing
  $ echo arthur > server/outside/outside-removed
  $ hg -R server add server/
  adding server/inside/inside-change
  adding server/outside/outside-changing
  adding server/outside/outside-removed
  adding server/root
  $ hg -R server commit -m root



  $ hg clone ssh://user@dummy/server client --narrow --include inside
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets a0c415d360e5
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

"trivial" change outside of narrow spec on the server

  $ echo zephir > server/outside/outside-added
  $ hg -R server add server/outside/outside-added
  $ echo flore > server/outside/outside-changing
  $ hg -R server remove server/outside/outside-removed
  $ hg -R server commit -m "outside change"

Merge them with some unrelated local change

  $ echo celeste > client/inside/inside-change
  $ hg -R client commit -m "inside change"
  $ hg -R client pull
  pulling from ssh://user@dummy/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files (+1 heads)
  new changesets f9ec5453023e
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg -R client merge
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg -R client ci -m 'merge changes'
  $ hg -R client push -r .
  pushing to ssh://user@dummy/server
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 2 changesets with 1 changes to 1 files

Checking result
---------------

general sentry of all output

  $ hg --repository server manifest --debug --rev 0
  360afd990eeff79e4a7f9f3ded5ecd7bc2fd3b59 644   inside/inside-change
  7db95ce5cd8e734ad12e3f5f37779a08070a1399 644   outside/outside-changing
  1591f6db41a30b68bd94ddccf4a4ce4f4fbe2a44 644   outside/outside-removed
  50ecbc31c0e82dd60c2747c434d1f11b85c0e178 644   root
  $ hg --repository server manifest --debug --rev 1
  360afd990eeff79e4a7f9f3ded5ecd7bc2fd3b59 644   inside/inside-change
  486c008d6dddcaeb5e5f99556a121800cdcfb149 644   outside/outside-added
  153d7af5e4f53f44475bc0ff2b806c86f019eda4 644   outside/outside-changing
  50ecbc31c0e82dd60c2747c434d1f11b85c0e178 644   root

  $ hg --repository server manifest --debug --rev 2
  1b3ab69c6c847abc8fd25537241fedcd4d188668 644   inside/inside-change
  7db95ce5cd8e734ad12e3f5f37779a08070a1399 644   outside/outside-changing
  1591f6db41a30b68bd94ddccf4a4ce4f4fbe2a44 644   outside/outside-removed
  50ecbc31c0e82dd60c2747c434d1f11b85c0e178 644   root
  $ hg --repository server manifest --debug --rev 3
  1b3ab69c6c847abc8fd25537241fedcd4d188668 644   inside/inside-change
  486c008d6dddcaeb5e5f99556a121800cdcfb149 644   outside/outside-added
  153d7af5e4f53f44475bc0ff2b806c86f019eda4 644   outside/outside-changing
  50ecbc31c0e82dd60c2747c434d1f11b85c0e178 644   root

The file changed outside should be changed by the merge

  $ hg --repository server manifest --debug --rev 'desc("inside change")' | grep outside-changing
  7db95ce5cd8e734ad12e3f5f37779a08070a1399 644   outside/outside-changing

  $ hg --repository server manifest --debug --rev 'desc("outside change")' | grep outside-changing
  153d7af5e4f53f44475bc0ff2b806c86f019eda4 644   outside/outside-changing
  $ hg --repository server manifest --debug --rev 'desc("merge")' | grep outside-changing
  153d7af5e4f53f44475bc0ff2b806c86f019eda4 644   outside/outside-changing

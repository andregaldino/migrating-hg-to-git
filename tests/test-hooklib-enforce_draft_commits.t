  $ cat <<EOF >> $HGRCPATH
  > [extensions]
  > hooklib =
  > 
  > [phases]
  > publish = False
  > EOF
  $ hg init a
  $ hg --cwd a debugbuilddag .
  $ hg --cwd a phase --public 0
  $ hg init b
  $ cat <<EOF >> b/.hg/hgrc
  > [hooks]
  > pretxnclose-phase.enforce_draft_commits = \
  >   python:hgext.hooklib.enforce_draft_commits.hook
  > EOF
  $ hg --cwd b pull ../a
  pulling from ../a
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  error: pretxnclose-phase.enforce_draft_commits hook failed: New changeset 1ea73414a91b in phase 'public' rejected
  transaction abort!
  rollback completed
  abort: New changeset 1ea73414a91b in phase 'public' rejected
  [255]
  $ hg --cwd a phase --force --draft 0
  $ hg --cwd b pull ../a
  pulling from ../a
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b (1 drafts)
  (run 'hg update' to get a working copy)
  $ hg --cwd a phase --public 0
  $ hg --cwd b pull ../a
  pulling from ../a
  searching for changes
  no changes found
  error: pretxnclose-phase.enforce_draft_commits hook failed: Phase change from 'draft' to 'public' for 1ea73414a91b rejected
  abort: Phase change from 'draft' to 'public' for 1ea73414a91b rejected
  [255]

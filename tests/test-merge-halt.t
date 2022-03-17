  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase=
  > [phases]
  > publish=False
  > [merge]
  > EOF

  $ hg init repo
  $ cd repo
  $ echo a > a
  $ echo b > b
  $ hg commit -qAm ab
  $ echo c >> a
  $ echo c >> b
  $ hg commit -qAm c
  $ hg up -q ".^"
  $ echo d >> a
  $ echo d >> b
  $ hg commit -qAm d

Testing on-failure=continue
  $ echo on-failure=continue >> $HGRCPATH
  $ hg rebase -s 1 -d 2 --tool false
  rebasing 1:1f28a51c3c9b "c"
  merging a
  merging a failed!
  merging b
  merging b failed!
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg resolve --list
  U a
  U b

  $ hg rebase --abort
  rebase aborted

Testing on-failure=halt
  $ echo on-failure=halt >> $HGRCPATH
  $ hg rebase -s 1 -d 2 --tool false
  rebasing 1:1f28a51c3c9b "c"
  merging a
  merging a failed!
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg resolve --list
  U a
  U b

  $ hg rebase --abort
  rebase aborted

Testing on-failure=prompt
  $ cat <<EOS >> $HGRCPATH
  > [merge]
  > on-failure=prompt
  > [ui]
  > interactive=1
  > EOS
  $ cat <<EOS | hg rebase -s 1 -d 2 --tool false
  > y
  > n
  > EOS
  rebasing 1:1f28a51c3c9b "c"
  merging a
  merging a failed!
  continue merge operation (yn)? y
  merging b
  merging b failed!
  continue merge operation (yn)? n
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg resolve --list
  U a
  U b

  $ hg rebase --abort
  rebase aborted

Check that successful tool with failed post-check halts the merge
  $ cat <<EOS >> $HGRCPATH
  > [merge-tools]
  > true.check=changed
  > EOS
  $ cat <<EOS | hg rebase -s 1 -d 2 --tool true
  > y
  > n
  > n
  > EOS
  rebasing 1:1f28a51c3c9b "c"
  merging a
   output file a appears unchanged
  was merge successful (yn)? y
  merging b
   output file b appears unchanged
  was merge successful (yn)? n
  merging b failed!
  continue merge operation (yn)? n
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg resolve --list
  R a
  U b

  $ hg rebase --abort
  rebase aborted

Check that conflicts with conflict check also halts the merge
  $ cat <<EOS >> $HGRCPATH
  > [merge-tools]
  > true.check=conflicts
  > true.premerge=keep
  > [merge]
  > on-failure=halt
  > EOS
  $ hg rebase -s 1 -d 2 --tool true
  rebasing 1:1f28a51c3c9b "c"
  merging a
  merging a failed!
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg resolve --list
  U a
  U b

  $ hg rebase --abort
  rebase aborted

Check that always-prompt also can halt the merge
  $ cat <<EOS | hg rebase -s 1 -d 2 --tool true --config merge-tools.true.check=prompt
  > y
  > n
  > EOS
  rebasing 1:1f28a51c3c9b "c"
  merging a
  was merge of 'a' successful (yn)? y
  merging b
  was merge of 'b' successful (yn)? n
  merging b failed!
  unresolved conflicts (see 'hg resolve', then 'hg rebase --continue')
  [240]

  $ hg resolve --list
  R a
  U b

  $ hg rebase --abort
  rebase aborted

Check that successful tool otherwise allows the merge to continue
  $ hg rebase -s 1 -d 2 --tool echo --keep --config merge-tools.echo.premerge=keep
  rebasing 1:1f28a51c3c9b "c"
  merging a
  $TESTTMP/repo/a *a~base* *a~other* (glob)
  merging b
  $TESTTMP/repo/b *b~base* *b~other* (glob)

Check that unshelve isn't broken by halting the merge
  $ cat <<EOS >> $HGRCPATH
  > [extensions]
  > shelve =
  > [merge-tools]
  > false.check=conflicts
  > false.premerge=false
  > EOS
  $ echo foo > shelve_file1
  $ echo foo > shelve_file2
  $ hg ci -qAm foo
  $ echo bar >> shelve_file1
  $ echo bar >> shelve_file2
  $ hg shelve --list
  $ hg shelve
  shelved as default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo baz >> shelve_file1
  $ echo baz >> shelve_file2
  $ hg ci -m baz
  $ hg unshelve --tool false --config merge-tools.false.premerge=keep
  unshelving change 'default'
  rebasing shelved changes
  merging shelve_file1
  merging shelve_file1 failed!
  unresolved conflicts (see 'hg resolve', then 'hg unshelve --continue')
  [240]
  $ hg status --config commands.status.verbose=True
  M shelve_file1
  M shelve_file2
  ? shelve_file1.orig
  # The repository is in an unfinished *unshelve* state.
  
  # Unresolved merge conflicts:
  # 
  #     shelve_file1
  #     shelve_file2
  # 
  # To mark files as resolved:  hg resolve --mark FILE
  
  # To continue:    hg unshelve --continue
  # To abort:       hg unshelve --abort
  
  $ hg resolve --tool false --all --re-merge
  merging shelve_file1
  merging shelve_file1 failed!
  merge halted after failed merge (see hg resolve)
  [240]
  $ hg shelve --list
  default         (*s ago) * changes to: foo (glob)
  $ hg unshelve --abort
  unshelve of 'default' aborted

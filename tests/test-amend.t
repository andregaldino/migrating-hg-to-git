#testcases obsstore-off obsstore-on

  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > amend=
  > debugdrawdag=$TESTDIR/drawdag.py
  > [diff]
  > git=1
  > EOF

#if obsstore-on
  $ cat << EOF >> $HGRCPATH
  > [experimental]
  > evolution.createmarkers=True
  > EOF
#endif

Basic amend

  $ hg init repo1
  $ cd repo1
  $ hg debugdrawdag <<'EOS'
  > B
  > |
  > A
  > EOS

  $ hg update B -q
  $ echo 2 >> B

  $ hg amend
  saved backup bundle to $TESTTMP/repo1/.hg/strip-backup/112478962961-7e959a55-amend.hg (obsstore-off !)
#if obsstore-off
  $ hg log -p -G --hidden -T '{rev} {node|short} {desc}\n'
  @  1 be169c7e8dbe B
  |  diff --git a/B b/B
  |  new file mode 100644
  |  --- /dev/null
  |  +++ b/B
  |  @@ -0,0 +1,1 @@
  |  +B2
  |
  o  0 426bada5c675 A
     diff --git a/A b/A
     new file mode 100644
     --- /dev/null
     +++ b/A
     @@ -0,0 +1,1 @@
     +A
     \ No newline at end of file
  
#else
  $ hg log -p -G --hidden -T '{rev} {node|short} {desc}\n'
  @  2 be169c7e8dbe B
  |  diff --git a/B b/B
  |  new file mode 100644
  |  --- /dev/null
  |  +++ b/B
  |  @@ -0,0 +1,1 @@
  |  +B2
  |
  | x  1 112478962961 B
  |/   diff --git a/B b/B
  |    new file mode 100644
  |    --- /dev/null
  |    +++ b/B
  |    @@ -0,0 +1,1 @@
  |    +B
  |    \ No newline at end of file
  |
  o  0 426bada5c675 A
     diff --git a/A b/A
     new file mode 100644
     --- /dev/null
     +++ b/A
     @@ -0,0 +1,1 @@
     +A
     \ No newline at end of file
  
#endif

Nothing changed

  $ hg amend
  nothing changed
  [1]

  $ hg amend -d "0 0"
  nothing changed
  [1]

  $ hg amend -d "Thu Jan 01 00:00:00 1970 UTC"
  nothing changed
  [1]

#if obsstore-on
  $ hg init repo-merge-state
  $ cd repo-merge-state
  $ echo a > f
  $ hg ci -Aqm a
  $ echo b > f
  $ hg ci -Aqm b
  $ echo c > f
  $ hg co -m '.^'
  merging f
  warning: conflicts while merging f! (edit, then use 'hg resolve --mark')
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges
  [1]
  $ echo d > f
  $ hg resolve -m f
  (no more unresolved files)
  $ hg ci --amend --config experimental.evolution.allowunstable=True
  1 new orphan changesets
  $ hg resolve -l
  $ cd ..
#endif

Matcher and metadata options

  $ echo 3 > C
  $ echo 4 > D
  $ hg add C D
  $ hg amend -m NEWMESSAGE -I C
  saved backup bundle to $TESTTMP/repo1/.hg/strip-backup/be169c7e8dbe-7684ddc5-amend.hg (obsstore-off !)
  $ hg log -r . -T '{node|short} {desc} {files}\n'
  c7ba14d9075b NEWMESSAGE B C
  $ echo 5 > E
  $ rm C
  $ hg amend -d '2000 1000' -u 'Foo <foo@example.com>' -A C D
  saved backup bundle to $TESTTMP/repo1/.hg/strip-backup/c7ba14d9075b-b3e76daa-amend.hg (obsstore-off !)
  $ hg log -r . -T '{node|short} {desc} {files} {author} {date}\n'
  14f6c4bcc865 NEWMESSAGE B D Foo <foo@example.com> 2000.01000

Amend with editor

  $ cat > $TESTTMP/prefix.sh <<'EOF'
  > printf 'EDITED: ' > $TESTTMP/msg
  > cat "$1" >> $TESTTMP/msg
  > mv $TESTTMP/msg "$1"
  > EOF
  $ chmod +x $TESTTMP/prefix.sh

  $ HGEDITOR="sh $TESTTMP/prefix.sh" hg amend --edit
  saved backup bundle to $TESTTMP/repo1/.hg/strip-backup/14f6c4bcc865-6591f15d-amend.hg (obsstore-off !)
  $ hg log -r . -T '{node|short} {desc}\n'
  298f085230c3 EDITED: NEWMESSAGE
  $ HGEDITOR="sh $TESTTMP/prefix.sh" hg amend -e -m MSG
  saved backup bundle to $TESTTMP/repo1/.hg/strip-backup/298f085230c3-d81a6ad3-amend.hg (obsstore-off !)
  $ hg log -r . -T '{node|short} {desc}\n'
  974f07f28537 EDITED: MSG

  $ echo FOO > $TESTTMP/msg
  $ hg amend -l $TESTTMP/msg -m BAR
  abort: cannot specify both --message and --logfile
  [10]
  $ hg amend -l $TESTTMP/msg
  saved backup bundle to $TESTTMP/repo1/.hg/strip-backup/974f07f28537-edb6470a-amend.hg (obsstore-off !)
  $ hg log -r . -T '{node|short} {desc}\n'
  507be9bdac71 FOO

Interactive mode

  $ touch F G
  $ hg add F G
  $ cat <<EOS | hg amend -i --config ui.interactive=1
  > y
  > n
  > EOS
  diff --git a/F b/F
  new file mode 100644
  examine changes to 'F'?
  (enter ? for help) [Ynesfdaq?] y
  
  diff --git a/G b/G
  new file mode 100644
  examine changes to 'G'?
  (enter ? for help) [Ynesfdaq?] n
  
  saved backup bundle to $TESTTMP/repo1/.hg/strip-backup/507be9bdac71-c8077452-amend.hg (obsstore-off !)
  $ hg log -r . -T '{files}\n'
  B D F

Amend in the middle of a stack

  $ hg init $TESTTMP/repo2
  $ cd $TESTTMP/repo2
  $ hg debugdrawdag <<'EOS'
  > C
  > |
  > B
  > |
  > A
  > EOS

  $ hg update -q B
  $ echo 2 >> B
  $ hg amend
  abort: cannot amend changeset, as that will orphan 1 descendants
  (see 'hg help evolution.instability')
  [10]

#if obsstore-on

With allowunstable, amend could work in the middle of a stack

  $ cat >> $HGRCPATH <<EOF
  > [experimental]
  > evolution.createmarkers=True
  > evolution.allowunstable=True
  > EOF

  $ hg amend
  1 new orphan changesets
  $ hg log -T '{rev} {node|short} {desc}\n' -G
  @  3 be169c7e8dbe B
  |
  | *  2 26805aba1e60 C
  | |
  | x  1 112478962961 B
  |/
  o  0 426bada5c675 A
  
Checking the note stored in the obsmarker

  $ echo foo > bar
  $ hg add bar
  $ hg amend --note 'yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy'
  abort: cannot store a note of more than 255 bytes
  [10]
  $ hg amend --note "adding bar"
  $ hg debugobsolete -r .
  112478962961147124edd43549aedd1a335e44bf be169c7e8dbe21cd10b3d79691cbe7f241e3c21c 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '8', 'operation': 'amend', 'user': 'test'}
  be169c7e8dbe21cd10b3d79691cbe7f241e3c21c 16084da537dd8f84cfdb3055c633772269d62e1b 0 (Thu Jan 01 00:00:00 1970 +0000) {'ef1': '8', 'note': 'adding bar', 'operation': 'amend', 'user': 'test'}

Cannot cause divergence by default

  $ hg co --hidden 1
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg amend -m divergent
  abort: cannot amend 112478962961, as that creates content-divergence with 16084da537dd
  (add --verbose for details or see 'hg help evolution.instability')
  [10]
  $ hg amend -m divergent --verbose
  abort: cannot amend 112478962961, as that creates content-divergence with 16084da537dd
      changeset 112478962961 already has a successor in changeset 16084da537dd
      rewriting changeset 112478962961 would create "content-divergence"
      set experimental.evolution.allowdivergence=True to skip this check
  (see 'hg help evolution.instability' for details on content-divergence)
  [10]
  $ hg amend -m divergent --config experimental.evolution.allowdivergence=true
  2 new content-divergent changesets

Amending pruned part of split commit does not cause divergence (issue6262)

  $ hg debugobsolete $(hg log  -T '{node}' -r .)
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg co '.^'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ node_B=$(hg log -T '{node}' -r 4)
  $ hg revert -r $node_B -a
  adding B
  adding bar
  $ hg ci -m B-split1
  created new head
  $ node_B_split1=$(hg log -T '{node}' -r .)
  $ hg co '.^'
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg revert -r 4 -a
  adding B
  adding bar
  $ hg ci -m B-split2
  created new head
  $ node_B_split2=$(hg log -T '{node}' -r .)
  $ hg debugobsolete $node_B $node_B_split1 $node_B_split2
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg debugobsolete $node_B_split2
  1 new obsolescence markers
  obsoleted 1 changesets
  $ hg co --hidden $node_B_split2
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg amend -m 'revived B-split2'
  abort: cannot amend 809fe227532f, as that creates content-divergence with c68306a86921, from 16084da537dd (known-bad-output !)
  (add --verbose for details or see 'hg help evolution.instability') (known-bad-output !)
  [10]

Hidden common predecessor of divergence does not cause crash

First create C1 as a pruned successor of C
  $ hg co C
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg amend -m C1
  $ hg tag --local C1
  $ hg debugobsolete $(hg log -T '{node}' -r C1)
  1 new obsolescence markers
  obsoleted 1 changesets
Now create C2 as other side of divergence (not actually divergent because C1 is
pruned)
  $ hg co C
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg amend -m C2
  1 new orphan changesets
Make the common predecessor (C) pruned
  $ hg tag --local --remove C
  $ hg co C1
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
Try to cause divergence
  $ hg amend -m C11
  abort: cannot amend 2758767f5d17, as that creates content-divergence with bfcb433a0dea, from 26805aba1e60
  (add --verbose for details or see 'hg help evolution.instability')
  [10]
#endif

Cannot amend public changeset

  $ hg phase -r A --public
  $ hg update -C -q A
  $ hg amend -m AMEND
  abort: cannot amend public changesets: 426bada5c675
  (see 'hg help phases' for details)
  [10]

Amend a merge changeset

  $ hg init $TESTTMP/repo3
  $ cd $TESTTMP/repo3
  $ hg debugdrawdag <<'EOS'
  >   C
  >  /|
  > A B
  > EOS
  $ hg update -q C
  $ hg amend -m FOO
  saved backup bundle to $TESTTMP/repo3/.hg/strip-backup/a35c07e8a2a4-15ff4612-amend.hg (obsstore-off !)
  $ rm .hg/localtags
  $ hg log -G -T '{desc}\n'
  @    FOO
  |\
  | o  B
  |
  o  A
  

More complete test for status changes (issue5732)
-------------------------------------------------

Generates history of files having 3 states, r0_r1_wc:

 r0: ground (content/missing)
 r1: old state to be amended (content/missing, where missing means removed)
 wc: changes to be included in r1 (content/missing-tracked/untracked)

  $ hg init $TESTTMP/wcstates
  $ cd $TESTTMP/wcstates

  $ "$PYTHON" $TESTDIR/generate-working-copy-states.py state 2 1
  $ hg addremove -q --similarity 0
  $ hg commit -m0

  $ "$PYTHON" $TESTDIR/generate-working-copy-states.py state 2 2
  $ hg addremove -q --similarity 0
  $ hg commit -m1

  $ "$PYTHON" $TESTDIR/generate-working-copy-states.py state 2 wc
  $ hg addremove -q --similarity 0
  $ hg forget *_*_*-untracked
  $ rm *_*_missing-*

amend r1 to include wc changes

  $ hg amend
  saved backup bundle to * (glob) (obsstore-off !)

clean/modified/removed/added states of the amended revision

  $ hg status --all --change . 'glob:content1_*_content1-tracked'
  C content1_content1_content1-tracked
  C content1_content2_content1-tracked
  C content1_missing_content1-tracked
  $ hg status --all --change . 'glob:content1_*_content[23]-tracked'
  M content1_content1_content3-tracked
  M content1_content2_content2-tracked
  M content1_content2_content3-tracked
  M content1_missing_content3-tracked
  $ hg status --all --change . 'glob:content1_*_missing-tracked'
  M content1_content2_missing-tracked
  R content1_missing_missing-tracked
  C content1_content1_missing-tracked
  $ hg status --all --change . 'glob:content1_*_*-untracked'
  R content1_content1_content1-untracked
  R content1_content1_content3-untracked
  R content1_content1_missing-untracked
  R content1_content2_content1-untracked
  R content1_content2_content2-untracked
  R content1_content2_content3-untracked
  R content1_content2_missing-untracked
  R content1_missing_content1-untracked
  R content1_missing_content3-untracked
  R content1_missing_missing-untracked
  $ hg status --all --change . 'glob:missing_content2_*'
  A missing_content2_content2-tracked
  A missing_content2_content3-tracked
  A missing_content2_missing-tracked
  $ hg status --all --change . 'glob:missing_missing_*'
  A missing_missing_content3-tracked

working directory should be all clean (with some missing/untracked files)

  $ hg status --all 'glob:*_content?-tracked'
  C content1_content1_content1-tracked
  C content1_content1_content3-tracked
  C content1_content2_content1-tracked
  C content1_content2_content2-tracked
  C content1_content2_content3-tracked
  C content1_missing_content1-tracked
  C content1_missing_content3-tracked
  C missing_content2_content2-tracked
  C missing_content2_content3-tracked
  C missing_missing_content3-tracked
  $ hg status --all 'glob:*_missing-tracked'
  ! content1_content1_missing-tracked
  ! content1_content2_missing-tracked
  ! content1_missing_missing-tracked
  ! missing_content2_missing-tracked
  ! missing_missing_missing-tracked
  $ hg status --all 'glob:*-untracked'
  ? content1_content1_content1-untracked
  ? content1_content1_content3-untracked
  ? content1_content2_content1-untracked
  ? content1_content2_content2-untracked
  ? content1_content2_content3-untracked
  ? content1_missing_content1-untracked
  ? content1_missing_content3-untracked
  ? missing_content2_content2-untracked
  ? missing_content2_content3-untracked
  ? missing_missing_content3-untracked

=================================
Test backup-bundle config option|
=================================
  $ hg init $TESTTMP/repo4
  $ cd $TESTTMP/repo4
  $ echo a>a
  $ hg ci -Aqma
  $ echo oops>b
  $ hg ci -Aqm "b"
  $ echo partiallyfixed > b

#if obsstore-off
  $ hg amend
  saved backup bundle to $TESTTMP/repo4/.hg/strip-backup/95e899acf2ce-f11cb050-amend.hg
When backup-bundle config option is set:
  $ cat << EOF >> $HGRCPATH
  > [rewrite]
  > backup-bundle = False
  > EOF
  $ echo fixed > b
  $ hg amend

#else
  $ hg amend
When backup-bundle config option is set:
  $ cat << EOF >> $HGRCPATH
  > [rewrite]
  > backup-bundle = False
  > EOF
  $ echo fixed > b
  $ hg amend

#endif
==========================================
Test update-timestamp config option|
==========================================

  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > amend=
  > mockmakedate = $TESTDIR/mockmakedate.py
  > EOF

  $ hg init $TESTTMP/repo5
  $ cd $TESTTMP/repo5
  $ cat <<'EOF' >> .hg/hgrc
  > [command-templates]
  > log = 'user:        {user}
  >        date:        {date|date}
  >        summary:     {desc|firstline}\n'
  > EOF

  $ echo a>a
  $ hg ci -Am 'commit 1'
  adding a

When updatetimestamp is False

  $ hg amend --date '1997-1-1 0:1'
  $ hg log --limit 1
  user:        test
  date:        Wed Jan 01 00:01:00 1997 +0000
  summary:     commit 1

 When update-timestamp is True and no other change than the date

  $ hg amend --config rewrite.update-timestamp=True
  nothing changed
  [1]
  $ hg log --limit 1
  user:        test
  date:        Wed Jan 01 00:01:00 1997 +0000
  summary:     commit 1

When update-timestamp is True and there is other change than the date
  $ hg amend --user foobar --config rewrite.update-timestamp=True
  $ hg log --limit 1
  user:        foobar
  date:        Thu Jan 01 00:00:02 1970 +0000
  summary:     commit 1

When date option is applicable and update-timestamp is True
  $ hg amend  --date '1998-1-1 0:1' --config rewrite.update-timestamp=True
  $ hg log --limit 1
  user:        foobar
  date:        Thu Jan 01 00:01:00 1998 +0000
  summary:     commit 1

Unlike rewrite.update-timestamp, -D/--currentdate always updates the timestamp

  $ hg amend -D
  $ hg log --limit 1
  user:        foobar
  date:        Thu Jan 01 00:00:04 1970 +0000
  summary:     commit 1

  $ hg amend -D --config rewrite.update-timestamp=True
  $ hg log --limit 1
  user:        foobar
  date:        Thu Jan 01 00:00:05 1970 +0000
  summary:     commit 1

rewrite.update-timestamp can be negated by --no-currentdate

  $ hg amend --config rewrite.update-timestamp=True --no-currentdate -u baz
  $ hg log --limit 1
  user:        baz
  date:        Thu Jan 01 00:00:05 1970 +0000
  summary:     commit 1

Bad combination of date options:

  $ hg amend -D --date '0 0'
  abort: cannot specify both --date and --currentdate
  [10]

Close branch

  $ hg amend --secret --close-branch
  $ hg log --limit 1 -T 'close={get(extras, "close")}\nphase={phase}\n'
  close=1
  phase=secret

  $ cd ..

Corner case of amend from issue6157:
- working copy parent has a change to file `a`
- working copy has the inverse change
- we amend the working copy parent for files other than `a`
hg used to include the changes to `a` anyway.

  $ hg init 6157; cd 6157
  $ echo a > a; echo b > b; hg commit -qAm_
  $ echo a2 > a; hg commit -qm_
  $ hg diff --stat -c .
   a |  2 +-
   1 files changed, 1 insertions(+), 1 deletions(-)
  $ echo a > a; echo b2 > b; hg amend -q b
  $ hg diff --stat -c .
   a |  2 +-
   b |  2 +-
   2 files changed, 2 insertions(+), 2 deletions(-)

Modifying a file while the editor is open can cause dirstate corruption
(issue6233)

  $ cd $TESTTMP
  $ hg init modify-during-amend; cd modify-during-amend
  $ echo r0 > foo; hg commit -qAm "r0"
  $ echo alpha > foo; hg commit -qm "alpha"
  $ echo beta >> foo
  $ cat > $TESTTMP/touchy_editor.sh <<EOF
  > sleep 1
  > echo delta >> "$TESTTMP/modify-during-amend/foo"
  > sleep 1
  > echo hi > "\$1"
  > sleep 1
  > EOF
  $ HGEDITOR="sh $TESTTMP/touchy_editor.sh" hg commit --amend
  $ if (hg diff -c . | grep 'delta' >/dev/null) || [ -n "$(hg status)" ]; then
  >   echo "OK."
  > else
  >   echo "Bug detected. 'delta' is not part of the commit OR the wdir"
  >   echo "Diff and status before rebuild:"
  >   hg diff
  >   hg status
  >   hg debugrebuilddirstate
  >   echo "Diff and status after rebuild:"
  >   hg diff
  >   hg status
  > fi
  OK.

Amending a commit that has copies but not specifying those copies shouldn't
cause them to be lost

  $ cd $TESTTMP
  $ hg init dont-lose-copies; cd dont-lose-copies
  $ echo r0 > r0; hg commit -qAm "r0"
  $ hg cp r0 r0_copied; hg commit -qm "copy r0"
  $ echo hi > new_file_amend_me
  $ hg status --change . --copies
  A r0_copied
    r0
  $ hg amend -qA new_file_amend_me
  $ hg status --change . --copies
  A new_file_amend_me
  A r0_copied
    r0

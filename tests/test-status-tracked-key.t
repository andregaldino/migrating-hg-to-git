===============================
Test the "tracked hint" feature
===============================

The tracked hint feature provide a file that get updated when the set of tracked
files get updated.

basic setup

  $ cat << EOF >> $HGRCPATH
  > [format]
  > use-dirstate-tracked-hint=yes
  > EOF

  $ hg init tracked-hint-test
  $ cd tracked-hint-test
  $ hg debugbuilddag '.+10' -n
  $ hg log -G -T '{rev} {desc} {files}\n'
  o  10 r10 nf10
  |
  o  9 r9 nf9
  |
  o  8 r8 nf8
  |
  o  7 r7 nf7
  |
  o  6 r6 nf6
  |
  o  5 r5 nf5
  |
  o  4 r4 nf4
  |
  o  3 r3 nf3
  |
  o  2 r2 nf2
  |
  o  1 r1 nf1
  |
  o  0 r0 nf0
  
  $ hg up tip
  11 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg files
  nf0
  nf1
  nf10
  nf2
  nf3
  nf4
  nf5
  nf6
  nf7
  nf8
  nf9

key-file exists
-----------

The tracked hint file should exist

  $ ls -1 .hg/dirstate*
  .hg/dirstate
  .hg/dirstate-tracked-hint

key-file stay the same if the tracked set is unchanged
------------------------------------------------------

(copy its content for later comparison)

  $ cp .hg/dirstate-tracked-hint ../key-bck
  $ echo foo >> nf0
  $ sleep 1
  $ hg status
  M nf0
  $ diff --brief .hg/dirstate-tracked-hint ../key-bck
  $ hg revert -C nf0
  $ sleep 1
  $ hg status
  $ diff --brief .hg/dirstate-tracked-hint ../key-bck

key-file change if the tracked set is changed manually
------------------------------------------------------

adding a file to tracking

  $ cp .hg/dirstate-tracked-hint ../key-bck
  $ echo x > x
  $ hg add x
  $ diff --brief .hg/dirstate-tracked-hint ../key-bck
  Files .hg/dirstate-tracked-hint and ../key-bck differ
  [1]

remove a file from tracking
(forget)

  $ cp .hg/dirstate-tracked-hint ../key-bck
  $ hg forget x
  $ diff --brief .hg/dirstate-tracked-hint ../key-bck
  Files .hg/dirstate-tracked-hint and ../key-bck differ
  [1]

(remove)

  $ cp .hg/dirstate-tracked-hint ../key-bck
  $ hg remove nf1
  $ diff --brief .hg/dirstate-tracked-hint ../key-bck
  Files .hg/dirstate-tracked-hint and ../key-bck differ
  [1]

key-file changes on revert (when applicable)
--------------------------------------------

  $ cp .hg/dirstate-tracked-hint ../key-bck
  $ hg status
  R nf1
  ? x
  $ hg revert --all
  undeleting nf1
  $ hg status
  ? x
  $ diff --brief .hg/dirstate-tracked-hint ../key-bck
  Files .hg/dirstate-tracked-hint and ../key-bck differ
  [1]


`hg update` does affect the key-file (when needed)
--------------------------------------------------

update changing the tracked set

(removing)

  $ cp .hg/dirstate-tracked-hint ../key-bck
  $ hg status --rev . --rev '.#generations[-1]'
  R nf10
  $ hg up '.#generations[-1]'
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ diff --brief .hg/dirstate-tracked-hint ../key-bck
  Files .hg/dirstate-tracked-hint and ../key-bck differ
  [1]

(adding)

  $ cp .hg/dirstate-tracked-hint ../key-bck
  $ hg status --rev . --rev '.#generations[1]'
  A nf10
  $ hg up '.#generations[1]'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ diff --brief .hg/dirstate-tracked-hint ../key-bck
  Files .hg/dirstate-tracked-hint and ../key-bck differ
  [1]

update not affecting the tracked set

  $ echo foo >> nf0
  $ hg commit -m foo

  $ cp .hg/dirstate-tracked-hint ../key-bck
  $ hg status --rev . --rev '.#generations[-1]'
  M nf0
  $ hg up '.#generations[-1]'
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ diff --brief .hg/dirstate-tracked-hint ../key-bck

Test upgrade and downgrade
==========================

  $ ls .hg/dirstate-tracked-hint
  .hg/dirstate-tracked-hint
  $ hg debugrequires | grep 'tracked'
  dirstate-tracked-key-v1

downgrade

  $ hg debugupgraderepo --config format.use-dirstate-tracked-hint=no --run --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: * (glob)
     removed: dirstate-tracked-key-v1
  
  no revlogs to process
  
  $ ls -1 .hg/dirstate-tracked-hint
  ls: *.hg/dirstate-tracked-hint*: $ENOENT$ (glob)
  [2]
  $ hg debugrequires | grep 'tracked'
  [1]

upgrade

  $ hg debugupgraderepo --config format.use-dirstate-tracked-hint=yes --run --quiet
  upgrade will perform the following actions:
  
  requirements
     preserved: * (glob)
     added: dirstate-tracked-key-v1
  
  no revlogs to process
  
  $ ls -1 .hg/dirstate-tracked-hint
  .hg/dirstate-tracked-hint
  $ hg debugrequires | grep 'tracked'
  dirstate-tracked-key-v1
  $ cd ..

Test automatic upgrade and downgrade
------------------------------------

create an initial repository

  $ hg init auto-upgrade \
  > --config format.use-dirstate-tracked-hint=no
  $ hg debugbuilddag -R auto-upgrade --new-file .+5
  $ hg -R auto-upgrade update
  6 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg debugformat -R auto-upgrade | grep tracked
  tracked-hint:        no

upgrade it to dirstate-tracked-hint automatically

  $ hg status -R auto-upgrade \
  > --config format.use-dirstate-tracked-hint.automatic-upgrade-of-mismatching-repositories=yes \
  > --config format.use-dirstate-tracked-hint=yes
  automatically upgrading repository to the `tracked-hint` feature
  (see `hg help config.format.use-dirstate-tracked-hint` for details)
  $ hg debugformat -R auto-upgrade | grep tracked
  tracked-hint:       yes

downgrade it from dirstate-tracked-hint automatically

  $ hg status -R auto-upgrade \
  > --config format.use-dirstate-tracked-hint.automatic-upgrade-of-mismatching-repositories=yes \
  > --config format.use-dirstate-tracked-hint=no
  automatically downgrading repository from the `tracked-hint` feature
  (see `hg help config.format.use-dirstate-tracked-hint` for details)
  $ hg debugformat -R auto-upgrade | grep tracked
  tracked-hint:        no

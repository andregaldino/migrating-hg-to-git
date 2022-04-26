Test support for partial-resolution tools

Create a tool that resolves conflicts after line 5 by simply dropping those
lines (even if there are no conflicts there)
  $ cat >> "$TESTTMP/head.sh" <<'EOF'
  > #!/bin/sh
  > for f in "$@"; do
  >   head -5 $f > tmp
  >   mv -f tmp $f
  > done
  > EOF
  $ chmod +x "$TESTTMP/head.sh"
...and another tool that keeps only the last 5 lines instead of the first 5.
  $ cat >> "$TESTTMP/tail.sh" <<'EOF'
  > #!/bin/sh
  > for f in "$@"; do
  >   tail -5 $f > tmp
  >   mv -f tmp $f
  > done
  > EOF
  $ chmod +x "$TESTTMP/tail.sh"

Set up both tools to run on all patterns (the default), and let the `tail` tool
run after the `head` tool, which means it will have no effect (we'll override it
to test order later)
  $ cat >> "$HGRCPATH" <<EOF
  > [partial-merge-tools]
  > head.executable=$TESTTMP/head.sh
  > tail.executable=$TESTTMP/tail.sh
  > tail.order=1
  > EOF

  $ make_commit() {
  >   echo "$@" | xargs -n1 > file
  >   hg add file 2> /dev/null
  >   hg ci -m "$*"
  > }


Let a partial-resolution tool resolve some conflicts and leave other conflicts
for the regular merge tool (:merge3 here)

  $ hg init repo
  $ cd repo
  $ make_commit a b c d e f
  $ make_commit a b2 c d e f2
  $ hg up 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ make_commit a b3 c d e f3
  created new head
  $ hg merge 1 -t :merge3
  merging file
  warning: conflicts while merging file! (edit, then use 'hg resolve --mark')
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ cat file
  a
  <<<<<<< working copy:    e11a49d4b620 - test: a b3 c d e f3
  b3
  ||||||| common ancestor: 8ae8bb9cc43a - test: a b c d e f
  b
  =======
  b2
  >>>>>>> merge rev:       fbc096a40cc5 - test: a b2 c d e f2
  c
  d
  e


With premerge=keep, the partial-resolution tools runs before and doesn't see
the conflict markers

  $ hg up -C 2
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cat >> .hg/hgrc <<EOF
  > [merge-tools]
  > my-local.executable = cat
  > my-local.args = $local
  > my-local.premerge = keep-merge3
  > EOF
  $ hg merge 1 -t my-local
  merging file
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ cat file
  a
  <<<<<<< working copy:    e11a49d4b620 - test: a b3 c d e f3
  b3
  ||||||| common ancestor: 8ae8bb9cc43a - test: a b c d e f
  b
  =======
  b2
  >>>>>>> merge rev:       fbc096a40cc5 - test: a b2 c d e f2
  c
  d
  e


When a partial-resolution tool resolves all conflicts, the resolution should
be recorded and the regular merge tool should not be invoked for the file.

  $ hg up -C 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ make_commit a b c d e f2
  created new head
  $ hg up 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ make_commit a b c d e f3
  created new head
  $ hg merge 3 -t false
  merging file
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ cat file
  a
  b
  c
  d
  e


Can disable all partial merge tools (the `head` tool would have resolved this
conflict it had been enabled)

  $ hg up -C 4
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 3 -t :merge3 --config merge.disable-partial-tools=yes
  merging file
  warning: conflicts while merging file! (edit, then use 'hg resolve --mark')
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ cat file
  a
  b
  c
  d
  e
  <<<<<<< working copy:    d57edaa6e21a - test: a b c d e f3
  f3
  ||||||| common ancestor: 8ae8bb9cc43a - test: a b c d e f
  f
  =======
  f2
  >>>>>>> merge rev:       8c217da987be - test: a b c d e f2


Can disable one partial merge tool (the `head` tool would have resolved this
conflict it had been enabled)

  $ hg up -C 4
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 3 -t :merge3 --config partial-merge-tools.head.disable=yes
  merging file
  warning: conflicts while merging file! (edit, then use 'hg resolve --mark')
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ cat file
  b
  c
  d
  e
  <<<<<<< working copy:    d57edaa6e21a - test: a b c d e f3
  f3
  ||||||| common ancestor: 8ae8bb9cc43a - test: a b c d e f
  f
  =======
  f2
  >>>>>>> merge rev:       8c217da987be - test: a b c d e f2


Only tools whose patterns match are run. We make `head` not match here, so
only `tail` should run

  $ hg up -C 4
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 3 -t :merge3 --config partial-merge-tools.head.patterns=other
  merging file
  warning: conflicts while merging file! (edit, then use 'hg resolve --mark')
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ cat file
  b
  c
  d
  e
  <<<<<<< working copy:    d57edaa6e21a - test: a b c d e f3
  f3
  ||||||| common ancestor: 8ae8bb9cc43a - test: a b c d e f
  f
  =======
  f2
  >>>>>>> merge rev:       8c217da987be - test: a b c d e f2


If there are several matching tools, they are run in requested order. We move
`head` after `tail` in order here so it has no effect (the conflict in "f" thus
remains).

  $ hg up -C 4
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 3 -t :merge3 --config partial-merge-tools.head.order=2
  merging file
  warning: conflicts while merging file! (edit, then use 'hg resolve --mark')
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ cat file
  b
  c
  d
  e
  <<<<<<< working copy:    d57edaa6e21a - test: a b c d e f3
  f3
  ||||||| common ancestor: 8ae8bb9cc43a - test: a b c d e f
  f
  =======
  f2
  >>>>>>> merge rev:       8c217da987be - test: a b c d e f2


When using "nomerge" tools (e.g. `:other`), the partial-resolution tools
should not be run.

  $ hg up -C 4
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 3 -t :other
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ cat file
  a
  b
  c
  d
  e
  f2


If a partial-resolution tool resolved some conflict and simplemerge can
merge the rest, then the regular merge tool should not be used. Here we merge
"a b c d e3 f3" with "a b2 c d e f2". The `head` tool resolves the conflict in
"f" and the internal simplemerge merges the remaining changes in "b" and "e".

  $ hg up -C 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ make_commit a b c d e3 f3
  created new head
  $ hg merge 1 -t false
  merging file
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ cat file
  a
  b2
  c
  d
  e3

Test that arguments get passed as expected.

  $ cat >> "$TESTTMP/log-args.sh" <<'EOF'
  > #!/bin/sh
  > echo "$@" > args.log
  > EOF
  $ chmod +x "$TESTTMP/log-args.sh"
  $ cat >> "$HGRCPATH" <<EOF
  > [partial-merge-tools]
  > log-args.executable=$TESTTMP/log-args.sh
  > EOF
  $ hg up -C 2
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 1
  merging file
  warning: conflicts while merging file! (edit, then use 'hg resolve --mark')
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ cat args.log
  */hgmerge-*/file~local */hgmerge-*/file~base */hgmerge-*/file~other (glob)
  $ hg up -C 2
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge 1 --config partial-merge-tools.log-args.args='--other $other $base --foo --local $local --also-other $other'
  merging file
  warning: conflicts while merging file! (edit, then use 'hg resolve --mark')
  0 files updated, 0 files merged, 0 files removed, 1 files unresolved
  use 'hg resolve' to retry unresolved file merges or 'hg merge --abort' to abandon
  [1]
  $ cat args.log
  --other */hgmerge-*/file~other */hgmerge-*/file~base --foo --local */hgmerge-*/file~local --also-other */hgmerge-*/file~other (glob)

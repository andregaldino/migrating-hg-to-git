Define helpers.

  $ hg_log () { hg log -G -T "{rev}:{node|short}"; }
  $ commit () { echo "foo - ${2:-$1}" > $1; hg commit -Aqm "Edited $1"; }
  $ strip() { hg --config extensions.strip= strip -q -r "$1" ; }

Setup hg repo.

  $ hg init repo
  $ cd repo
  $ touch x; hg add x; hg commit -m "initial"
  $ hg clone -q . ../clone
  $ commit a

  $ cd ../clone

  $ commit b

  $ hg pull -q ../repo

  $ cat .hg/cache/branch2-visible
  222ae9789a75703f9836e44de7db179cbfd420ee 2
  a3498d6e39376d2456425dd8c692367bdbf00fa2 o default
  222ae9789a75703f9836e44de7db179cbfd420ee o default

  $ hg_log
  o  2:222ae9789a75
  |
  | @  1:a3498d6e3937
  |/
  o  0:7ab0a3bd758a
  

  $ strip '1:'

The branchmap cache is not adjusted on strip.
Now mentions a changelog entry that has been stripped.

  $ cat .hg/cache/branch2-visible
  222ae9789a75703f9836e44de7db179cbfd420ee 2
  a3498d6e39376d2456425dd8c692367bdbf00fa2 o default
  222ae9789a75703f9836e44de7db179cbfd420ee o default

  $ commit c

Not adjusted on commit, either.

  $ cat .hg/cache/branch2-visible
  222ae9789a75703f9836e44de7db179cbfd420ee 2
  a3498d6e39376d2456425dd8c692367bdbf00fa2 o default
  222ae9789a75703f9836e44de7db179cbfd420ee o default

On pull we end up with the same tip, and so wrongly reuse the invalid cache and crash.

  $ hg pull ../repo 2>&1 | grep 'ValueError:'
  ValueError: node a3498d6e39376d2456425dd8c692367bdbf00fa2 does not exist (known-bad-output !)

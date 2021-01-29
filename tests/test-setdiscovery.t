
Function to test discovery between two repos in both directions, using both the local shortcut
(which is currently not activated by default) and the full remotable protocol:

  $ testdesc() { # revs_a, revs_b, dagdesc
  >     if [ -d foo ]; then rm -rf foo; fi
  >     hg init foo
  >     cd foo
  >     hg debugbuilddag "$3"
  >     hg clone . a $1 --quiet
  >     hg clone . b $2 --quiet
  >     echo
  >     echo "% -- a -> b tree"
  >     hg -R a debugdiscovery b --verbose --old
  >     echo
  >     echo "% -- a -> b set"
  >     hg -R a debugdiscovery b --verbose --debug --config progress.debug=true
  >     echo
  >     echo "% -- a -> b set (tip only)"
  >     hg -R a debugdiscovery b --verbose --debug --config progress.debug=true --rev tip
  >     echo
  >     echo "% -- b -> a tree"
  >     hg -R b debugdiscovery a --verbose --old
  >     echo
  >     echo "% -- b -> a set"
  >     hg -R b debugdiscovery a --verbose --debug --config progress.debug=true
  >     echo
  >     echo "% -- b -> a set (tip only)"
  >     hg -R b debugdiscovery a --verbose --debug --config progress.debug=true --rev tip
  >     cd ..
  > }


Small superset:

  $ testdesc '-ra1 -ra2' '-rb1 -rb2 -rb3' '
  > +2:f +1:a1:b1
  > <f +4 :a2
  > +5 :b2
  > <f +3 :b3'
  
  % -- a -> b tree
  comparing with b
  searching for changes
  unpruned common: 01241442b3c2 66f7d451a68b b5714e113bc0
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          2
      also local heads:          2
      also remote heads:         1
      both:                      1
    local heads:                 2
      common:                    2
      missing:                   0
    remote heads:                3
      common:                    1
      unknown:                   2
  local changesets:              7
    common:                      7
      heads:                     2
      roots:                     1
    missing:                     0
      heads:                     0
      roots:                     0
    first undecided set:         3
      heads:                     1
      roots:                     1
      common:                    3
      missing:                   0
  common heads: 01241442b3c2 b5714e113bc0
  
  % -- a -> b set
  comparing with b
  query 1; heads
  searching for changes
  all local changesets known remotely
  elapsed time:  * seconds (glob)
  round-trips:                   1
  heads summary:
    total common heads:          2
      also local heads:          2
      also remote heads:         1
      both:                      1
    local heads:                 2
      common:                    2
      missing:                   0
    remote heads:                3
      common:                    1
      unknown:                   2
  local changesets:              7
    common:                      7
      heads:                     2
      roots:                     1
    missing:                     0
      heads:                     0
      roots:                     0
    first undecided set:         3
      heads:                     1
      roots:                     1
      common:                    3
      missing:                   0
  common heads: 01241442b3c2 b5714e113bc0
  
  % -- a -> b set (tip only)
  comparing with b
  query 1; heads
  searching for changes
  all local changesets known remotely
  elapsed time:  * seconds (glob)
  round-trips:                   1
  heads summary:
    total common heads:          1
      also local heads:          1
      also remote heads:         0
      both:                      0
    local heads:                 2
      common:                    1
      missing:                   1
    remote heads:                3
      common:                    0
      unknown:                   3
  local changesets:              7
    common:                      6
      heads:                     1
      roots:                     1
    missing:                     1
      heads:                     1
      roots:                     1
    first undecided set:         6
      heads:                     2
      roots:                     1
      common:                    5
      missing:                   1
  common heads: b5714e113bc0
  
  % -- b -> a tree
  comparing with a
  searching for changes
  unpruned common: 01241442b3c2 b5714e113bc0
  elapsed time:  * seconds (glob)
  round-trips:                   1
  heads summary:
    total common heads:          2
      also local heads:          1
      also remote heads:         2
      both:                      1
    local heads:                 3
      common:                    1
      missing:                   2
    remote heads:                2
      common:                    2
      unknown:                   0
  local changesets:             15
    common:                      7
      heads:                     2
      roots:                     1
    missing:                     8
      heads:                     2
      roots:                     2
    first undecided set:         8
      heads:                     2
      roots:                     2
      common:                    0
      missing:                   8
  common heads: 01241442b3c2 b5714e113bc0
  
  % -- b -> a set
  comparing with a
  query 1; heads
  searching for changes
  all remote heads known locally
  elapsed time:  * seconds (glob)
  round-trips:                   1
  heads summary:
    total common heads:          2
      also local heads:          1
      also remote heads:         2
      both:                      1
    local heads:                 3
      common:                    1
      missing:                   2
    remote heads:                2
      common:                    2
      unknown:                   0
  local changesets:             15
    common:                      7
      heads:                     2
      roots:                     1
    missing:                     8
      heads:                     2
      roots:                     2
    first undecided set:         8
      heads:                     2
      roots:                     2
      common:                    0
      missing:                   8
  common heads: 01241442b3c2 b5714e113bc0
  
  % -- b -> a set (tip only)
  comparing with a
  query 1; heads
  searching for changes
  all remote heads known locally
  elapsed time:  * seconds (glob)
  round-trips:                   1
  heads summary:
    total common heads:          2
      also local heads:          1
      also remote heads:         2
      both:                      1
    local heads:                 3
      common:                    1
      missing:                   2
    remote heads:                2
      common:                    2
      unknown:                   0
  local changesets:             15
    common:                      7
      heads:                     2
      roots:                     1
    missing:                     8
      heads:                     2
      roots:                     2
    first undecided set:         8
      heads:                     2
      roots:                     2
      common:                    0
      missing:                   8
  common heads: 01241442b3c2 b5714e113bc0


Many new:

  $ testdesc '-ra1 -ra2' '-rb' '
  > +2:f +3:a1 +3:b
  > <f +30 :a2'
  
  % -- a -> b tree
  comparing with b
  searching for changes
  unpruned common: bebd167eb94d
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          1
      also remote heads:         0
      both:                      0
    local heads:                 2
      common:                    1
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             35
    common:                      5
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        34
      heads:                     2
      roots:                     1
      common:                    4
      missing:                  30
  common heads: bebd167eb94d
  
  % -- a -> b set
  comparing with b
  query 1; heads
  searching for changes
  taking initial sample
  searching: 2 queries
  query 2; still undecided: 29, sample size is: 29
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          1
      also remote heads:         0
      both:                      0
    local heads:                 2
      common:                    1
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             35
    common:                      5
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        34
      heads:                     2
      roots:                     1
      common:                    4
      missing:                  30
  common heads: bebd167eb94d
  
  % -- a -> b set (tip only)
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 31, sample size is: 31
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 2
      common:                    0
      missing:                   2
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             35
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    33
      heads:                     2
      roots:                     2
    first undecided set:        35
      heads:                     2
      roots:                     1
      common:                    2
      missing:                  33
  common heads: 66f7d451a68b
  
  % -- b -> a tree
  comparing with a
  searching for changes
  unpruned common: 66f7d451a68b bebd167eb94d
  elapsed time:  * seconds (glob)
  round-trips:                   4
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         1
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                2
      common:                    1
      unknown:                   1
  local changesets:              8
    common:                      5
      heads:                     1
      roots:                     1
    missing:                     3
      heads:                     1
      roots:                     1
    first undecided set:         3
      heads:                     1
      roots:                     1
      common:                    0
      missing:                   3
  common heads: bebd167eb94d
  
  % -- b -> a set
  comparing with a
  query 1; heads
  searching for changes
  taking initial sample
  searching: 2 queries
  query 2; still undecided: 2, sample size is: 2
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         1
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                2
      common:                    1
      unknown:                   1
  local changesets:              8
    common:                      5
      heads:                     1
      roots:                     1
    missing:                     3
      heads:                     1
      roots:                     1
    first undecided set:         3
      heads:                     1
      roots:                     1
      common:                    0
      missing:                   3
  common heads: bebd167eb94d
  
  % -- b -> a set (tip only)
  comparing with a
  query 1; heads
  searching for changes
  taking initial sample
  searching: 2 queries
  query 2; still undecided: 2, sample size is: 2
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         1
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                2
      common:                    1
      unknown:                   1
  local changesets:              8
    common:                      5
      heads:                     1
      roots:                     1
    missing:                     3
      heads:                     1
      roots:                     1
    first undecided set:         3
      heads:                     1
      roots:                     1
      common:                    0
      missing:                   3
  common heads: bebd167eb94d

Both sides many new with stub:

  $ testdesc '-ra1 -ra2' '-rb' '
  > +2:f +2:a1 +30 :b
  > <f +30 :a2'
  
  % -- a -> b tree
  comparing with b
  searching for changes
  unpruned common: 2dc09a01254d
  elapsed time:  * seconds (glob)
  round-trips:                   4
  heads summary:
    total common heads:          1
      also local heads:          1
      also remote heads:         0
      both:                      0
    local heads:                 2
      common:                    1
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             34
    common:                      4
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        33
      heads:                     2
      roots:                     1
      common:                    3
      missing:                  30
  common heads: 2dc09a01254d
  
  % -- a -> b set
  comparing with b
  query 1; heads
  searching for changes
  taking initial sample
  searching: 2 queries
  query 2; still undecided: 29, sample size is: 29
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          1
      also remote heads:         0
      both:                      0
    local heads:                 2
      common:                    1
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             34
    common:                      4
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        33
      heads:                     2
      roots:                     1
      common:                    3
      missing:                  30
  common heads: 2dc09a01254d
  
  % -- a -> b set (tip only)
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 31, sample size is: 31
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 2
      common:                    0
      missing:                   2
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             34
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    32
      heads:                     2
      roots:                     2
    first undecided set:        34
      heads:                     2
      roots:                     1
      common:                    2
      missing:                  32
  common heads: 66f7d451a68b
  
  % -- b -> a tree
  comparing with a
  searching for changes
  unpruned common: 2dc09a01254d 66f7d451a68b
  elapsed time:  * seconds (glob)
  round-trips:                   4
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         1
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                2
      common:                    1
      unknown:                   1
  local changesets:             34
    common:                      4
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        30
      heads:                     1
      roots:                     1
      common:                    0
      missing:                  30
  common heads: 2dc09a01254d
  
  % -- b -> a set
  comparing with a
  query 1; heads
  searching for changes
  taking initial sample
  searching: 2 queries
  query 2; still undecided: 29, sample size is: 29
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         1
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                2
      common:                    1
      unknown:                   1
  local changesets:             34
    common:                      4
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        30
      heads:                     1
      roots:                     1
      common:                    0
      missing:                  30
  common heads: 2dc09a01254d
  
  % -- b -> a set (tip only)
  comparing with a
  query 1; heads
  searching for changes
  taking initial sample
  searching: 2 queries
  query 2; still undecided: 29, sample size is: 29
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         1
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                2
      common:                    1
      unknown:                   1
  local changesets:             34
    common:                      4
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        30
      heads:                     1
      roots:                     1
      common:                    0
      missing:                  30
  common heads: 2dc09a01254d


Both many new:

  $ testdesc '-ra' '-rb' '
  > +2:f +30 :b
  > <f +30 :a'
  
  % -- a -> b tree
  comparing with b
  searching for changes
  unpruned common: 66f7d451a68b
  elapsed time:  * seconds (glob)
  round-trips:                   4
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             32
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        32
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  30
  common heads: 66f7d451a68b
  
  % -- a -> b set
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 31, sample size is: 31
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             32
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        32
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  30
  common heads: 66f7d451a68b
  
  % -- a -> b set (tip only)
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 31, sample size is: 31
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             32
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        32
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  30
  common heads: 66f7d451a68b
  
  % -- b -> a tree
  comparing with a
  searching for changes
  unpruned common: 66f7d451a68b
  elapsed time:  * seconds (glob)
  round-trips:                   4
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             32
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        32
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  30
  common heads: 66f7d451a68b
  
  % -- b -> a set
  comparing with a
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 31, sample size is: 31
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             32
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        32
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  30
  common heads: 66f7d451a68b
  
  % -- b -> a set (tip only)
  comparing with a
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 31, sample size is: 31
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             32
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        32
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  30
  common heads: 66f7d451a68b


Both many new skewed:

  $ testdesc '-ra' '-rb' '
  > +2:f +30 :b
  > <f +50 :a'
  
  % -- a -> b tree
  comparing with b
  searching for changes
  unpruned common: 66f7d451a68b
  elapsed time:  * seconds (glob)
  round-trips:                   4
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             52
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    50
      heads:                     1
      roots:                     1
    first undecided set:        52
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  50
  common heads: 66f7d451a68b
  
  % -- a -> b set
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 51, sample size is: 51
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             52
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    50
      heads:                     1
      roots:                     1
    first undecided set:        52
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  50
  common heads: 66f7d451a68b
  
  % -- a -> b set (tip only)
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 51, sample size is: 51
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             52
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    50
      heads:                     1
      roots:                     1
    first undecided set:        52
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  50
  common heads: 66f7d451a68b
  
  % -- b -> a tree
  comparing with a
  searching for changes
  unpruned common: 66f7d451a68b
  elapsed time:  * seconds (glob)
  round-trips:                   3
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             32
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        32
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  30
  common heads: 66f7d451a68b
  
  % -- b -> a set
  comparing with a
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 31, sample size is: 31
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             32
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        32
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  30
  common heads: 66f7d451a68b
  
  % -- b -> a set (tip only)
  comparing with a
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 31, sample size is: 31
  2 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   2
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:             32
    common:                      2
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:        32
      heads:                     1
      roots:                     1
      common:                    2
      missing:                  30
  common heads: 66f7d451a68b


Both many new on top of long history:

  $ testdesc '-ra' '-rb' '
  > +1000:f +30 :b
  > <f +50 :a'
  
  % -- a -> b tree
  comparing with b
  searching for changes
  unpruned common: 7ead0cba2838
  elapsed time:  * seconds (glob)
  round-trips:                   4
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:           1050
    common:                   1000
      heads:                     1
      roots:                     1
    missing:                    50
      heads:                     1
      roots:                     1
    first undecided set:      1050
      heads:                     1
      roots:                     1
      common:                 1000
      missing:                  50
  common heads: 7ead0cba2838
  
  % -- a -> b set
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 1049, sample size is: 11
  sampling from both directions
  searching: 3 queries
  query 3; still undecided: 31, sample size is: 31
  3 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   3
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:           1050
    common:                   1000
      heads:                     1
      roots:                     1
    missing:                    50
      heads:                     1
      roots:                     1
    first undecided set:      1050
      heads:                     1
      roots:                     1
      common:                 1000
      missing:                  50
  common heads: 7ead0cba2838
  
  % -- a -> b set (tip only)
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 1049, sample size is: 11
  sampling from both directions
  searching: 3 queries
  query 3; still undecided: 31, sample size is: 31
  3 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   3
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:           1050
    common:                   1000
      heads:                     1
      roots:                     1
    missing:                    50
      heads:                     1
      roots:                     1
    first undecided set:      1050
      heads:                     1
      roots:                     1
      common:                 1000
      missing:                  50
  common heads: 7ead0cba2838
  
  % -- b -> a tree
  comparing with a
  searching for changes
  unpruned common: 7ead0cba2838
  elapsed time:  * seconds (glob)
  round-trips:                   3
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:           1030
    common:                   1000
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:      1030
      heads:                     1
      roots:                     1
      common:                 1000
      missing:                  30
  common heads: 7ead0cba2838
  
  % -- b -> a set
  comparing with a
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 1029, sample size is: 11
  sampling from both directions
  searching: 3 queries
  query 3; still undecided: 15, sample size is: 15
  3 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   3
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:           1030
    common:                   1000
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:      1030
      heads:                     1
      roots:                     1
      common:                 1000
      missing:                  30
  common heads: 7ead0cba2838
  
  % -- b -> a set (tip only)
  comparing with a
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 1029, sample size is: 11
  sampling from both directions
  searching: 3 queries
  query 3; still undecided: 15, sample size is: 15
  3 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   3
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                 1
      common:                    0
      missing:                   1
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:           1030
    common:                   1000
      heads:                     1
      roots:                     1
    missing:                    30
      heads:                     1
      roots:                     1
    first undecided set:      1030
      heads:                     1
      roots:                     1
      common:                 1000
      missing:                  30
  common heads: 7ead0cba2838


One with >200 heads. We now switch to send them all in the initial roundtrip, but still do sampling for the later request.

  $ hg init manyheads
  $ cd manyheads
  $ echo "+300:r @a" >dagdesc
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3 *r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3*r+3" >>dagdesc # 20 heads
  $ echo "@b *r+3" >>dagdesc # one more head
  $ hg debugbuilddag <dagdesc
  reading DAG from stdin

  $ hg heads -t --template . | wc -c
  \s*261 (re)

  $ hg clone -b a . a
  adding changesets
  adding manifests
  adding file changes
  added 1340 changesets with 0 changes to 0 files (+259 heads)
  new changesets 1ea73414a91b:1c51e2c80832
  updating to branch a
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg clone -b b . b
  adding changesets
  adding manifests
  adding file changes
  added 304 changesets with 0 changes to 0 files
  new changesets 1ea73414a91b:513314ca8b3a
  updating to branch b
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ hg -R a debugdiscovery b --debug --verbose --config progress.debug=true --config devel.discovery.randomize=false  --config devel.discovery.sample-size.initial=50
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 1080, sample size is: 50
  sampling from both directions
  searching: 3 queries
  query 3; still undecided: 1030, sample size is: 200
  sampling from both directions
  searching: 4 queries
  query 4; still undecided: 547, sample size is: 210
  sampling from both directions
  searching: 5 queries
  query 5; still undecided: 336, sample size is: 220
  sampling from both directions
  searching: 6 queries
  query 6; still undecided: 114, sample size is: 114
  6 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   6
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:               260
      common:                    0
      missing:                 260
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:           1340
    common:                    300
      heads:                     1
      roots:                     1
    missing:                  1040
      heads:                   260
      roots:                   260
    first undecided set:      1340
      heads:                   260
      roots:                     1
      common:                  300
      missing:                1040
  common heads: 3ee37d65064a
  $ hg -R a debugdiscovery b --debug --verbose --config progress.debug=true --rev tip
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  searching: 2 queries
  query 2; still undecided: 303, sample size is: 9
  sampling from both directions
  searching: 3 queries
  query 3; still undecided: 3, sample size is: 3
  3 total queries in *.????s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   3
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:               260
      common:                    0
      missing:                 260
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:           1340
    common:                    300
      heads:                     1
      roots:                     1
    missing:                  1040
      heads:                   260
      roots:                   260
    first undecided set:      1340
      heads:                   260
      roots:                     1
      common:                  300
      missing:                1040
  common heads: 3ee37d65064a

  $ hg -R a debugdiscovery b --debug --config devel.discovery.exchange-heads=false --config devel.discovery.randomize=false --config devel.discovery.grow-sample.rate=1.20 --config devel.discovery.sample-size=50
  comparing with b
  searching for changes
  sampling from both directions
  query 1; still undecided: 1340, sample size is: 50
  sampling from both directions
  query 2; still undecided: 995, sample size is: 60
  sampling from both directions
  query 3; still undecided: 913, sample size is: 72
  sampling from both directions
  query 4; still undecided: 816, sample size is: 204
  sampling from both directions
  query 5; still undecided: 612, sample size is: 153
  sampling from both directions
  query 6; still undecided: 456, sample size is: 123
  sampling from both directions
  query 7; still undecided: 332, sample size is: 147
  sampling from both directions
  query 8; still undecided: 184, sample size is: 176
  sampling from both directions
  query 9; still undecided: 8, sample size is: 8
  9 total queries in *s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   9
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:               260
      common:                    0
      missing:                 260
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:           1340
    common:                    300
      heads:                     1
      roots:                     1
    missing:                  1040
      heads:                   260
      roots:                   260
    first undecided set:      1340
      heads:                   260
      roots:                     1
      common:                  300
      missing:                1040
  common heads: 3ee37d65064a

Test actual protocol when pulling one new head in addition to common heads

  $ hg clone -U b c
  $ hg -R c id -ir tip
  513314ca8b3a
  $ hg -R c up -qr default
  $ touch c/f
  $ hg -R c ci -Aqm "extra head"
  $ hg -R c id -i
  e64a39e7da8b

  $ hg serve -R c -p $HGPORT -d --pid-file=hg.pid -A access.log -E errors.log
  $ cat hg.pid >> $DAEMON_PIDS

  $ hg -R b incoming http://localhost:$HGPORT/ -T '{node|short}\n'
  comparing with http://localhost:$HGPORT/
  searching for changes
  e64a39e7da8b

  $ killdaemons.py
  $ cut -d' ' -f6- access.log | grep -v cmd=known # cmd=known uses random sampling
  "GET /?cmd=capabilities HTTP/1.1" 200 -
  "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=heads+%3Bknown+nodes%3D513314ca8b3ae4dac8eec56966265b00fcf866db x-hgproto-1:0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull
  "GET /?cmd=getbundle HTTP/1.1" 200 - x-hgarg-1:$USUAL_BUNDLE_CAPS$&cg=1&common=513314ca8b3ae4dac8eec56966265b00fcf866db&heads=e64a39e7da8b0d54bc63e81169aff001c13b3477 x-hgproto-1:0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull
  "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases x-hgproto-1:0.1 0.2 comp=$USUAL_COMPRESSIONS$ partial-pull
  $ cat errors.log

  $ cd ..


Issue 4438 - test coverage for 3ef893520a85 issues.

  $ mkdir issue4438
  $ cd issue4438
#if false
generate new bundles:
  $ hg init r1
  $ for i in `"$PYTHON" $TESTDIR/seq.py 101`; do hg -R r1 up -qr null && hg -R r1 branch -q b$i && hg -R r1 ci -qmb$i; done
  $ hg clone -q r1 r2
  $ for i in `"$PYTHON" $TESTDIR/seq.py 10`; do hg -R r1 up -qr null && hg -R r1 branch -q c$i && hg -R r1 ci -qmc$i; done
  $ hg -R r2 branch -q r2change && hg -R r2 ci -qmr2change
  $ hg -R r1 bundle -qa $TESTDIR/bundles/issue4438-r1.hg
  $ hg -R r2 bundle -qa $TESTDIR/bundles/issue4438-r2.hg
#else
use existing bundles:
  $ hg init r1
  $ hg -R r1 -q unbundle $TESTDIR/bundles/issue4438-r1.hg
  $ hg -R r1 -q up
  $ hg init r2
  $ hg -R r2 -q unbundle $TESTDIR/bundles/issue4438-r2.hg
  $ hg -R r2 -q up
#endif

Set iteration order could cause wrong and unstable results - fixed in 73cfaa348650:

  $ hg -R r1 outgoing r2 -T'{rev} '
  comparing with r2
  searching for changes
  101 102 103 104 105 106 107 108 109 110  (no-eol)

The case where all the 'initialsamplesize' samples already were common would
give 'all remote heads known locally' without checking the remaining heads -
fixed in 86c35b7ae300:

  $ cat >> r1/.hg/hgrc << EOF
  > [devel]
  > discovery.randomize = False
  > EOF

  $ hg -R r1 outgoing r2 -T'{rev} ' --config extensions.blackbox= \
  > --config blackbox.track='command commandfinish discovery'
  comparing with r2
  searching for changes
  101 102 103 104 105 106 107 108 109 110  (no-eol)
  $ hg -R r1 --config extensions.blackbox= blackbox --config blackbox.track=
  * @5d0b986a083e0d91f116de4691e2aaa54d5bbec0 (*)> serve --cmdserver chgunix * (glob) (chg !)
  * @5d0b986a083e0d91f116de4691e2aaa54d5bbec0 (*)> -R r1 outgoing r2 *-T{rev} * --config *extensions.blackbox=* (glob)
  * @5d0b986a083e0d91f116de4691e2aaa54d5bbec0 (*)> found 101 common and 1 unknown server heads, 1 roundtrips in *.????s (glob)
  * @5d0b986a083e0d91f116de4691e2aaa54d5bbec0 (*)> -R r1 outgoing r2 *-T{rev} * --config *extensions.blackbox=* exited 0 after *.?? seconds (glob)
  $ cd ..

Even if the set of revs to discover is restricted, unrelated revs may be
returned as common heads.

  $ mkdir ancestorsof
  $ cd ancestorsof
  $ hg init a
  $ hg clone a b -q
  $ cd b
  $ hg debugbuilddag '.:root *root *root'
  $ hg log -G -T '{node|short}'
  o  fa942426a6fd
  |
  | o  66f7d451a68b
  |/
  o  1ea73414a91b
  
  $ hg push -r 66f7d451a68b -q
  $ hg debugdiscovery --verbose --rev fa942426a6fd
  comparing with $TESTTMP/ancestorsof/a
  searching for changes
  elapsed time:  * seconds (glob)
  round-trips:                   1
  heads summary:
    total common heads:          1
      also local heads:          1
      also remote heads:         1
      both:                      1
    local heads:                 2
      common:                    1
      missing:                   1
    remote heads:                1
      common:                    1
      unknown:                   0
  local changesets:              3
    common:                      2
      heads:                     1
      roots:                     1
    missing:                     1
      heads:                     1
      roots:                     1
    first undecided set:         1
      heads:                     1
      roots:                     1
      common:                    0
      missing:                   1
  common heads: 66f7d451a68b

  $ cd ..


Test debuging discovery using different subset of the same repository
=====================================================================

remote is a local subset
------------------------

remote will be last 25 heads of the local graph

  $ cd $TESTTMP/manyheads
  $ hg -R a debugdiscovery \
  > --debug \
  > --remote-as-revs 'last(heads(all()), 25)' \
  > --config devel.discovery.randomize=false
  query 1; heads
  searching for changes
  all remote heads known locally
  elapsed time:  * seconds (glob)
  round-trips:                   1
  heads summary:
    total common heads:         25
      also local heads:         25
      also remote heads:        25
      both:                     25
    local heads:               260
      common:                   25
      missing:                 235
    remote heads:               25
      common:                   25
      unknown:                   0
  local changesets:           1340
    common:                    400
      heads:                    25
      roots:                     1
    missing:                   940
      heads:                   235
      roots:                   235
    first undecided set:       940
      heads:                   235
      roots:                   235
      common:                    0
      missing:                 940
  common heads: 0dfd965d91c6 0fe09b60448d 14a17233ce9d 175c0a3072cf 1c51e2c80832 1e51600e0698 24eb5f9bdbab 25ce09526613 36bd00abde57 426989fdefa0 596d87362679 5dd1039ea5c0 5ef24f022278 5f230dc19419 80b39998accb 88f40688ffb5 9e37ddf8c632 abf4d55b075e b2ce801fddfe b368b6ac3ce3 c959bf2e869c c9fba6ba4e2e d783207cf649 d9a51e256f21 e3717a4e3753

local is a local subset
------------------------

remote will be last 25 heads of the local graph

  $ cd $TESTTMP/manyheads
  $ hg -R a debugdiscovery b \
  > --debug \
  > --local-as-revs 'first(heads(all()), 25)' \
  > --config devel.discovery.randomize=false
  comparing with b
  query 1; heads
  searching for changes
  taking quick initial sample
  query 2; still undecided: 375, sample size is: 81
  sampling from both directions
  query 3; still undecided: 3, sample size is: 3
  3 total queries *s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   3
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                25
      common:                    0
      missing:                  25
    remote heads:                1
      common:                    0
      unknown:                   1
  local changesets:            400
    common:                    300
      heads:                     1
      roots:                     1
    missing:                   100
      heads:                    25
      roots:                    25
    first undecided set:       400
      heads:                    25
      roots:                     1
      common:                  300
      missing:                 100
  common heads: 3ee37d65064a

both local and remove are subset
------------------------

remote will be last 25 heads of the local graph

  $ cd $TESTTMP/manyheads
  $ hg -R a debugdiscovery \
  > --debug \
  > --local-as-revs 'first(heads(all()), 25)' \
  > --remote-as-revs 'last(heads(all()), 25)' \
  > --config devel.discovery.randomize=false
  query 1; heads
  searching for changes
  taking quick initial sample
  query 2; still undecided: 375, sample size is: 81
  sampling from both directions
  query 3; still undecided: 3, sample size is: 3
  3 total queries in *s (glob)
  elapsed time:  * seconds (glob)
  round-trips:                   3
  heads summary:
    total common heads:          1
      also local heads:          0
      also remote heads:         0
      both:                      0
    local heads:                25
      common:                    0
      missing:                  25
    remote heads:               25
      common:                    0
      unknown:                  25
  local changesets:            400
    common:                    300
      heads:                     1
      roots:                     1
    missing:                   100
      heads:                    25
      roots:                    25
    first undecided set:       400
      heads:                    25
      roots:                     1
      common:                  300
      missing:                 100
  common heads: 3ee37d65064a

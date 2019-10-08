#require test-repo

Set vars:

  $ . "$TESTDIR/helpers-testrepo.sh"
  $ CONTRIBDIR="$TESTDIR/../contrib"

Prepare repo:

  $ hg init

  $ echo this is file a > a
  $ hg add a
  $ hg commit -m first

  $ echo adding to file a >> a
  $ hg commit -m second

  $ echo adding more to file a >> a
  $ hg commit -m third

  $ hg up -r 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo merge-this >> a
  $ hg commit -m merge-able
  created new head

  $ hg up -r 2
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

perfstatus

  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > perf=$CONTRIBDIR/perf.py
  > [perf]
  > presleep=0
  > stub=on
  > parentscount=1
  > EOF
  $ hg help -e perf
  perf extension - helper extension to measure performance
  
  Configurations
  ==============
  
  "perf"
  ------
  
  "all-timing"
      When set, additional statistics will be reported for each benchmark: best,
      worst, median average. If not set only the best timing is reported
      (default: off).
  
  "presleep"
    number of second to wait before any group of runs (default: 1)
  
  "pre-run"
    number of run to perform before starting measurement.
  
  "profile-benchmark"
    Enable profiling for the benchmarked section. (The first iteration is
    benchmarked)
  
  "run-limits"
    Control the number of runs each benchmark will perform. The option value
    should be a list of '<time>-<numberofrun>' pairs. After each run the
    conditions are considered in order with the following logic:
  
        If benchmark has been running for <time> seconds, and we have performed
        <numberofrun> iterations, stop the benchmark,
  
    The default value is: '3.0-100, 10.0-3'
  
  "stub"
      When set, benchmarks will only be run once, useful for testing (default:
      off)
  
  list of commands:
  
   perfaddremove
                 (no help text available)
   perfancestors
                 (no help text available)
   perfancestorset
                 (no help text available)
   perfannotate  (no help text available)
   perfbdiff     benchmark a bdiff between revisions
   perfbookmarks
                 benchmark parsing bookmarks from disk to memory
   perfbranchmap
                 benchmark the update of a branchmap
   perfbranchmapload
                 benchmark reading the branchmap
   perfbranchmapupdate
                 benchmark branchmap update from for <base> revs to <target>
                 revs
   perfbundleread
                 Benchmark reading of bundle files.
   perfcca       (no help text available)
   perfchangegroupchangelog
                 Benchmark producing a changelog group for a changegroup.
   perfchangeset
                 (no help text available)
   perfctxfiles  (no help text available)
   perfdiffwd    Profile diff of working directory changes
   perfdirfoldmap
                 benchmap a 'dirstate._map.dirfoldmap.get()' request
   perfdirs      (no help text available)
   perfdirstate  benchmap the time necessary to load a dirstate from scratch
   perfdirstatedirs
                 benchmap a 'dirstate.hasdir' call from an empty 'dirs' cache
   perfdirstatefoldmap
                 benchmap a 'dirstate._map.filefoldmap.get()' request
   perfdirstatewrite
                 (no help text available)
   perfdiscovery
                 benchmark discovery between local repo and the peer at given
                 path
   perffncacheencode
                 (no help text available)
   perffncacheload
                 (no help text available)
   perffncachewrite
                 (no help text available)
   perfheads     benchmark the computation of a changelog heads
   perfhelper-mergecopies
                 find statistics about potential parameters for
                 'perfmergecopies'
   perfhelper-pathcopies
                 find statistic about potential parameters for the
                 'perftracecopies'
   perfignore    benchmark operation related to computing ignore
   perfindex     benchmark index creation time followed by a lookup
   perflinelogedits
                 (no help text available)
   perfloadmarkers
                 benchmark the time to parse the on-disk markers for a repo
   perflog       (no help text available)
   perflookup    (no help text available)
   perflrucachedict
                 (no help text available)
   perfmanifest  benchmark the time to read a manifest from disk and return a
                 usable
   perfmergecalculate
                 (no help text available)
   perfmergecopies
                 measure runtime of 'copies.mergecopies'
   perfmoonwalk  benchmark walking the changelog backwards
   perfnodelookup
                 (no help text available)
   perfnodemap   benchmark the time necessary to look up revision from a cold
                 nodemap
   perfparents   benchmark the time necessary to fetch one changeset's parents.
   perfpathcopies
                 benchmark the copy tracing logic
   perfphases    benchmark phasesets computation
   perfphasesremote
                 benchmark time needed to analyse phases of the remote server
   perfprogress  printing of progress bars
   perfrawfiles  (no help text available)
   perfrevlogchunks
                 Benchmark operations on revlog chunks.
   perfrevlogindex
                 Benchmark operations against a revlog index.
   perfrevlogrevision
                 Benchmark obtaining a revlog revision.
   perfrevlogrevisions
                 Benchmark reading a series of revisions from a revlog.
   perfrevlogwrite
                 Benchmark writing a series of revisions to a revlog.
   perfrevrange  (no help text available)
   perfrevset    benchmark the execution time of a revset
   perfstartup   (no help text available)
   perfstatus    benchmark the performance of a single status call
   perftags      (no help text available)
   perftemplating
                 test the rendering time of a given template
   perfunidiff   benchmark a unified diff between revisions
   perfvolatilesets
                 benchmark the computation of various volatile set
   perfwalk      (no help text available)
   perfwrite     microbenchmark ui.write
  
  (use 'hg help -v perf' to show built-in aliases and global options)
  $ hg perfaddremove
  $ hg perfancestors
  $ hg perfancestorset 2
  $ hg perfannotate a
  $ hg perfbdiff -c 1
  $ hg perfbdiff --alldata 1
  $ hg perfunidiff -c 1
  $ hg perfunidiff --alldata 1
  $ hg perfbookmarks
  $ hg perfbranchmap
  $ hg perfbranchmapload
  $ hg perfbranchmapupdate --base "not tip" --target "tip"
  benchmark of branchmap with 3 revisions with 1 new ones
  $ hg perfcca
  $ hg perfchangegroupchangelog
  $ hg perfchangegroupchangelog --cgversion 01
  $ hg perfchangeset 2
  $ hg perfctxfiles 2
  $ hg perfdiffwd
  $ hg perfdirfoldmap
  $ hg perfdirs
  $ hg perfdirstate
  $ hg perfdirstatedirs
  $ hg perfdirstatefoldmap
  $ hg perfdirstatewrite
#if repofncache
  $ hg perffncacheencode
  $ hg perffncacheload
  $ hg debugrebuildfncache
  fncache already up to date
  $ hg perffncachewrite
  $ hg debugrebuildfncache
  fncache already up to date
#endif
  $ hg perfheads
  $ hg perfignore
  $ hg perfindex
  $ hg perflinelogedits -n 1
  $ hg perfloadmarkers
  $ hg perflog
  $ hg perflookup 2
  $ hg perflrucache
  $ hg perfmanifest 2
  $ hg perfmanifest -m 44fe2c8352bb3a478ffd7d8350bbc721920134d1
  $ hg perfmanifest -m 44fe2c8352bb
  abort: manifest revision must be integer or full node
  [255]
  $ hg perfmergecalculate -r 3
  $ hg perfmoonwalk
  $ hg perfnodelookup 2
  $ hg perfpathcopies 1 2
  $ hg perfprogress --total 1000
  $ hg perfrawfiles 2
  $ hg perfrevlogindex -c
#if reporevlogstore
  $ hg perfrevlogrevisions .hg/store/data/a.i
#endif
  $ hg perfrevlogrevision -m 0
  $ hg perfrevlogchunks -c
  $ hg perfrevrange
  $ hg perfrevset 'all()'
  $ hg perfstartup
  $ hg perfstatus
  $ hg perftags
  $ hg perftemplating
  $ hg perfvolatilesets
  $ hg perfwalk
  $ hg perfparents
  $ hg perfdiscovery -q .

Test run control
----------------

Simple single entry

  $ hg perfparents --config perf.stub=no --config perf.run-limits='0.000000001-15'
  ! wall * comb * user * sys * (best of 15) (glob)

Multiple entries

  $ hg perfparents --config perf.stub=no --config perf.run-limits='500000-1, 0.000000001-5'
  ! wall * comb * user * sys * (best of 5) (glob)

error case are ignored

  $ hg perfparents --config perf.stub=no --config perf.run-limits='500, 0.000000001-5'
  malformatted run limit entry, missing "-": 500
  ! wall * comb * user * sys * (best of 5) (glob)
  $ hg perfparents --config perf.stub=no --config perf.run-limits='aaa-12, 0.000000001-5'
  malformatted run limit entry, could not convert string to float: aaa: aaa-12 (no-py3 !)
  malformatted run limit entry, could not convert string to float: 'aaa': aaa-12 (py3 !)
  ! wall * comb * user * sys * (best of 5) (glob)
  $ hg perfparents --config perf.stub=no --config perf.run-limits='12-aaaaaa, 0.000000001-5'
  malformatted run limit entry, invalid literal for int() with base 10: 'aaaaaa': 12-aaaaaa
  ! wall * comb * user * sys * (best of 5) (glob)

test actual output
------------------

normal output:

  $ hg perfheads --config perf.stub=no
  ! wall * comb * user * sys * (best of *) (glob)

detailed output:

  $ hg perfheads --config perf.all-timing=yes --config perf.stub=no
  ! wall * comb * user * sys * (best of *) (glob)
  ! wall * comb * user * sys * (max of *) (glob)
  ! wall * comb * user * sys * (avg of *) (glob)
  ! wall * comb * user * sys * (median of *) (glob)

test json output
----------------

normal output:

  $ hg perfheads --template json --config perf.stub=no
  [
   {
    "comb": *, (glob)
    "count": *, (glob)
    "sys": *, (glob)
    "user": *, (glob)
    "wall": * (glob)
   }
  ]

detailed output:

  $ hg perfheads --template json --config perf.all-timing=yes --config perf.stub=no
  [
   {
    "avg.comb": *, (glob)
    "avg.count": *, (glob)
    "avg.sys": *, (glob)
    "avg.user": *, (glob)
    "avg.wall": *, (glob)
    "comb": *, (glob)
    "count": *, (glob)
    "max.comb": *, (glob)
    "max.count": *, (glob)
    "max.sys": *, (glob)
    "max.user": *, (glob)
    "max.wall": *, (glob)
    "median.comb": *, (glob)
    "median.count": *, (glob)
    "median.sys": *, (glob)
    "median.user": *, (glob)
    "median.wall": *, (glob)
    "sys": *, (glob)
    "user": *, (glob)
    "wall": * (glob)
   }
  ]

Test pre-run feature
--------------------

(perf discovery has some spurious output)

  $ hg perfdiscovery . --config perf.stub=no --config perf.run-limits='0.000000001-1' --config perf.pre-run=0
  ! wall * comb * user * sys * (best of 1) (glob)
  searching for changes
  $ hg perfdiscovery . --config perf.stub=no --config perf.run-limits='0.000000001-1' --config perf.pre-run=1
  ! wall * comb * user * sys * (best of 1) (glob)
  searching for changes
  searching for changes
  $ hg perfdiscovery . --config perf.stub=no --config perf.run-limits='0.000000001-1' --config perf.pre-run=3
  ! wall * comb * user * sys * (best of 1) (glob)
  searching for changes
  searching for changes
  searching for changes
  searching for changes

test  profile-benchmark option
------------------------------

Function to check that statprof ran
  $ statprofran () {
  >   egrep 'Sample count:|No samples recorded' > /dev/null
  > }
  $ hg perfdiscovery . --config perf.stub=no --config perf.run-limits='0.000000001-1' --config perf.profile-benchmark=yes 2>&1 | statprofran

Check perf.py for historical portability
----------------------------------------

  $ cd "$TESTDIR/.."

  $ (testrepohg files -r 1.2 glob:mercurial/*.c glob:mercurial/*.py;
  >  testrepohg files -r tip glob:mercurial/*.c glob:mercurial/*.py) |
  > "$TESTDIR"/check-perf-code.py contrib/perf.py
  contrib/perf.py:\d+: (re)
   >     from mercurial import (
   import newer module separately in try clause for early Mercurial
  contrib/perf.py:\d+: (re)
   >     from mercurial import (
   import newer module separately in try clause for early Mercurial
  contrib/perf.py:\d+: (re)
   >     origindexpath = orig.opener.join(orig.indexfile)
   use getvfs()/getsvfs() for early Mercurial
  contrib/perf.py:\d+: (re)
   >     origdatapath = orig.opener.join(orig.datafile)
   use getvfs()/getsvfs() for early Mercurial
  contrib/perf.py:\d+: (re)
   >         vfs = vfsmod.vfs(tmpdir)
   use getvfs()/getsvfs() for early Mercurial
  contrib/perf.py:\d+: (re)
   >         vfs.options = getattr(orig.opener, 'options', None)
   use getvfs()/getsvfs() for early Mercurial
  [1]

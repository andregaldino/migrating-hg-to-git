Test graph-related template functions
=====================================

  $ cat <<'EOF' >> $HGRCPATH
  > [extensions]
  > drawdag = $RUNTESTDIR/drawdag.py
  > EOF

  $ hg init a
  $ cd a

  $ hg debugdrawdag <<'EOF'
  >   l
  >  / \
  > |   k
  > |   |\
  > |   | j
  > |   | |
  > i   | |
  > |\  | |
  > h | | |
  > | | | |
  > | g | |
  > | | | |
  > f | | |
  > | |/ /
  > | e |
  > | |/
  > | d
  > |/|
  > c |
  > | |
  > b |
  >   |
  >   a
  > EOF

  $ hg log -Gq -T'{rev} {tags}\n'
  o    11 l tip
  |\
  | o    10 i
  | |\
  o \ \    9 k
  |\ \ \
  +-----o  8 g
  | | |
  | o |  7 j
  | | |
  | | o  6 h
  | | |
  o | |  5 e
  |/ /
  | o  4 f
  | |
  o |  3 d
  |\|
  | o  2 c
  | |
  | o  1 b
  |
  o  0 a
  

  $ cd ..

subsetparents
-------------

  $ cd a

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("c+i"))}\n' -r 'c+i'
  o  10 i: 2
  :
  o  2 c:
  |
  ~

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("c+h+i"))}\n' -r 'c+h+i'
  o    10 i: 6
  |\
  o :  6 h: 2
  :/
  o  2 c:
  |
  ~

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("c+h+l"))}\n' -r 'c+h+l'
  o    11 l tip: 6
  :\
  : o  6 h: 2
  :/
  o  2 c:
  |
  ~

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("c+f+l"))}\n' -r 'c+f+l'
  o    11 l tip: 4
  :\
  : o  4 f: 2
  :/
  o  2 c:
  |
  ~

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("c+h+i+k"))}\n' -r 'c+h+i+k'
  o    10 i: 6
  |\
  | : o  9 k: 2
  | :/
  o :  6 h: 2
  :/
  o  2 c:
  |
  ~

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("c+d+h+i+k"))}\n' -r 'c+d+h+i+k'
  o    10 i: 6 3
  |\
  | : o  9 k: 3
  | :/
  o :  6 h: 2
  : :
  : o  3 d: 2
  :/|
  : ~
  o  2 c:
  |
  ~

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("c+j+k+i"))}\n' -r 'c+j+k+i'
  o  10 i: 2
  :
  : o  9 k: 7
  :/|
  : o  7 j: 2
  :/
  o  2 c:
  |
  ~

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("c+e+f+j"))}\n' -r 'c+e+f+j'
  o  7 j: 2
  :
  : o  5 e: 2
  :/
  : o  4 f: 2
  :/
  o  2 c:
  |
  ~

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("b+e+f+j"))}\n' -r 'b+e+f+j'
  o  7 j: 1
  :
  : o  5 e: 1
  :/
  : o  4 f: 1
  :/
  o  1 b:
  

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("a+c+f+g+j+l"))}\n' -r 'a+c+f+g+j+l'
  o    11 l tip: 4 8 7
  :\
  : \
  : :\
  : : \
  : : :\
  : : : \
  : : : :\
  : o---+ :  8 g: 0 2
  : :/ / /
  : +---o  7 j: 0 2
  : : :/
  o---+  4 f: 2
   / /
  : o  2 c:
  : |
  : ~
  o  0 a:
  

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("b+i+l"))}\n' -r 'b+i+l'
  o    11 l tip: 10
  |\
  o :  10 i: 1
  :/
  o  1 b:
  

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("b+i+j+l"))}\n' -r 'b+i+j+l'
  o    11 l tip: 10 7
  |\
  | \
  | :\
  o : :  10 i: 1
  :/ /
  : o  7 j: 1
  :/
  o  1 b:
  

null in subset:

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("null+a+c+f"))}\n' -r 'null+a+c+f'
  o  4 f: 2
  |
  o  2 c: -1
  :
  : o  0 a: -1
  :/
  @  -1 : -1
  

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("null+a+b+c+f"))}\n' -r 'null+a+b+c+f'
  o  4 f: 2
  |
  o  2 c: 1
  |
  o  1 b: -1
  |
  | o  0 a: -1
  |/
  @  -1 : -1
  

wdir in subset:

  $ hg update -qC i

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("f+k+wdir()"))}\n' -r 'f+k+wdir()'
  o  2147483647 : 4
  :
  : o    9 k:
  : |\
  : ~ ~
  o  4 f:
  |
  ~

  $ hg update -qC null

Revisions not in subset:

  $ hg log -T '{rev} {tags}: {subsetparents(rev, revset("a+c+f+g+j+l"))}\n'
  11 l tip: 4 8 7
  10 i: 
  9 k: 
  8 g: 0 2
  7 j: 0 2
  6 h: 
  5 e: 
  4 f: 2
  3 d: 
  2 c: 
  1 b: 
  0 a: 

  $ hg log -T '{rev} {tags}: {subsetparents(rev, revset("b+c"))}\n'
  11 l tip: 
  10 i: 
  9 k: 
  8 g: 
  7 j: 
  6 h: 
  5 e: 
  4 f: 
  3 d: 
  2 c: 1
  1 b: 
  0 a: 

  $ hg log -T '{rev} {tags}: {subsetparents(rev, revset("b+c"))}\n' -r'reverse(null:2)'
  2 c: 1
  1 b: 
  0 a: 
  -1 : 

Nothing excluded:

  $ hg log -T '{rev} {tags}: {subsetparents(rev, revset("null:wdir()"))}\n' -r'reverse(null:wdir())'
  2147483647 : -1
  11 l tip: 10 9
  10 i: 6 8
  9 k: 5 7
  8 g: 5
  7 j: 3
  6 h: 4
  5 e: 3
  4 f: 2
  3 d: 0 2
  2 c: 1
  1 b: -1
  0 a: -1
  -1 : -1

Uncachable query:

  $ hg log -Gq -T '{rev} {tags}: {subsetparents(rev, revset("%d:%d", rev, rev - 1))}\n'
  o    11 l tip: 10
  |\
  | o    10 i:
  | |\
  o \ \    9 k:
  |\ \ \
  +-----o  8 g:
  | | |
  | o |  7 j:
  | | |
  | | o  6 h:
  | | |
  o | |  5 e:
  |/ /
  | o  4 f:
  | |
  o |  3 d: 2
  |\|
  | o  2 c: 1
  | |
  | o  1 b:
  |
  o  0 a: -1
  

Invalid arguments:

  $ hg log -T '{subsetparents()}\n'
  hg: parse error: subsetparents expects two arguments
  [255]
  $ hg log -T '{subsetparents("a")}\n'
  hg: parse error: subsetparents expects two arguments
  [255]
  $ hg log -T '{subsetparents(rev, extras)}\n'
  hg: parse error: subsetparents expects a queried revset
  [255]

  $ cd ..

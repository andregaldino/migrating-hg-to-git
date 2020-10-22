Test extension of unfinished states support.
  $ mkdir chainify
  $ cd chainify
  $ cat >> chainify.py <<EOF
  > from mercurial import cmdutil, error, extensions, exthelper, node, scmutil, state
  > from hgext import rebase
  > 
  > eh = exthelper.exthelper()
  > 
  > extsetup = eh.finalextsetup
  > cmdtable = eh.cmdtable
  > 
  > # Rebase calls addunfinished in uisetup, so we have to call it in extsetup.
  > # Ideally there'd by an 'extensions.afteruisetup()' just like
  > # 'extensions.afterloaded()' to allow nesting multiple commands.
  > @eh.extsetup
  > def _extsetup(ui):
  >     state.addunfinished(
  >         b'chainify',
  >         b'chainify.state',
  >         continueflag=True,
  >         childopnames=[b'rebase'])
  > 
  > def _node(repo, arg):
  >     return node.hex(scmutil.revsingle(repo, arg).node())
  > 
  > @eh.command(
  >     b'chainify',
  >     [(b'r', b'revs', [], b'revs to chain', b'REV'),
  >      (b'', b'continue', False, b'continue op')],
  >     b'chainify [-r REV] +',
  >     inferrepo=True)
  > def chainify(ui, repo, **opts):
  >     """Rebases r1, r2, r3, etc. into a chain."""
  >     with repo.wlock(), repo.lock():
  >         cmdstate = state.cmdstate(repo, b'chainify.state')
  >         if opts['continue']:
  >             if not cmdstate.exists():
  >                 raise error.Abort(b'no chainify in progress')
  >         else:
  >             cmdutil.checkunfinished(repo)
  >             data = {
  >                 b'tip': _node(repo, opts['revs'][0]),
  >                 b'revs': b','.join(_node(repo, r) for r in opts['revs'][1:]),
  >             }
  >             cmdstate.save(1, data)
  > 
  >         data = cmdstate.read()
  >         while data[b'revs']:
  >             tip = data[b'tip']
  >             revs = data[b'revs'].split(b',')
  >             with state.delegating(repo, b'chainify', b'rebase'):
  >                 ui.status(b'rebasing %s onto %s\n' % (revs[0][:12], tip[:12]))
  >                 if state.ischildunfinished(repo, b'chainify', b'rebase'):
  >                     rc = state.continuechild(ui, repo, b'chainify', b'rebase')
  >                 else:
  >                     rc = rebase.rebase(ui, repo, rev=[revs[0]], dest=tip)
  >                 if rc and rc != 0:
  >                     raise error.Abort(b'rebase failed (rc: %d)' % rc)
  >             data[b'tip'] = _node(repo, b'tip')
  >             data[b'revs'] = b','.join(revs[1:])
  >             cmdstate.save(1, data)
  >         cmdstate.delete()
  >         ui.status(b'done chainifying\n')
  > EOF

  $ chainifypath=`pwd`/chainify.py
  $ echo '[extensions]' >> $HGRCPATH
  $ echo "chainify = $chainifypath" >> $HGRCPATH
  $ echo "rebase =" >> $HGRCPATH

  $ cd $TESTTMP
  $ hg init a
  $ cd a
  $ echo base > base.txt
  $ hg commit -Aqm 'base commit'
  $ echo foo > file1
  $ hg commit -Aqm 'add file'
  $ hg co -q ".^"
  $ echo bar > file2
  $ hg commit -Aqm 'add other file'
  $ hg co -q ".^"
  $ echo foo2 > file1
  $ hg commit -Aqm 'add conflicting file'
  $ hg co -q ".^"
  $ hg log --graph --template '{rev} {files}'
  o  3 file1
  |
  | o  2 file2
  |/
  | o  1 file1
  |/
  @  0 base.txt
  
  $ hg chainify -r 8430cfdf77c2 -r f8596309dff8 -r a858b338b3e9
  rebasing f8596309dff8 onto 8430cfdf77c2
  rebasing 2:f8596309dff8 "add other file"
  saved backup bundle to $TESTTMP/* (glob)
  rebasing a858b338b3e9 onto 83c722183a8e
  rebasing 2:a858b338b3e9 "add conflicting file"
  merging file1
  warning: conflicts while merging file1! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see 'hg resolve', then 'hg chainify --continue')
  [240]
  $ hg status --config commands.status.verbose=True
  M file1
  ? file1.orig
  # The repository is in an unfinished *chainify* state.
  
  # Unresolved merge conflicts:
  # 
  #     file1
  # 
  # To mark files as resolved:  hg resolve --mark FILE
  
  # To continue:    hg chainify --continue
  # To abort:       hg chainify --abort
  
  $ echo foo3 > file1
  $ hg resolve --mark file1
  (no more unresolved files)
  continue: hg chainify --continue
  $ hg chainify --continue
  rebasing a858b338b3e9 onto 83c722183a8e
  rebasing 2:a858b338b3e9 "add conflicting file"
  saved backup bundle to $TESTTMP/* (glob)
  done chainifying
  $ hg log --graph --template '{rev} {files}'
  o  3 file1
  |
  o  2 file2
  |
  o  1 file1
  |
  @  0 base.txt
  

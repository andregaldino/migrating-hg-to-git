Setup:
  $ cat > eval.py <<EOF
  > import filecmp
  > from mercurial import commands, context, pycompat, registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > @command(b'eval', [], b'hg eval CMD')
  > def eval_(ui, repo, *cmds, **opts):
  >     cmd = b" ".join(cmds)
  >     res = pycompat.bytestr(eval(cmd, globals(), locals()))
  >     ui.warn(b"%s" % res)
  > EOF

  $ echo "[extensions]" >> $HGRCPATH
  $ echo "eval=`pwd`/eval.py" >> $HGRCPATH

Arbitraryfilectx.cmp does not follow symlinks:
  $ mkdir case1
  $ cd case1
  $ hg init
#if symlink
  $ printf "A" > real_A
  $ printf "foo" > A
  $ printf "foo" > B
  $ ln -s A sym_A
  $ hg add .
  adding A
  adding B
  adding real_A
  adding sym_A
  $ hg commit -m "base"
#else
  $ hg import -q --bypass - <<EOF
  > # HG changeset patch
  > # User test
  > # Date 0 0
  > base
  > 
  > diff --git a/A b/A
  > new file mode 100644
  > --- /dev/null
  > +++ b/A
  > @@ -0,0 +1,1 @@
  > +foo
  > \ No newline at end of file
  > diff --git a/B b/B
  > new file mode 100644
  > --- /dev/null
  > +++ b/B
  > @@ -0,0 +1,1 @@
  > +foo
  > \ No newline at end of file
  > diff --git a/real_A b/real_A
  > new file mode 100644
  > --- /dev/null
  > +++ b/real_A
  > @@ -0,0 +1,1 @@
  > +A
  > \ No newline at end of file
  > diff --git a/sym_A b/sym_A
  > new file mode 120000
  > --- /dev/null
  > +++ b/sym_A
  > @@ -0,0 +1,1 @@
  > +A
  > \ No newline at end of file
  > EOF
  $ hg up -q
#endif

These files are different and should return True (different):
(Note that filecmp.cmp's return semantics are inverted from ours, so we invert
for simplicity):
  $ hg eval "context.arbitraryfilectx(b'A', repo).cmp(repo[None][b'real_A'])"
  True (no-eol)
  $ hg eval "not filecmp.cmp(b'A', b'real_A')"
  True (no-eol)

These files are identical and should return False (same):
  $ hg eval "context.arbitraryfilectx(b'A', repo).cmp(repo[None][b'A'])"
  False (no-eol)
  $ hg eval "context.arbitraryfilectx(b'A', repo).cmp(repo[None][b'B'])"
  False (no-eol)
  $ hg eval "not filecmp.cmp(b'A', b'B')"
  False (no-eol)

This comparison should also return False, since A and sym_A are substantially
the same in the eyes of ``filectx.cmp``, which looks at data only.
  $ hg eval "context.arbitraryfilectx(b'real_A', repo).cmp(repo[None][b'sym_A'])"
  False (no-eol)

A naive use of filecmp on those two would wrongly return True, since it follows
the symlink to "A", which has different contents.
#if symlink
  $ hg eval "not filecmp.cmp(b'real_A', b'sym_A')"
  True (no-eol)
#else
  $ hg eval "not filecmp.cmp(b'real_A', b'sym_A')"
  False (no-eol)
#endif

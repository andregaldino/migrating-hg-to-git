#require execbit unix-permissions no-chg

Checking that experimental.atomic-file works.

  $ cat > $TESTTMP/show_mode.py <<EOF
  > import os
  > import stat
  > import sys
  > ST_MODE = stat.ST_MODE
  > 
  > for file_path in sys.argv[1:]:
  >     file_stat = os.stat(file_path)
  >     octal_mode = oct(file_stat[ST_MODE] & 0o777).replace('o', '')
  >     print("%s:%s" % (file_path, octal_mode))
  > 
  > EOF

  $ hg init repo
  $ cd repo

  $ cat > .hg/showwrites.py <<EOF
  > from mercurial import pycompat
  > from mercurial.utils import stringutil
  > def uisetup(ui):
  >   from mercurial import vfs
  >   class newvfs(vfs.vfs):
  >     def __call__(self, *args, **kwargs):
  >       print(pycompat.sysstr(stringutil.pprint(
  >           ('vfs open', args, sorted(list(kwargs.items()))))))
  >       return super(newvfs, self).__call__(*args, **kwargs)
  >   vfs.vfs = newvfs
  > EOF

  $ for v in a1 a2 b1 b2 c ro; do echo $v > $v; done
  $ chmod +x b*
  $ hg commit -Aqm _

# We check that
# - the changes are actually atomic
# - that permissions are correct (all 4 cases of (executable before) * (executable after))
# - that renames work, though they should be atomic anyway
# - that it works when source files are read-only (but directories are read-write still)

  $ for v in a1 a2 b1 b2 ro; do echo changed-$v > $v; done
  $ chmod -x *1; chmod +x *2
  $ hg rename c d
  $ hg commit -qm _

Check behavior without update.atomic-file

  $ hg update -r 0 -q
  $ hg update -r 1 --config extensions.showwrites=.hg/showwrites.py 2>&1 | grep "a1'.*wb"
  ('vfs open', ('a1', 'wb'), [('atomictemp', False), ('backgroundclose', True)])

  $ "$PYTHON" $TESTTMP/show_mode.py *
  a1:0644
  a2:0755
  b1:0644
  b2:0755
  d:0644
  ro:0644

Add a second revision for the ro file so we can test update when the file is
present or not

  $ echo "ro" > ro

  $ hg commit -qm _

Check behavior without update.atomic-file first

  $ hg update -C -r 0 -q

  $ hg update -r 1
  6 files updated, 0 files merged, 1 files removed, 0 files unresolved

  $ "$PYTHON" $TESTTMP/show_mode.py *
  a1:0644
  a2:0755
  b1:0644
  b2:0755
  d:0644
  ro:0644

Manually reset the mode of the read-only file

  $ chmod a-w ro

  $ "$PYTHON" $TESTTMP/show_mode.py ro
  ro:0444

Now the file is present, try to update and check the permissions of the file

  $ hg up -r 2
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ "$PYTHON" $TESTTMP/show_mode.py ro
  ro:0644

# The file which was read-only is now writable in the default behavior

Check behavior with update.atomic-files


  $ cat >> .hg/hgrc <<EOF
  > [experimental]
  > update.atomic-file = true
  > EOF

  $ hg update -C -r 0 -q
  $ hg update -r 1 --config extensions.showwrites=.hg/showwrites.py 2>&1 | grep "a1'.*wb"
  ('vfs open', ('a1', 'wb'), [('atomictemp', True), ('backgroundclose', True)])
  $ hg st -A --rev 1
  C a1
  C a2
  C b1
  C b2
  C d
  C ro

Check the file permission after update
  $ "$PYTHON" $TESTTMP/show_mode.py *
  a1:0644
  a2:0755
  b1:0644
  b2:0755
  d:0644
  ro:0644

Manually reset the mode of the read-only file

  $ chmod a-w ro

  $ "$PYTHON" $TESTTMP/show_mode.py ro
  ro:0444

Now the file is present, try to update and check the permissions of the file

  $ hg update -r 2 --traceback
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ "$PYTHON" $TESTTMP/show_mode.py ro
  ro:0644

# The behavior is the same as without atomic update

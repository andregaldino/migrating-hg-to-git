# setup some files and commit for a good stream clone testing.

touch foo
hg -q commit -A -m initial

python3 << EOF
for i in range(1024):
    with open(str(i), 'wb') as fh:
        fh.write(b"%d" % i) and None
EOF
hg -q commit -A -m 'add a lot of files'

# (the status call is to check for issue5130)

hg st

# add files with "tricky" name:

echo foo > 00changelog.i
echo foo > 00changelog.d
echo foo > 00changelog.n
echo foo > 00changelog-ab349180a0405010.nd
echo foo > 00manifest.i
echo foo > 00manifest.d
echo foo > foo.i
echo foo > foo.d
echo foo > foo.n
echo foo > undo.py
echo foo > undo.i
echo foo > undo.d
echo foo > undo.n
echo foo > undo.foo.i
echo foo > undo.foo.d
echo foo > undo.foo.n
echo foo > undo.babar
mkdir savanah
echo foo > savanah/foo.i
echo foo > savanah/foo.d
echo foo > savanah/foo.n
echo foo > savanah/undo.py
echo foo > savanah/undo.i
echo foo > savanah/undo.d
echo foo > savanah/undo.n
echo foo > savanah/undo.foo.i
echo foo > savanah/undo.foo.d
echo foo > savanah/undo.foo.n
echo foo > savanah/undo.babar
mkdir data
echo foo > data/foo.i
echo foo > data/foo.d
echo foo > data/foo.n
echo foo > data/undo.py
echo foo > data/undo.i
echo foo > data/undo.d
echo foo > data/undo.n
echo foo > data/undo.foo.i
echo foo > data/undo.foo.d
echo foo > data/undo.foo.n
echo foo > data/undo.babar
mkdir meta
echo foo > meta/foo.i
echo foo > meta/foo.d
echo foo > meta/foo.n
echo foo > meta/undo.py
echo foo > meta/undo.i
echo foo > meta/undo.d
echo foo > meta/undo.n
echo foo > meta/undo.foo.i
echo foo > meta/undo.foo.d
echo foo > meta/undo.foo.n
echo foo > meta/undo.babar
mkdir store
echo foo > store/foo.i
echo foo > store/foo.d
echo foo > store/foo.n
echo foo > store/undo.py
echo foo > store/undo.i
echo foo > store/undo.d
echo foo > store/undo.n
echo foo > store/undo.foo.i
echo foo > store/undo.foo.d
echo foo > store/undo.foo.n
echo foo > store/undo.babar

# Name with special characters

echo foo > store/CélesteVille_is_a_Capital_City

# name causing issue6581

mkdir -p container/isam-build-centos7/
touch container/isam-build-centos7/bazel-coverage-generator-sandboxfs-compatibility-0758e3e4f6057904d44399bd666faba9e7f40686.patch

# Add all that

hg add .
hg ci -m 'add files with "tricky" name'

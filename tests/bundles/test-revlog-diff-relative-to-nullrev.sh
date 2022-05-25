#!/bin/bash
#
# Make sure to patch mercurial to create the delta against nullrev
#          if deltainfo is None:
#-             deltainfo = self._fullsnapshotinfo(fh, revinfo, target_rev)
#+             deltainfo = self._builddeltainfo(revinfo, nullrev, fh)

cd "`dirname \"$0\"`"
export HGRCPATH=
export HGMODULEPOLICY=py

rm -rf nullrev-diff
../../hg init nullrev-diff  --config format.revlog-compression=zlib
cd nullrev-diff
echo hi > a
../../../hg commit -Am root-B
../../../hg debugdeltachain a
rm -rf .hg/cache/ .hg/wcache/
cd ..

tar cf test-revlog-diff-relative-to-nullrev.tar nullrev-diff

rm -rf nullrev-diff

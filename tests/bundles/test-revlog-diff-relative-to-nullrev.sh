#!/bin/bash
#
# Make sure to patch mercurial to create the delta against nullrev
#
# # Parent  cdb85d0512b81031d4a7b30d6a5ddbe69ef1a876
#
# diff --git a/mercurial/revlogutils/deltas.py b/mercurial/revlogutils/deltas.py
# --- a/mercurial/revlogutils/deltas.py
# +++ b/mercurial/revlogutils/deltas.py
# @@ -1117,7 +1117,10 @@ class deltacomputer:
#                  candidaterevs = next(groups)
#
#          if deltainfo is None:
# -            deltainfo = self._fullsnapshotinfo(fh, revinfo, target_rev)
# +            if revlog._generaldelta:
# +                deltainfo = self._builddeltainfo(revinfo, nullrev, fh)
# +            else:
# +                deltainfo = self._fullsnapshotinfo(fh, revinfo, target_rev)


cd "`dirname \"$0\"`"
export HGRCPATH=
export HGMODULEPOLICY=py

rm -rf nullrev-diff
../../hg init nullrev-diff  --config format.revlog-compression=zlib
cd nullrev-diff
echo hi > a
../../../hg commit -Am root-B
echo ho > a
../../../hg commit -Am child-A
hg up null
echo ha > a
../../../hg commit -Am root-A
../../../hg debugdeltachain a
rm -rf .hg/cache/ .hg/wcache/
cd ..

tar cf test-revlog-diff-relative-to-nullrev.tar nullrev-diff

rm -rf nullrev-diff

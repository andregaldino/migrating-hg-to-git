        return r"<patchmeta %s %r>" % (self.op, self.path)
         opts=None, losedatafn=None, pathfn=None, copy=None,
         copysourcematch=None, hunksfilterfn=None):
    if copysourcematch is not None, then copy sources will be filtered by this
    matcher

    if not node1 and not node2:
        node1 = repo.dirstate.p1()

    ctx1 = repo[node1]
    ctx2 = repo[node2]

            repo, ctx1=ctx1, ctx2=ctx2, match=match, changes=changes, opts=opts,
            losedatafn=losedatafn, pathfn=pathfn, copy=copy,
            copysourcematch=copysourcematch):
def diffhunks(repo, ctx1, ctx2, match=None, changes=None, opts=None,
              losedatafn=None, pathfn=None, copy=None, copysourcematch=None):
    if copysourcematch:
        # filter out copies where source side isn't inside the matcher
                if copysourcematch(src)}
                       copy, getfilectx, opts, losedata, pathfn)
            copy, getfilectx, opts, losedatafn, pathfn):
    pathfn is applied to every path in the diff output.
    '''
    if not pathfn:
        pathfn = lambda f: f
        path1 = pathfn(f1 or f2)
        path2 = pathfn(f2 or f1)
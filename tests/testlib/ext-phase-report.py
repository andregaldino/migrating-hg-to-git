# tiny extension to report phase changes during transaction


def reposetup(ui, repo):
    def reportphasemove(tr):
        for revs, move in sorted(tr.changes[b"phases"], key=lambda r: r[0][0]):
            for rev in revs:
                if move[0] is None:
                    ui.write(
                        (
                            b'test-debug-phase: new rev %d:  x -> %d\n'
                            % (rev, move[1])
                        )
                    )
                else:
                    ui.write(
                        (
                            b'test-debug-phase: move rev %d: %d -> %d\n'
                            % (rev, move[0], move[1])
                        )
                    )

    class reportphaserepo(repo.__class__):
        def transaction(self, *args, **kwargs):
            tr = super(reportphaserepo, self).transaction(*args, **kwargs)
            tr.addpostclose(b'report-phase', reportphasemove)
            return tr

    repo.__class__ = reportphaserepo

from mercurial import (
    encoding,
    extensions,
    streamclone,
    testing,
)


WALKED_FILE_1 = encoding.environ[b'HG_TEST_STREAM_WALKED_FILE_1']
WALKED_FILE_2 = encoding.environ[b'HG_TEST_STREAM_WALKED_FILE_2']


def _test_sync_point_walk_1(orig, repo):
    testing.write_file(WALKED_FILE_1)


def _test_sync_point_walk_2(orig, repo):
    assert repo._currentlock(repo._lockref) is None
    testing.wait_file(WALKED_FILE_2)


def uisetup(ui):
    extensions.wrapfunction(
        streamclone, '_test_sync_point_walk_1', _test_sync_point_walk_1
    )

    extensions.wrapfunction(
        streamclone, '_test_sync_point_walk_2', _test_sync_point_walk_2
    )

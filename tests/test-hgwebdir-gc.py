import os
from mercurial.hgweb import hgwebdir_mod

hgwebdir = hgwebdir_mod.hgwebdir

os.mkdir(b'webdir')
os.chdir(b'webdir')

webdir = os.path.realpath(b'.')


def trivial_response(req, res):
    return []


def make_hgwebdir(gc_rate=None):
    config = os.path.join(webdir, b'hgwebdir.conf')
    with open(config, 'wb') as configfile:
        configfile.write(b'[experimental]\n')
        if gc_rate is not None:
            configfile.write(b'web.full-garbage-collection-rate=%d\n' % gc_rate)
    hg_wd = hgwebdir(config)
    hg_wd._runwsgi = trivial_response
    return hg_wd


def process_requests(webdir_instance, number):
    # we don't care for now about passing realistic arguments
    for _ in range(number):
        for chunk in webdir_instance.run_wsgi(None, None):
            pass


without_gc = make_hgwebdir(gc_rate=0)
process_requests(without_gc, 5)
assert without_gc.requests_count == 5
assert without_gc.gc_full_collections_done == 0

with_gc = make_hgwebdir(gc_rate=2)
process_requests(with_gc, 5)
assert with_gc.requests_count == 5
assert with_gc.gc_full_collections_done == 2

with_systematic_gc = make_hgwebdir()  # default value of the setting
process_requests(with_systematic_gc, 3)
assert with_systematic_gc.requests_count == 3
assert with_systematic_gc.gc_full_collections_done == 3

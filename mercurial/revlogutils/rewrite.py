# censor code related to censoring revision
# coding: utf8
#
# Copyright 2021 Pierre-Yves David <pierre-yves.david@octobus.net>
# Copyright 2015 Google, Inc <martinvonz@google.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

import contextlib
import os

from ..node import (
    nullrev,
)
from .constants import (
    COMP_MODE_PLAIN,
    ENTRY_DATA_COMPRESSED_LENGTH,
    ENTRY_DATA_COMPRESSION_MODE,
    ENTRY_DATA_OFFSET,
    ENTRY_DATA_UNCOMPRESSED_LENGTH,
    ENTRY_DELTA_BASE,
    ENTRY_LINK_REV,
    ENTRY_NODE_ID,
    ENTRY_PARENT_1,
    ENTRY_PARENT_2,
    ENTRY_SIDEDATA_COMPRESSED_LENGTH,
    ENTRY_SIDEDATA_COMPRESSION_MODE,
    ENTRY_SIDEDATA_OFFSET,
    REVLOGV0,
    REVLOGV1,
)
from ..i18n import _

from .. import (
    error,
    pycompat,
    revlogutils,
    util,
)
from ..utils import (
    storageutil,
)
from . import (
    constants,
    deltas,
)


def v1_censor(rl, tr, censornode, tombstone=b''):
    """censors a revision in a "version 1" revlog"""
    assert rl._format_version == constants.REVLOGV1, rl._format_version

    # avoid cycle
    from .. import revlog

    censorrev = rl.rev(censornode)
    tombstone = storageutil.packmeta({b'censored': tombstone}, b'')

    # Rewriting the revlog in place is hard. Our strategy for censoring is
    # to create a new revlog, copy all revisions to it, then replace the
    # revlogs on transaction close.
    #
    # This is a bit dangerous. We could easily have a mismatch of state.
    newrl = revlog.revlog(
        rl.opener,
        target=rl.target,
        radix=rl.radix,
        postfix=b'tmpcensored',
        censorable=True,
    )
    newrl._format_version = rl._format_version
    newrl._format_flags = rl._format_flags
    newrl._generaldelta = rl._generaldelta
    newrl._parse_index = rl._parse_index

    for rev in rl.revs():
        node = rl.node(rev)
        p1, p2 = rl.parents(node)

        if rev == censorrev:
            newrl.addrawrevision(
                tombstone,
                tr,
                rl.linkrev(censorrev),
                p1,
                p2,
                censornode,
                constants.REVIDX_ISCENSORED,
            )

            if newrl.deltaparent(rev) != nullrev:
                m = _(b'censored revision stored as delta; cannot censor')
                h = _(
                    b'censoring of revlogs is not fully implemented;'
                    b' please report this bug'
                )
                raise error.Abort(m, hint=h)
            continue

        if rl.iscensored(rev):
            if rl.deltaparent(rev) != nullrev:
                m = _(
                    b'cannot censor due to censored '
                    b'revision having delta stored'
                )
                raise error.Abort(m)
            rawtext = rl._chunk(rev)
        else:
            rawtext = rl.rawdata(rev)

        newrl.addrawrevision(
            rawtext, tr, rl.linkrev(rev), p1, p2, node, rl.flags(rev)
        )

    tr.addbackup(rl._indexfile, location=b'store')
    if not rl._inline:
        tr.addbackup(rl._datafile, location=b'store')

    rl.opener.rename(newrl._indexfile, rl._indexfile)
    if not rl._inline:
        rl.opener.rename(newrl._datafile, rl._datafile)

    rl.clearcaches()
    rl._loadindex()


def v2_censor(revlog, tr, censornode, tombstone=b''):
    """censors a revision in a "version 2" revlog"""
    assert revlog._format_version != REVLOGV0, revlog._format_version
    assert revlog._format_version != REVLOGV1, revlog._format_version

    censor_revs = {revlog.rev(censornode)}
    _rewrite_v2(revlog, tr, censor_revs, tombstone)


def _rewrite_v2(revlog, tr, censor_revs, tombstone=b''):
    """rewrite a revlog to censor some of its content

    General principle

    We create new revlog files (index/data/sidedata) to copy the content of
    the existing data without the censored data.

    We need to recompute new delta for any revision that used the censored
    revision as delta base. As the cumulative size of the new delta may be
    large, we store them in a temporary file until they are stored in their
    final destination.

    All data before the censored data can be blindly copied. The rest needs
    to be copied as we go and the associated index entry needs adjustement.
    """
    assert revlog._format_version != REVLOGV0, revlog._format_version
    assert revlog._format_version != REVLOGV1, revlog._format_version

    old_index = revlog.index
    docket = revlog._docket

    tombstone = storageutil.packmeta({b'censored': tombstone}, b'')

    first_excl_rev = min(censor_revs)

    first_excl_entry = revlog.index[first_excl_rev]
    index_cutoff = revlog.index.entry_size * first_excl_rev
    data_cutoff = first_excl_entry[ENTRY_DATA_OFFSET] >> 16
    sidedata_cutoff = revlog.sidedata_cut_off(first_excl_rev)

    with pycompat.unnamedtempfile(mode=b"w+b") as tmp_storage:
        # rev → (new_base, data_start, data_end, compression_mode)
        rewritten_entries = _precompute_rewritten_delta(
            revlog,
            old_index,
            censor_revs,
            tmp_storage,
        )

        all_files = _setup_new_files(
            revlog,
            index_cutoff,
            data_cutoff,
            sidedata_cutoff,
        )

        # we dont need to open the old index file since its content already
        # exist in a usable form in `old_index`.
        with all_files() as open_files:
            (
                old_data_file,
                old_sidedata_file,
                new_index_file,
                new_data_file,
                new_sidedata_file,
            ) = open_files

            # writing the censored revision

            # Writing all subsequent revisions
            for rev in range(first_excl_rev, len(old_index)):
                if rev in censor_revs:
                    _rewrite_censor(
                        revlog,
                        old_index,
                        open_files,
                        rev,
                        tombstone,
                    )
                else:
                    _rewrite_simple(
                        revlog,
                        old_index,
                        open_files,
                        rev,
                        rewritten_entries,
                        tmp_storage,
                    )
    docket.write(transaction=None, stripping=True)


def _precompute_rewritten_delta(
    revlog,
    old_index,
    excluded_revs,
    tmp_storage,
):
    """Compute new delta for revisions whose delta is based on revision that
    will not survive as is.

    Return a mapping: {rev → (new_base, data_start, data_end, compression_mode)}
    """
    dc = deltas.deltacomputer(revlog)
    rewritten_entries = {}
    first_excl_rev = min(excluded_revs)
    with revlog._segmentfile._open_read() as dfh:
        for rev in range(first_excl_rev, len(old_index)):
            if rev in excluded_revs:
                # this revision will be preserved as is, so we don't need to
                # consider recomputing a delta.
                continue
            entry = old_index[rev]
            if entry[ENTRY_DELTA_BASE] not in excluded_revs:
                continue
            # This is a revision that use the censored revision as the base
            # for its delta. We need a need new deltas
            if entry[ENTRY_DATA_UNCOMPRESSED_LENGTH] == 0:
                # this revision is empty, we can delta against nullrev
                rewritten_entries[rev] = (nullrev, 0, 0, COMP_MODE_PLAIN)
            else:

                text = revlog.rawdata(rev, _df=dfh)
                info = revlogutils.revisioninfo(
                    node=entry[ENTRY_NODE_ID],
                    p1=revlog.node(entry[ENTRY_PARENT_1]),
                    p2=revlog.node(entry[ENTRY_PARENT_2]),
                    btext=[text],
                    textlen=len(text),
                    cachedelta=None,
                    flags=entry[ENTRY_DATA_OFFSET] & 0xFFFF,
                )
                d = dc.finddeltainfo(
                    info, dfh, excluded_bases=excluded_revs, target_rev=rev
                )
                default_comp = revlog._docket.default_compression_header
                comp_mode, d = deltas.delta_compression(default_comp, d)
                # using `tell` is a bit lazy, but we are not here for speed
                start = tmp_storage.tell()
                tmp_storage.write(d.data[1])
                end = tmp_storage.tell()
                rewritten_entries[rev] = (d.base, start, end, comp_mode)
    return rewritten_entries


def _setup_new_files(
    revlog,
    index_cutoff,
    data_cutoff,
    sidedata_cutoff,
):
    """

    return a context manager to open all the relevant files:
    - old_data_file,
    - old_sidedata_file,
    - new_index_file,
    - new_data_file,
    - new_sidedata_file,

    The old_index_file is not here because it is accessed through the
    `old_index` object if the caller function.
    """
    docket = revlog._docket
    old_index_filepath = revlog.opener.join(docket.index_filepath())
    old_data_filepath = revlog.opener.join(docket.data_filepath())
    old_sidedata_filepath = revlog.opener.join(docket.sidedata_filepath())

    new_index_filepath = revlog.opener.join(docket.new_index_file())
    new_data_filepath = revlog.opener.join(docket.new_data_file())
    new_sidedata_filepath = revlog.opener.join(docket.new_sidedata_file())

    util.copyfile(old_index_filepath, new_index_filepath, nb_bytes=index_cutoff)
    util.copyfile(old_data_filepath, new_data_filepath, nb_bytes=data_cutoff)
    util.copyfile(
        old_sidedata_filepath,
        new_sidedata_filepath,
        nb_bytes=sidedata_cutoff,
    )
    revlog.opener.register_file(docket.index_filepath())
    revlog.opener.register_file(docket.data_filepath())
    revlog.opener.register_file(docket.sidedata_filepath())

    docket.index_end = index_cutoff
    docket.data_end = data_cutoff
    docket.sidedata_end = sidedata_cutoff

    # reload the revlog internal information
    revlog.clearcaches()
    revlog._loadindex(docket=docket)

    @contextlib.contextmanager
    def all_files_opener():
        # hide opening in an helper function to please check-code, black
        # and various python version at the same time
        with open(old_data_filepath, 'rb') as old_data_file:
            with open(old_sidedata_filepath, 'rb') as old_sidedata_file:
                with open(new_index_filepath, 'r+b') as new_index_file:
                    with open(new_data_filepath, 'r+b') as new_data_file:
                        with open(
                            new_sidedata_filepath, 'r+b'
                        ) as new_sidedata_file:
                            new_index_file.seek(0, os.SEEK_END)
                            assert new_index_file.tell() == index_cutoff
                            new_data_file.seek(0, os.SEEK_END)
                            assert new_data_file.tell() == data_cutoff
                            new_sidedata_file.seek(0, os.SEEK_END)
                            assert new_sidedata_file.tell() == sidedata_cutoff
                            yield (
                                old_data_file,
                                old_sidedata_file,
                                new_index_file,
                                new_data_file,
                                new_sidedata_file,
                            )

    return all_files_opener


def _rewrite_simple(
    revlog,
    old_index,
    all_files,
    rev,
    rewritten_entries,
    tmp_storage,
):
    """append a normal revision to the index after the rewritten one(s)"""
    (
        old_data_file,
        old_sidedata_file,
        new_index_file,
        new_data_file,
        new_sidedata_file,
    ) = all_files
    entry = old_index[rev]
    flags = entry[ENTRY_DATA_OFFSET] & 0xFFFF
    old_data_offset = entry[ENTRY_DATA_OFFSET] >> 16

    if rev not in rewritten_entries:
        old_data_file.seek(old_data_offset)
        new_data_size = entry[ENTRY_DATA_COMPRESSED_LENGTH]
        new_data = old_data_file.read(new_data_size)
        data_delta_base = entry[ENTRY_DELTA_BASE]
        d_comp_mode = entry[ENTRY_DATA_COMPRESSION_MODE]
    else:
        (
            data_delta_base,
            start,
            end,
            d_comp_mode,
        ) = rewritten_entries[rev]
        new_data_size = end - start
        tmp_storage.seek(start)
        new_data = tmp_storage.read(new_data_size)

    # It might be faster to group continuous read/write operation,
    # however, this is censor, an operation that is not focussed
    # around stellar performance. So I have not written this
    # optimisation yet.
    new_data_offset = new_data_file.tell()
    new_data_file.write(new_data)

    sidedata_size = entry[ENTRY_SIDEDATA_COMPRESSED_LENGTH]
    new_sidedata_offset = new_sidedata_file.tell()
    if 0 < sidedata_size:
        old_sidedata_offset = entry[ENTRY_SIDEDATA_OFFSET]
        old_sidedata_file.seek(old_sidedata_offset)
        new_sidedata = old_sidedata_file.read(sidedata_size)
        new_sidedata_file.write(new_sidedata)

    data_uncompressed_length = entry[ENTRY_DATA_UNCOMPRESSED_LENGTH]
    sd_com_mode = entry[ENTRY_SIDEDATA_COMPRESSION_MODE]
    assert data_delta_base <= rev, (data_delta_base, rev)

    new_entry = revlogutils.entry(
        flags=flags,
        data_offset=new_data_offset,
        data_compressed_length=new_data_size,
        data_uncompressed_length=data_uncompressed_length,
        data_delta_base=data_delta_base,
        link_rev=entry[ENTRY_LINK_REV],
        parent_rev_1=entry[ENTRY_PARENT_1],
        parent_rev_2=entry[ENTRY_PARENT_2],
        node_id=entry[ENTRY_NODE_ID],
        sidedata_offset=new_sidedata_offset,
        sidedata_compressed_length=sidedata_size,
        data_compression_mode=d_comp_mode,
        sidedata_compression_mode=sd_com_mode,
    )
    revlog.index.append(new_entry)
    entry_bin = revlog.index.entry_binary(rev)
    new_index_file.write(entry_bin)

    revlog._docket.index_end = new_index_file.tell()
    revlog._docket.data_end = new_data_file.tell()
    revlog._docket.sidedata_end = new_sidedata_file.tell()


def _rewrite_censor(
    revlog,
    old_index,
    all_files,
    rev,
    tombstone,
):
    """rewrite and append a censored revision"""
    (
        old_data_file,
        old_sidedata_file,
        new_index_file,
        new_data_file,
        new_sidedata_file,
    ) = all_files
    entry = old_index[rev]

    # XXX consider trying the default compression too
    new_data_size = len(tombstone)
    new_data_offset = new_data_file.tell()
    new_data_file.write(tombstone)

    # we are not adding any sidedata as they might leak info about the censored version

    link_rev = entry[ENTRY_LINK_REV]

    p1 = entry[ENTRY_PARENT_1]
    p2 = entry[ENTRY_PARENT_2]

    new_entry = revlogutils.entry(
        flags=constants.REVIDX_ISCENSORED,
        data_offset=new_data_offset,
        data_compressed_length=new_data_size,
        data_uncompressed_length=new_data_size,
        data_delta_base=rev,
        link_rev=link_rev,
        parent_rev_1=p1,
        parent_rev_2=p2,
        node_id=entry[ENTRY_NODE_ID],
        sidedata_offset=0,
        sidedata_compressed_length=0,
        data_compression_mode=COMP_MODE_PLAIN,
        sidedata_compression_mode=COMP_MODE_PLAIN,
    )
    revlog.index.append(new_entry)
    entry_bin = revlog.index.entry_binary(rev)
    new_index_file.write(entry_bin)
    revlog._docket.index_end = new_index_file.tell()
    revlog._docket.data_end = new_data_file.tell()

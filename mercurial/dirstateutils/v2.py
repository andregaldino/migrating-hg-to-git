# v2.py - Pure-Python implementation of the dirstate-v2 file format
#
# Copyright Mercurial Contributors
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import struct

from .. import policy

parsers = policy.importmod('parsers')


# Must match the constant of the same name in
# `rust/hg-core/src/dirstate_tree/on_disk.rs`
TREE_METADATA_SIZE = 44
NODE_SIZE = 43


# Must match the `TreeMetadata` Rust struct in
# `rust/hg-core/src/dirstate_tree/on_disk.rs`. See doc-comments there.
#
# * 4 bytes: start offset of root nodes
# * 4 bytes: number of root nodes
# * 4 bytes: total number of nodes in the tree that have an entry
# * 4 bytes: total number of nodes in the tree that have a copy source
# * 4 bytes: number of bytes in the data file that are not used anymore
# * 4 bytes: unused
# * 20 bytes: SHA-1 hash of ignore patterns
TREE_METADATA = struct.Struct('>LLLLL4s20s')


# Must match the `Node` Rust struct in
# `rust/hg-core/src/dirstate_tree/on_disk.rs`. See doc-comments there.
#
# * 4 bytes: start offset of full path
# * 2 bytes: length of the full path
# * 2 bytes: length within the full path before its "base name"
# * 4 bytes: start offset of the copy source if any, or zero for no copy source
# * 2 bytes: length of the copy source if any, or unused
# * 4 bytes: start offset of child nodes
# * 4 bytes: number of child nodes
# * 4 bytes: number of descendant nodes that have an entry
# * 4 bytes: number of descendant nodes that have a "tracked" state
# * 1 byte: flags
# * 4 bytes: expected size
# * 4 bytes: mtime seconds
# * 4 bytes: mtime nanoseconds
NODE = struct.Struct('>LHHLHLLLLBlll')


assert TREE_METADATA_SIZE == TREE_METADATA.size
assert NODE_SIZE == NODE.size


def parse_dirstate(map, copy_map, data, tree_metadata):
    """parse a full v2-dirstate from a binary data into dictionnaries:

    - map: a {path: entry} mapping that will be filled
    - copy_map: a {path: copy-source} mapping that will be filled
    - data: a binary blob contains v2 nodes data
    - tree_metadata:: a binary blob of the top level node (from the docket)
    """
    (
        root_nodes_start,
        root_nodes_len,
        _nodes_with_entry_count,
        _nodes_with_copy_source_count,
        _unreachable_bytes,
        _unused,
        _ignore_patterns_hash,
    ) = TREE_METADATA.unpack(tree_metadata)
    parse_nodes(map, copy_map, data, root_nodes_start, root_nodes_len)


def parse_nodes(map, copy_map, data, start, len):
    """parse <len> nodes from <data> starting at offset <start>

    This is used by parse_dirstate to recursively fill `map` and `copy_map`.
    """
    for i in range(len):
        node_start = start + NODE_SIZE * i
        node_bytes = slice_with_len(data, node_start, NODE_SIZE)
        (
            path_start,
            path_len,
            _basename_start,
            copy_source_start,
            copy_source_len,
            children_start,
            children_count,
            _descendants_with_entry_count,
            _tracked_descendants_count,
            flags,
            size,
            mtime_s,
            _mtime_ns,
        ) = NODE.unpack(node_bytes)

        # Parse child nodes of this node recursively
        parse_nodes(map, copy_map, data, children_start, children_count)

        item = parsers.DirstateItem.from_v2_data(flags, size, mtime_s)
        if not item.any_tracked:
            continue
        path = slice_with_len(data, path_start, path_len)
        map[path] = item
        if copy_source_start:
            copy_map[path] = slice_with_len(
                data, copy_source_start, copy_source_len
            )


def slice_with_len(data, start, len):
    return data[start : start + len]

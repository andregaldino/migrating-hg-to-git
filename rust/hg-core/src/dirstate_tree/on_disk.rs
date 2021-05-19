//! The "version 2" disk representation of the dirstate
//!
//! # File format
//!
//! The file starts with a fixed-sized header, whose layout is defined by the
//! `Header` struct. Its `root` field contains the slice (offset and length) to
//! the nodes representing the files and directories at the root of the
//! repository. Each node is also fixed-size, defined by the `Node` struct.
//! Nodes in turn contain slices to variable-size paths, and to their own child
//! nodes (if any) for nested files and directories.

use crate::dirstate_tree::dirstate_map::{self, DirstateMap, NodeRef};
use crate::dirstate_tree::path_with_basename::WithBasename;
use crate::errors::HgError;
use crate::utils::hg_path::HgPath;
use crate::DirstateEntry;
use crate::DirstateError;
use crate::DirstateParents;
use crate::EntryState;
use bytes_cast::unaligned::{I32Be, U32Be, U64Be};
use bytes_cast::BytesCast;
use std::borrow::Cow;
use std::convert::{TryFrom, TryInto};

/// Added at the start of `.hg/dirstate` when the "v2" format is used.
/// This a redundant sanity check more than an actual "magic number" since
/// `.hg/requires` already governs which format should be used.
pub const V2_FORMAT_MARKER: &[u8; 12] = b"dirstate-v2\n";

#[derive(BytesCast)]
#[repr(C)]
struct Header {
    marker: [u8; V2_FORMAT_MARKER.len()],

    /// `dirstatemap.parents()` in `mercurial/dirstate.py` relies on this
    /// `parents` field being at this offset, immediately after `marker`.
    parents: DirstateParents,

    root: ChildNodes,
    nodes_with_entry_count: Size,
    nodes_with_copy_source_count: Size,
}

#[derive(BytesCast)]
#[repr(C)]
pub(super) struct Node {
    full_path: PathSlice,

    /// In bytes from `self.full_path.start`
    base_name_start: Size,

    copy_source: OptPathSlice,
    entry: OptEntry,
    children: ChildNodes,
    pub(super) tracked_descendants_count: Size,
}

/// Either nothing if `state == b'\0'`, or a dirstate entry like in the v1
/// format
#[derive(BytesCast, Copy, Clone)]
#[repr(C)]
struct OptEntry {
    state: u8,
    mode: I32Be,
    mtime: I32Be,
    size: I32Be,
}

/// Counted in bytes from the start of the file
///
/// NOTE: If we decide to never support `.hg/dirstate` files larger than 4 GiB
/// we could save space by using `U32Be` instead.
type Offset = U64Be;

/// Counted in number of items
///
/// NOTE: not supporting directories with more than 4 billion direct children,
/// or filenames more than 4 GiB.
type Size = U32Be;

/// Location of consecutive, fixed-size items.
///
/// An item can be a single byte for paths, or a struct with
/// `derive(BytesCast)`.
#[derive(BytesCast, Copy, Clone)]
#[repr(C)]
struct Slice {
    start: Offset,
    len: Size,
}

/// A contiguous sequence of `len` times `Node`, representing the child nodes
/// of either some other node or of the repository root.
///
/// Always sorted by ascending `full_path`, to allow binary search.
/// Since nodes with the same parent nodes also have the same parent path,
/// only the `base_name`s need to be compared during binary search.
type ChildNodes = Slice;

/// A `HgPath` of `len` bytes
type PathSlice = Slice;

/// Either nothing if `start == 0`, or a `HgPath` of `len` bytes
type OptPathSlice = Slice;

/// Make sure that size-affecting changes are made knowingly
fn _static_assert_size_of() {
    let _ = std::mem::transmute::<Header, [u8; 72]>;
    let _ = std::mem::transmute::<Node, [u8; 57]>;
}

/// Unexpected file format found in `.hg/dirstate` with the "v2" format.
///
/// This should only happen if Mercurial is buggy or a repository is corrupted.
#[derive(Debug)]
pub struct DirstateV2ParseError;

impl From<DirstateV2ParseError> for HgError {
    fn from(_: DirstateV2ParseError) -> Self {
        HgError::corrupted("dirstate-v2 parse error")
    }
}

impl From<DirstateV2ParseError> for crate::DirstateError {
    fn from(error: DirstateV2ParseError) -> Self {
        HgError::from(error).into()
    }
}

pub(super) fn read<'on_disk>(
    on_disk: &'on_disk [u8],
) -> Result<
    (DirstateMap<'on_disk>, Option<DirstateParents>),
    DirstateV2ParseError,
> {
    if on_disk.is_empty() {
        return Ok((DirstateMap::empty(on_disk), None));
    }
    let (header, _) =
        Header::from_bytes(on_disk).map_err(|_| DirstateV2ParseError)?;
    let Header {
        marker,
        parents,
        root,
        nodes_with_entry_count,
        nodes_with_copy_source_count,
    } = header;
    if marker != V2_FORMAT_MARKER {
        return Err(DirstateV2ParseError);
    }
    let dirstate_map = DirstateMap {
        on_disk,
        root: dirstate_map::ChildNodes::OnDisk(read_slice::<Node>(
            on_disk, *root,
        )?),
        nodes_with_entry_count: nodes_with_entry_count.get(),
        nodes_with_copy_source_count: nodes_with_copy_source_count.get(),
    };
    let parents = Some(parents.clone());
    Ok((dirstate_map, parents))
}

impl Node {
    pub(super) fn full_path<'on_disk>(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<&'on_disk HgPath, DirstateV2ParseError> {
        read_hg_path(on_disk, self.full_path)
    }

    pub(super) fn base_name_start<'on_disk>(
        &self,
    ) -> Result<usize, DirstateV2ParseError> {
        let start = self.base_name_start.get();
        if start < self.full_path.len.get() {
            let start = usize::try_from(start)
                // u32 -> usize, could only panic on a 16-bit CPU
                .expect("dirstate-v2 base_name_start out of bounds");
            Ok(start)
        } else {
            Err(DirstateV2ParseError)
        }
    }

    pub(super) fn base_name<'on_disk>(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<&'on_disk HgPath, DirstateV2ParseError> {
        let full_path = self.full_path(on_disk)?;
        let base_name_start = self.base_name_start()?;
        Ok(HgPath::new(&full_path.as_bytes()[base_name_start..]))
    }

    pub(super) fn path<'on_disk>(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<dirstate_map::NodeKey<'on_disk>, DirstateV2ParseError> {
        Ok(WithBasename::from_raw_parts(
            Cow::Borrowed(self.full_path(on_disk)?),
            self.base_name_start()?,
        ))
    }

    pub(super) fn has_copy_source<'on_disk>(&self) -> bool {
        self.copy_source.start.get() != 0
    }

    pub(super) fn copy_source<'on_disk>(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<Option<&'on_disk HgPath>, DirstateV2ParseError> {
        Ok(if self.has_copy_source() {
            Some(read_hg_path(on_disk, self.copy_source)?)
        } else {
            None
        })
    }

    pub(super) fn has_entry(&self) -> bool {
        self.entry.state != b'\0'
    }

    pub(super) fn state(
        &self,
    ) -> Result<Option<EntryState>, DirstateV2ParseError> {
        Ok(if self.has_entry() {
            Some(
                self.entry
                    .state
                    .try_into()
                    .map_err(|_| DirstateV2ParseError)?,
            )
        } else {
            None
        })
    }

    pub(super) fn entry(
        &self,
    ) -> Result<Option<DirstateEntry>, DirstateV2ParseError> {
        Ok(self.state()?.map(|state| DirstateEntry {
            state,
            mode: self.entry.mode.get(),
            mtime: self.entry.mtime.get(),
            size: self.entry.size.get(),
        }))
    }

    pub(super) fn children<'on_disk>(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<&'on_disk [Node], DirstateV2ParseError> {
        read_slice::<Node>(on_disk, self.children)
    }

    pub(super) fn to_in_memory_node<'on_disk>(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<dirstate_map::Node<'on_disk>, DirstateV2ParseError> {
        Ok(dirstate_map::Node {
            children: dirstate_map::ChildNodes::OnDisk(
                self.children(on_disk)?,
            ),
            copy_source: self.copy_source(on_disk)?.map(Cow::Borrowed),
            entry: self.entry()?,
            tracked_descendants_count: self.tracked_descendants_count.get(),
        })
    }
}

fn read_hg_path(
    on_disk: &[u8],
    slice: Slice,
) -> Result<&HgPath, DirstateV2ParseError> {
    let bytes = read_slice::<u8>(on_disk, slice)?;
    Ok(HgPath::new(bytes))
}

fn read_slice<T>(
    on_disk: &[u8],
    slice: Slice,
) -> Result<&[T], DirstateV2ParseError>
where
    T: BytesCast,
{
    // Either `usize::MAX` would result in "out of bounds" error since a single
    // `&[u8]` cannot occupy the entire addess space.
    let start = usize::try_from(slice.start.get()).unwrap_or(std::usize::MAX);
    let len = usize::try_from(slice.len.get()).unwrap_or(std::usize::MAX);
    on_disk
        .get(start..)
        .and_then(|bytes| T::slice_from_bytes(bytes, len).ok())
        .map(|(slice, _rest)| slice)
        .ok_or_else(|| DirstateV2ParseError)
}

pub(super) fn write(
    dirstate_map: &mut DirstateMap,
    parents: DirstateParents,
) -> Result<Vec<u8>, DirstateError> {
    let header_len = std::mem::size_of::<Header>();

    // This ignores the space for paths, and for nodes without an entry.
    // TODO: better estimate? Skip the `Vec` and write to a file directly?
    let size_guess = header_len
        + std::mem::size_of::<Node>()
            * dirstate_map.nodes_with_entry_count as usize;
    let mut out = Vec::with_capacity(size_guess);

    // Keep space for the header. We’ll fill it out at the end when we know the
    // actual offset for the root nodes.
    out.resize(header_len, 0_u8);

    let root =
        write_nodes(dirstate_map, dirstate_map.root.as_ref(), &mut out)?;

    let header = Header {
        marker: *V2_FORMAT_MARKER,
        parents: parents,
        root,
        nodes_with_entry_count: dirstate_map.nodes_with_entry_count.into(),
        nodes_with_copy_source_count: dirstate_map
            .nodes_with_copy_source_count
            .into(),
    };
    out[..header_len].copy_from_slice(header.as_bytes());
    Ok(out)
}

fn write_nodes(
    dirstate_map: &DirstateMap,
    nodes: dirstate_map::ChildNodesRef,
    out: &mut Vec<u8>,
) -> Result<ChildNodes, DirstateError> {
    // `dirstate_map::ChildNodes` is a `HashMap` with undefined iteration
    // order. Sort to enable binary search in the written file.
    let nodes = nodes.sorted();

    // First accumulate serialized nodes in a `Vec`
    let mut on_disk_nodes = Vec::with_capacity(nodes.len());
    for node in nodes {
        let children = write_nodes(
            dirstate_map,
            node.children(dirstate_map.on_disk)?,
            out,
        )?;
        let full_path = node.full_path(dirstate_map.on_disk)?;
        let full_path = write_slice::<u8>(full_path.as_bytes(), out);
        let copy_source =
            if let Some(source) = node.copy_source(dirstate_map.on_disk)? {
                write_slice::<u8>(source.as_bytes(), out)
            } else {
                Slice {
                    start: 0.into(),
                    len: 0.into(),
                }
            };
        on_disk_nodes.push(match node {
            NodeRef::InMemory(path, node) => Node {
                children,
                copy_source,
                full_path,
                base_name_start: u32::try_from(path.base_name_start())
                    // Could only panic for paths over 4 GiB
                    .expect("dirstate-v2 offset overflow")
                    .into(),
                tracked_descendants_count: node
                    .tracked_descendants_count
                    .into(),
                entry: if let Some(entry) = &node.entry {
                    OptEntry {
                        state: entry.state.into(),
                        mode: entry.mode.into(),
                        mtime: entry.mtime.into(),
                        size: entry.size.into(),
                    }
                } else {
                    OptEntry {
                        state: b'\0',
                        mode: 0.into(),
                        mtime: 0.into(),
                        size: 0.into(),
                    }
                },
            },
            NodeRef::OnDisk(node) => Node {
                children,
                copy_source,
                full_path,
                ..*node
            },
        })
    }
    // … so we can write them contiguously
    Ok(write_slice::<Node>(&on_disk_nodes, out))
}

fn write_slice<T>(slice: &[T], out: &mut Vec<u8>) -> Slice
where
    T: BytesCast,
{
    let start = u64::try_from(out.len())
        // Could only panic on a 128-bit CPU with a dirstate over 16 EiB
        .expect("dirstate-v2 offset overflow")
        .into();
    let len = u32::try_from(slice.len())
        // Could only panic for paths over 4 GiB or nodes with over 4 billions
        // child nodes
        .expect("dirstate-v2 offset overflow")
        .into();
    out.extend(slice.as_bytes());
    Slice { start, len }
}

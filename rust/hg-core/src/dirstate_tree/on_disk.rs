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
use bytes_cast::unaligned::{I32Be, I64Be, U32Be};
use bytes_cast::BytesCast;
use format_bytes::format_bytes;
use std::borrow::Cow;
use std::convert::{TryFrom, TryInto};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Added at the start of `.hg/dirstate` when the "v2" format is used.
/// This a redundant sanity check more than an actual "magic number" since
/// `.hg/requires` already governs which format should be used.
pub const V2_FORMAT_MARKER: &[u8; 12] = b"dirstate-v2\n";

/// Keep space for 256-bit hashes
const STORED_NODE_ID_BYTES: usize = 32;

/// … even though only 160 bits are used for now, with SHA-1
const USED_NODE_ID_BYTES: usize = 20;

pub(super) const IGNORE_PATTERNS_HASH_LEN: usize = 20;
pub(super) type IgnorePatternsHash = [u8; IGNORE_PATTERNS_HASH_LEN];

// Must match `HEADER` in `mercurial/dirstateutils/docket.py`
#[derive(BytesCast)]
#[repr(C)]
struct DocketHeader {
    marker: [u8; V2_FORMAT_MARKER.len()],
    parent_1: [u8; STORED_NODE_ID_BYTES],
    parent_2: [u8; STORED_NODE_ID_BYTES],
    data_size: Size,
    uuid_size: u8,
}

pub struct Docket<'on_disk> {
    header: &'on_disk DocketHeader,
    uuid: &'on_disk [u8],
}

#[derive(BytesCast)]
#[repr(C)]
struct Header {
    root: ChildNodes,
    nodes_with_entry_count: Size,
    nodes_with_copy_source_count: Size,

    /// If non-zero, a hash of ignore files that were used for some previous
    /// run of the `status` algorithm.
    ///
    /// We define:
    ///
    /// * "Root" ignore files are `.hgignore` at the root of the repository if
    ///   it exists, and files from `ui.ignore.*` config. This set of files is
    ///   then sorted by the string representation of their path.
    /// * The "expanded contents" of an ignore files is the byte string made
    ///   by concatenating its contents with the "expanded contents" of other
    ///   files included with `include:` or `subinclude:` files, in inclusion
    ///   order. This definition is recursive, as included files can
    ///   themselves include more files.
    ///
    /// This hash is defined as the SHA-1 of the concatenation (in sorted
    /// order) of the "expanded contents" of each "root" ignore file.
    /// (Note that computing this does not require actually concatenating byte
    /// strings into contiguous memory, instead SHA-1 hashing can be done
    /// incrementally.)
    ignore_patterns_hash: IgnorePatternsHash,
}

#[derive(BytesCast)]
#[repr(C)]
pub(super) struct Node {
    full_path: PathSlice,

    /// In bytes from `self.full_path.start`
    base_name_start: Size,

    copy_source: OptPathSlice,
    children: ChildNodes,
    pub(super) descendants_with_entry_count: Size,
    pub(super) tracked_descendants_count: Size,

    /// Depending on the value of `state`:
    ///
    /// * A null byte: `data` is not used.
    ///
    /// * A `n`, `a`, `r`, or `m` ASCII byte: `state` and `data` together
    ///   represent a dirstate entry like in the v1 format.
    ///
    /// * A `d` ASCII byte: the bytes of `data` should instead be interpreted
    ///   as the `Timestamp` for the mtime of a cached directory.
    ///
    ///   The presence of this state means that at some point, this path in
    ///   the working directory was observed:
    ///
    ///   - To be a directory
    ///   - With the modification time as given by `Timestamp`
    ///   - That timestamp was already strictly in the past when observed,
    ///     meaning that later changes cannot happen in the same clock tick
    ///     and must cause a different modification time (unless the system
    ///     clock jumps back and we get unlucky, which is not impossible but
    ///     but deemed unlikely enough).
    ///   - All direct children of this directory (as returned by
    ///     `std::fs::read_dir`) either have a corresponding dirstate node, or
    ///     are ignored by ignore patterns whose hash is in
    ///     `Header::ignore_patterns_hash`.
    ///
    ///   This means that if `std::fs::symlink_metadata` later reports the
    ///   same modification time and ignored patterns haven’t changed, a run
    ///   of status that is not listing ignored   files can skip calling
    ///   `std::fs::read_dir` again for this directory,   iterate child
    ///   dirstate nodes instead.
    state: u8,
    data: Entry,
}

#[derive(BytesCast, Copy, Clone)]
#[repr(C)]
struct Entry {
    mode: I32Be,
    mtime: I32Be,
    size: I32Be,
}

/// Duration since the Unix epoch
#[derive(BytesCast, Copy, Clone, PartialEq)]
#[repr(C)]
pub(super) struct Timestamp {
    seconds: I64Be,

    /// In `0 .. 1_000_000_000`.
    ///
    /// This timestamp is later or earlier than `(seconds, 0)` by this many
    /// nanoseconds, if `seconds` is non-negative or negative, respectively.
    nanoseconds: U32Be,
}

/// Counted in bytes from the start of the file
///
/// NOTE: not supporting `.hg/dirstate` files larger than 4 GiB.
type Offset = U32Be;

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
    let _ = std::mem::transmute::<DocketHeader, [u8; 81]>;
    let _ = std::mem::transmute::<Header, [u8; 36]>;
    let _ = std::mem::transmute::<Node, [u8; 49]>;
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

impl<'on_disk> Docket<'on_disk> {
    pub fn parents(&self) -> DirstateParents {
        use crate::Node;
        let p1 = Node::try_from(&self.header.parent_1[..USED_NODE_ID_BYTES])
            .unwrap()
            .clone();
        let p2 = Node::try_from(&self.header.parent_2[..USED_NODE_ID_BYTES])
            .unwrap()
            .clone();
        DirstateParents { p1, p2 }
    }

    pub fn data_size(&self) -> usize {
        // This `unwrap` could only panic on a 16-bit CPU
        self.header.data_size.get().try_into().unwrap()
    }

    pub fn data_filename(&self) -> String {
        String::from_utf8(format_bytes!(b"dirstate.{}.d", self.uuid)).unwrap()
    }
}

pub fn read_docket(
    on_disk: &[u8],
) -> Result<Docket<'_>, DirstateV2ParseError> {
    let (header, uuid) =
        DocketHeader::from_bytes(on_disk).map_err(|_| DirstateV2ParseError)?;
    let uuid_size = header.uuid_size as usize;
    if header.marker == *V2_FORMAT_MARKER && uuid.len() == uuid_size {
        Ok(Docket { header, uuid })
    } else {
        Err(DirstateV2ParseError)
    }
}

pub(super) fn read<'on_disk>(
    on_disk: &'on_disk [u8],
) -> Result<DirstateMap<'on_disk>, DirstateV2ParseError> {
    if on_disk.is_empty() {
        return Ok(DirstateMap::empty(on_disk));
    }
    let (header, _) =
        Header::from_bytes(on_disk).map_err(|_| DirstateV2ParseError)?;
    let dirstate_map = DirstateMap {
        on_disk,
        root: dirstate_map::ChildNodes::OnDisk(read_slice::<Node>(
            on_disk,
            header.root,
        )?),
        nodes_with_entry_count: header.nodes_with_entry_count.get(),
        nodes_with_copy_source_count: header
            .nodes_with_copy_source_count
            .get(),
        ignore_patterns_hash: header.ignore_patterns_hash,
    };
    Ok(dirstate_map)
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

    pub(super) fn node_data(
        &self,
    ) -> Result<dirstate_map::NodeData, DirstateV2ParseError> {
        let entry = |state| {
            dirstate_map::NodeData::Entry(self.entry_with_given_state(state))
        };

        match self.state {
            b'\0' => Ok(dirstate_map::NodeData::None),
            b'd' => Ok(dirstate_map::NodeData::CachedDirectory {
                mtime: *self.data.as_timestamp(),
            }),
            b'n' => Ok(entry(EntryState::Normal)),
            b'a' => Ok(entry(EntryState::Added)),
            b'r' => Ok(entry(EntryState::Removed)),
            b'm' => Ok(entry(EntryState::Merged)),
            _ => Err(DirstateV2ParseError),
        }
    }

    pub(super) fn cached_directory_mtime(&self) -> Option<&Timestamp> {
        if self.state == b'd' {
            Some(self.data.as_timestamp())
        } else {
            None
        }
    }

    pub(super) fn state(
        &self,
    ) -> Result<Option<EntryState>, DirstateV2ParseError> {
        match self.state {
            b'\0' | b'd' => Ok(None),
            b'n' => Ok(Some(EntryState::Normal)),
            b'a' => Ok(Some(EntryState::Added)),
            b'r' => Ok(Some(EntryState::Removed)),
            b'm' => Ok(Some(EntryState::Merged)),
            _ => Err(DirstateV2ParseError),
        }
    }

    fn entry_with_given_state(&self, state: EntryState) -> DirstateEntry {
        DirstateEntry {
            state,
            mode: self.data.mode.get(),
            mtime: self.data.mtime.get(),
            size: self.data.size.get(),
        }
    }

    pub(super) fn entry(
        &self,
    ) -> Result<Option<DirstateEntry>, DirstateV2ParseError> {
        Ok(self
            .state()?
            .map(|state| self.entry_with_given_state(state)))
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
            data: self.node_data()?,
            descendants_with_entry_count: self
                .descendants_with_entry_count
                .get(),
            tracked_descendants_count: self.tracked_descendants_count.get(),
        })
    }
}

impl Entry {
    fn from_timestamp(timestamp: Timestamp) -> Self {
        // Safety: both types implement the `ByteCast` trait, so we could
        // safely use `as_bytes` and `from_bytes` to do this conversion. Using
        // `transmute` instead makes the compiler check that the two types
        // have the same size, which eliminates the error case of
        // `from_bytes`.
        unsafe { std::mem::transmute::<Timestamp, Entry>(timestamp) }
    }

    fn as_timestamp(&self) -> &Timestamp {
        // Safety: same as above in `from_timestamp`
        unsafe { &*(self as *const Entry as *const Timestamp) }
    }
}

impl Timestamp {
    pub fn seconds(&self) -> i64 {
        self.seconds.get()
    }
}

impl From<SystemTime> for Timestamp {
    fn from(system_time: SystemTime) -> Self {
        let (secs, nanos) = match system_time.duration_since(UNIX_EPOCH) {
            Ok(duration) => {
                (duration.as_secs() as i64, duration.subsec_nanos())
            }
            Err(error) => {
                let negative = error.duration();
                (-(negative.as_secs() as i64), negative.subsec_nanos())
            }
        };
        Timestamp {
            seconds: secs.into(),
            nanoseconds: nanos.into(),
        }
    }
}

impl From<&'_ Timestamp> for SystemTime {
    fn from(timestamp: &'_ Timestamp) -> Self {
        let secs = timestamp.seconds.get();
        let nanos = timestamp.nanoseconds.get();
        if secs >= 0 {
            UNIX_EPOCH + Duration::new(secs as u64, nanos)
        } else {
            UNIX_EPOCH - Duration::new((-secs) as u64, nanos)
        }
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

pub(crate) fn for_each_tracked_path<'on_disk>(
    on_disk: &'on_disk [u8],
    mut f: impl FnMut(&'on_disk HgPath),
) -> Result<(), DirstateV2ParseError> {
    let (header, _) =
        Header::from_bytes(on_disk).map_err(|_| DirstateV2ParseError)?;
    fn recur<'on_disk>(
        on_disk: &'on_disk [u8],
        nodes: Slice,
        f: &mut impl FnMut(&'on_disk HgPath),
    ) -> Result<(), DirstateV2ParseError> {
        for node in read_slice::<Node>(on_disk, nodes)? {
            if let Some(state) = node.state()? {
                if state.is_tracked() {
                    f(node.full_path(on_disk)?)
                }
            }
            recur(on_disk, node.children, f)?
        }
        Ok(())
    }
    recur(on_disk, header.root, &mut f)
}

pub(super) fn write(
    dirstate_map: &mut DirstateMap,
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
        root,
        nodes_with_entry_count: dirstate_map.nodes_with_entry_count.into(),
        nodes_with_copy_source_count: dirstate_map
            .nodes_with_copy_source_count
            .into(),
        ignore_patterns_hash: dirstate_map.ignore_patterns_hash,
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
            NodeRef::InMemory(path, node) => {
                let (state, data) = match &node.data {
                    dirstate_map::NodeData::Entry(entry) => (
                        entry.state.into(),
                        Entry {
                            mode: entry.mode.into(),
                            mtime: entry.mtime.into(),
                            size: entry.size.into(),
                        },
                    ),
                    dirstate_map::NodeData::CachedDirectory { mtime } => {
                        (b'd', Entry::from_timestamp(*mtime))
                    }
                    dirstate_map::NodeData::None => (
                        b'\0',
                        Entry {
                            mode: 0.into(),
                            mtime: 0.into(),
                            size: 0.into(),
                        },
                    ),
                };
                Node {
                    children,
                    copy_source,
                    full_path,
                    base_name_start: u32::try_from(path.base_name_start())
                        // Could only panic for paths over 4 GiB
                        .expect("dirstate-v2 offset overflow")
                        .into(),
                    descendants_with_entry_count: node
                        .descendants_with_entry_count
                        .into(),
                    tracked_descendants_count: node
                        .tracked_descendants_count
                        .into(),
                    state,
                    data,
                }
            }
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
    let start = u32::try_from(out.len())
        // Could only panic for a dirstate file larger than 4 GiB
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

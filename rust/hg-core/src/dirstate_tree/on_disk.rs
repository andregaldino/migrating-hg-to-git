//! The "version 2" disk representation of the dirstate
//!
//! See `mercurial/helptext/internals/dirstate-v2.txt`

use crate::dirstate::TruncatedTimestamp;
use crate::dirstate_tree::dirstate_map::{self, DirstateMap, NodeRef};
use crate::dirstate_tree::path_with_basename::WithBasename;
use crate::errors::HgError;
use crate::utils::hg_path::HgPath;
use crate::DirstateEntry;
use crate::DirstateError;
use crate::DirstateParents;
use bitflags::bitflags;
use bytes_cast::unaligned::{U16Be, U32Be};
use bytes_cast::BytesCast;
use format_bytes::format_bytes;
use rand::Rng;
use std::borrow::Cow;
use std::convert::{TryFrom, TryInto};
use std::fmt::Write;

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

/// Must match constants of the same names in `mercurial/dirstateutils/v2.py`
const TREE_METADATA_SIZE: usize = 44;
const NODE_SIZE: usize = 44;

/// Make sure that size-affecting changes are made knowingly
#[allow(unused)]
fn static_assert_size_of() {
    let _ = std::mem::transmute::<TreeMetadata, [u8; TREE_METADATA_SIZE]>;
    let _ = std::mem::transmute::<DocketHeader, [u8; TREE_METADATA_SIZE + 81]>;
    let _ = std::mem::transmute::<Node, [u8; NODE_SIZE]>;
}

// Must match `HEADER` in `mercurial/dirstateutils/docket.py`
#[derive(BytesCast)]
#[repr(C)]
struct DocketHeader {
    marker: [u8; V2_FORMAT_MARKER.len()],
    parent_1: [u8; STORED_NODE_ID_BYTES],
    parent_2: [u8; STORED_NODE_ID_BYTES],

    metadata: TreeMetadata,

    /// Counted in bytes
    data_size: Size,

    uuid_size: u8,
}

pub struct Docket<'on_disk> {
    header: &'on_disk DocketHeader,
    pub uuid: &'on_disk [u8],
}

/// Fields are documented in the *Tree metadata in the docket file*
/// section of `mercurial/helptext/internals/dirstate-v2.txt`
#[derive(BytesCast)]
#[repr(C)]
pub struct TreeMetadata {
    root_nodes: ChildNodes,
    nodes_with_entry_count: Size,
    nodes_with_copy_source_count: Size,
    unreachable_bytes: Size,
    unused: [u8; 4],

    /// See *Optional hash of ignore patterns* section of
    /// `mercurial/helptext/internals/dirstate-v2.txt`
    ignore_patterns_hash: IgnorePatternsHash,
}

/// Fields are documented in the *The data file format*
/// section of `mercurial/helptext/internals/dirstate-v2.txt`
#[derive(BytesCast)]
#[repr(C)]
pub(super) struct Node {
    full_path: PathSlice,

    /// In bytes from `self.full_path.start`
    base_name_start: PathSize,

    copy_source: OptPathSlice,
    children: ChildNodes,
    pub(super) descendants_with_entry_count: Size,
    pub(super) tracked_descendants_count: Size,
    flags: U16Be,
    size: U32Be,
    mtime: PackedTruncatedTimestamp,
}

bitflags! {
    #[repr(C)]
    struct Flags: u16 {
        const WDIR_TRACKED = 1 << 0;
        const P1_TRACKED = 1 << 1;
        const P2_INFO = 1 << 2;
        const MODE_EXEC_PERM = 1 << 3;
        const MODE_IS_SYMLINK = 1 << 4;
        const HAS_FALLBACK_EXEC = 1 <<  5;
        const FALLBACK_EXEC = 1 <<  6;
        const HAS_FALLBACK_SYMLINK = 1 <<  7;
        const FALLBACK_SYMLINK = 1 <<  8;
        const EXPECTED_STATE_IS_MODIFIED = 1 << 9;
        const HAS_MODE_AND_SIZE = 1 <<10;
        const HAS_MTIME = 1 <<11;
        const MTIME_SECOND_AMBIGUOUS = 1 << 12;
        const DIRECTORY = 1 <<13;
        const ALL_UNKNOWN_RECORDED = 1 <<14;
        const ALL_IGNORED_RECORDED = 1 <<15;
    }
}

/// Duration since the Unix epoch
#[derive(BytesCast, Copy, Clone)]
#[repr(C)]
struct PackedTruncatedTimestamp {
    truncated_seconds: U32Be,
    nanoseconds: U32Be,
}

/// Counted in bytes from the start of the file
///
/// NOTE: not supporting `.hg/dirstate` files larger than 4 GiB.
type Offset = U32Be;

/// Counted in number of items
///
/// NOTE: we choose not to support counting more than 4 billion nodes anywhere.
type Size = U32Be;

/// Counted in bytes
///
/// NOTE: we choose not to support file names/paths longer than 64 KiB.
type PathSize = U16Be;

/// A contiguous sequence of `len` times `Node`, representing the child nodes
/// of either some other node or of the repository root.
///
/// Always sorted by ascending `full_path`, to allow binary search.
/// Since nodes with the same parent nodes also have the same parent path,
/// only the `base_name`s need to be compared during binary search.
#[derive(BytesCast, Copy, Clone)]
#[repr(C)]
struct ChildNodes {
    start: Offset,
    len: Size,
}

/// A `HgPath` of `len` bytes
#[derive(BytesCast, Copy, Clone)]
#[repr(C)]
struct PathSlice {
    start: Offset,
    len: PathSize,
}

/// Either nothing if `start == 0`, or a `HgPath` of `len` bytes
type OptPathSlice = PathSlice;

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

impl TreeMetadata {
    pub fn as_bytes(&self) -> &[u8] {
        BytesCast::as_bytes(self)
    }
}

impl<'on_disk> Docket<'on_disk> {
    /// Generate the identifier for a new data file
    ///
    /// TODO: support the `HGTEST_UUIDFILE` environment variable.
    /// See `mercurial/revlogutils/docket.py`
    pub fn new_uid() -> String {
        const ID_LENGTH: usize = 8;
        let mut id = String::with_capacity(ID_LENGTH);
        let mut rng = rand::thread_rng();
        for _ in 0..ID_LENGTH {
            // One random hexadecimal digit.
            // `unwrap` never panics because `impl Write for String`
            // never returns an error.
            write!(&mut id, "{:x}", rng.gen_range(0, 16)).unwrap();
        }
        id
    }

    pub fn serialize(
        parents: DirstateParents,
        tree_metadata: TreeMetadata,
        data_size: u64,
        uuid: &[u8],
    ) -> Result<Vec<u8>, std::num::TryFromIntError> {
        let header = DocketHeader {
            marker: *V2_FORMAT_MARKER,
            parent_1: parents.p1.pad_to_256_bits(),
            parent_2: parents.p2.pad_to_256_bits(),
            metadata: tree_metadata,
            data_size: u32::try_from(data_size)?.into(),
            uuid_size: uuid.len().try_into()?,
        };
        let header = header.as_bytes();
        let mut docket = Vec::with_capacity(header.len() + uuid.len());
        docket.extend_from_slice(header);
        docket.extend_from_slice(uuid);
        Ok(docket)
    }

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

    pub fn tree_metadata(&self) -> &[u8] {
        self.header.metadata.as_bytes()
    }

    pub fn data_size(&self) -> usize {
        // This `unwrap` could only panic on a 16-bit CPU
        self.header.data_size.get().try_into().unwrap()
    }

    pub fn data_filename(&self) -> String {
        String::from_utf8(format_bytes!(b"dirstate.{}", self.uuid)).unwrap()
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
    metadata: &[u8],
) -> Result<DirstateMap<'on_disk>, DirstateV2ParseError> {
    if on_disk.is_empty() {
        return Ok(DirstateMap::empty(on_disk));
    }
    let (meta, _) = TreeMetadata::from_bytes(metadata)
        .map_err(|_| DirstateV2ParseError)?;
    let dirstate_map = DirstateMap {
        on_disk,
        root: dirstate_map::ChildNodes::OnDisk(read_nodes(
            on_disk,
            meta.root_nodes,
        )?),
        nodes_with_entry_count: meta.nodes_with_entry_count.get(),
        nodes_with_copy_source_count: meta.nodes_with_copy_source_count.get(),
        ignore_patterns_hash: meta.ignore_patterns_hash,
        unreachable_bytes: meta.unreachable_bytes.get(),
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

    fn flags(&self) -> Flags {
        Flags::from_bits_truncate(self.flags.get())
    }

    fn has_entry(&self) -> bool {
        self.flags().intersects(
            Flags::WDIR_TRACKED | Flags::P1_TRACKED | Flags::P2_INFO,
        )
    }

    pub(super) fn node_data(
        &self,
    ) -> Result<dirstate_map::NodeData, DirstateV2ParseError> {
        if self.has_entry() {
            Ok(dirstate_map::NodeData::Entry(self.assume_entry()?))
        } else if let Some(mtime) = self.cached_directory_mtime()? {
            Ok(dirstate_map::NodeData::CachedDirectory { mtime })
        } else {
            Ok(dirstate_map::NodeData::None)
        }
    }

    pub(super) fn cached_directory_mtime(
        &self,
    ) -> Result<Option<TruncatedTimestamp>, DirstateV2ParseError> {
        // For now we do not have code to handle the absence of
        // ALL_UNKNOWN_RECORDED, so we ignore the mtime if the flag is
        // unset.
        if self.flags().contains(Flags::DIRECTORY)
            && self.flags().contains(Flags::HAS_MTIME)
            && self.flags().contains(Flags::ALL_UNKNOWN_RECORDED)
        {
            Ok(Some(self.mtime()?))
        } else {
            Ok(None)
        }
    }

    fn synthesize_unix_mode(&self) -> u32 {
        let file_type = if self.flags().contains(Flags::MODE_IS_SYMLINK) {
            libc::S_IFLNK
        } else {
            libc::S_IFREG
        };
        let permisions = if self.flags().contains(Flags::MODE_EXEC_PERM) {
            0o755
        } else {
            0o644
        };
        file_type | permisions
    }

    fn mtime(&self) -> Result<TruncatedTimestamp, DirstateV2ParseError> {
        let mut m: TruncatedTimestamp = self.mtime.try_into()?;
        if self.flags().contains(Flags::MTIME_SECOND_AMBIGUOUS) {
            m.second_ambiguous = true;
        }
        Ok(m)
    }

    fn assume_entry(&self) -> Result<DirstateEntry, DirstateV2ParseError> {
        // TODO: convert through raw bits instead?
        let wdir_tracked = self.flags().contains(Flags::WDIR_TRACKED);
        let p1_tracked = self.flags().contains(Flags::P1_TRACKED);
        let p2_info = self.flags().contains(Flags::P2_INFO);
        let mode_size = if self.flags().contains(Flags::HAS_MODE_AND_SIZE)
            && !self.flags().contains(Flags::EXPECTED_STATE_IS_MODIFIED)
        {
            Some((self.synthesize_unix_mode(), self.size.into()))
        } else {
            None
        };
        let mtime = if self.flags().contains(Flags::HAS_MTIME)
            && !self.flags().contains(Flags::DIRECTORY)
            && !self.flags().contains(Flags::EXPECTED_STATE_IS_MODIFIED)
        {
            Some(self.mtime()?)
        } else {
            None
        };
        let fallback_exec = if self.flags().contains(Flags::HAS_FALLBACK_EXEC)
        {
            Some(self.flags().contains(Flags::FALLBACK_EXEC))
        } else {
            None
        };
        let fallback_symlink =
            if self.flags().contains(Flags::HAS_FALLBACK_SYMLINK) {
                Some(self.flags().contains(Flags::FALLBACK_SYMLINK))
            } else {
                None
            };
        Ok(DirstateEntry::from_v2_data(
            wdir_tracked,
            p1_tracked,
            p2_info,
            mode_size,
            mtime,
            fallback_exec,
            fallback_symlink,
        ))
    }

    pub(super) fn entry(
        &self,
    ) -> Result<Option<DirstateEntry>, DirstateV2ParseError> {
        if self.has_entry() {
            Ok(Some(self.assume_entry()?))
        } else {
            Ok(None)
        }
    }

    pub(super) fn children<'on_disk>(
        &self,
        on_disk: &'on_disk [u8],
    ) -> Result<&'on_disk [Node], DirstateV2ParseError> {
        read_nodes(on_disk, self.children)
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

    fn from_dirstate_entry(
        entry: &DirstateEntry,
    ) -> (Flags, U32Be, PackedTruncatedTimestamp) {
        let (
            wdir_tracked,
            p1_tracked,
            p2_info,
            mode_size_opt,
            mtime_opt,
            fallback_exec,
            fallback_symlink,
        ) = entry.v2_data();
        // TODO: convert throug raw flag bits instead?
        let mut flags = Flags::empty();
        flags.set(Flags::WDIR_TRACKED, wdir_tracked);
        flags.set(Flags::P1_TRACKED, p1_tracked);
        flags.set(Flags::P2_INFO, p2_info);
        let size = if let Some((m, s)) = mode_size_opt {
            let exec_perm = m & libc::S_IXUSR != 0;
            let is_symlink = m & libc::S_IFMT == libc::S_IFLNK;
            flags.set(Flags::MODE_EXEC_PERM, exec_perm);
            flags.set(Flags::MODE_IS_SYMLINK, is_symlink);
            flags.insert(Flags::HAS_MODE_AND_SIZE);
            s.into()
        } else {
            0.into()
        };
        let mtime = if let Some(m) = mtime_opt {
            flags.insert(Flags::HAS_MTIME);
            if m.second_ambiguous {
                flags.insert(Flags::MTIME_SECOND_AMBIGUOUS);
            };
            m.into()
        } else {
            PackedTruncatedTimestamp::null()
        };
        if let Some(f_exec) = fallback_exec {
            flags.insert(Flags::HAS_FALLBACK_EXEC);
            if f_exec {
                flags.insert(Flags::FALLBACK_EXEC);
            }
        }
        if let Some(f_symlink) = fallback_symlink {
            flags.insert(Flags::HAS_FALLBACK_SYMLINK);
            if f_symlink {
                flags.insert(Flags::FALLBACK_SYMLINK);
            }
        }
        (flags, size, mtime)
    }
}

fn read_hg_path(
    on_disk: &[u8],
    slice: PathSlice,
) -> Result<&HgPath, DirstateV2ParseError> {
    read_slice(on_disk, slice.start, slice.len.get()).map(HgPath::new)
}

fn read_nodes(
    on_disk: &[u8],
    slice: ChildNodes,
) -> Result<&[Node], DirstateV2ParseError> {
    read_slice(on_disk, slice.start, slice.len.get())
}

fn read_slice<T, Len>(
    on_disk: &[u8],
    start: Offset,
    len: Len,
) -> Result<&[T], DirstateV2ParseError>
where
    T: BytesCast,
    Len: TryInto<usize>,
{
    // Either `usize::MAX` would result in "out of bounds" error since a single
    // `&[u8]` cannot occupy the entire addess space.
    let start = start.get().try_into().unwrap_or(std::usize::MAX);
    let len = len.try_into().unwrap_or(std::usize::MAX);
    on_disk
        .get(start..)
        .and_then(|bytes| T::slice_from_bytes(bytes, len).ok())
        .map(|(slice, _rest)| slice)
        .ok_or_else(|| DirstateV2ParseError)
}

pub(crate) fn for_each_tracked_path<'on_disk>(
    on_disk: &'on_disk [u8],
    metadata: &[u8],
    mut f: impl FnMut(&'on_disk HgPath),
) -> Result<(), DirstateV2ParseError> {
    let (meta, _) = TreeMetadata::from_bytes(metadata)
        .map_err(|_| DirstateV2ParseError)?;
    fn recur<'on_disk>(
        on_disk: &'on_disk [u8],
        nodes: ChildNodes,
        f: &mut impl FnMut(&'on_disk HgPath),
    ) -> Result<(), DirstateV2ParseError> {
        for node in read_nodes(on_disk, nodes)? {
            if let Some(entry) = node.entry()? {
                if entry.state().is_tracked() {
                    f(node.full_path(on_disk)?)
                }
            }
            recur(on_disk, node.children, f)?
        }
        Ok(())
    }
    recur(on_disk, meta.root_nodes, &mut f)
}

/// Returns new data and metadata, together with whether that data should be
/// appended to the existing data file whose content is at
/// `dirstate_map.on_disk` (true), instead of written to a new data file
/// (false).
pub(super) fn write(
    dirstate_map: &DirstateMap,
    can_append: bool,
) -> Result<(Vec<u8>, TreeMetadata, bool), DirstateError> {
    let append = can_append && dirstate_map.write_should_append();

    // This ignores the space for paths, and for nodes without an entry.
    // TODO: better estimate? Skip the `Vec` and write to a file directly?
    let size_guess = std::mem::size_of::<Node>()
        * dirstate_map.nodes_with_entry_count as usize;

    let mut writer = Writer {
        dirstate_map,
        append,
        out: Vec::with_capacity(size_guess),
    };

    let root_nodes = writer.write_nodes(dirstate_map.root.as_ref())?;

    let meta = TreeMetadata {
        root_nodes,
        nodes_with_entry_count: dirstate_map.nodes_with_entry_count.into(),
        nodes_with_copy_source_count: dirstate_map
            .nodes_with_copy_source_count
            .into(),
        unreachable_bytes: dirstate_map.unreachable_bytes.into(),
        unused: [0; 4],
        ignore_patterns_hash: dirstate_map.ignore_patterns_hash,
    };
    Ok((writer.out, meta, append))
}

struct Writer<'dmap, 'on_disk> {
    dirstate_map: &'dmap DirstateMap<'on_disk>,
    append: bool,
    out: Vec<u8>,
}

impl Writer<'_, '_> {
    fn write_nodes(
        &mut self,
        nodes: dirstate_map::ChildNodesRef,
    ) -> Result<ChildNodes, DirstateError> {
        // Reuse already-written nodes if possible
        if self.append {
            if let dirstate_map::ChildNodesRef::OnDisk(nodes_slice) = nodes {
                let start = self.on_disk_offset_of(nodes_slice).expect(
                    "dirstate-v2 OnDisk nodes not found within on_disk",
                );
                let len = child_nodes_len_from_usize(nodes_slice.len());
                return Ok(ChildNodes { start, len });
            }
        }

        // `dirstate_map::ChildNodes::InMemory` contains a `HashMap` which has
        // undefined iteration order. Sort to enable binary search in the
        // written file.
        let nodes = nodes.sorted();
        let nodes_len = nodes.len();

        // First accumulate serialized nodes in a `Vec`
        let mut on_disk_nodes = Vec::with_capacity(nodes_len);
        for node in nodes {
            let children =
                self.write_nodes(node.children(self.dirstate_map.on_disk)?)?;
            let full_path = node.full_path(self.dirstate_map.on_disk)?;
            let full_path = self.write_path(full_path.as_bytes());
            let copy_source = if let Some(source) =
                node.copy_source(self.dirstate_map.on_disk)?
            {
                self.write_path(source.as_bytes())
            } else {
                PathSlice {
                    start: 0.into(),
                    len: 0.into(),
                }
            };
            on_disk_nodes.push(match node {
                NodeRef::InMemory(path, node) => {
                    let (flags, size, mtime) = match &node.data {
                        dirstate_map::NodeData::Entry(entry) => {
                            Node::from_dirstate_entry(entry)
                        }
                        dirstate_map::NodeData::CachedDirectory { mtime } => {
                            // we currently never set a mtime if unknown file
                            // are present.
                            // So if we have a mtime for a directory, we know
                            // they are no unknown
                            // files and we
                            // blindly set ALL_UNKNOWN_RECORDED.
                            //
                            // We never set ALL_IGNORED_RECORDED since we
                            // don't track that case
                            // currently.
                            let mut flags = Flags::DIRECTORY
                                | Flags::HAS_MTIME
                                | Flags::ALL_UNKNOWN_RECORDED;
                            if mtime.second_ambiguous {
                                flags.insert(Flags::MTIME_SECOND_AMBIGUOUS)
                            }
                            (flags, 0.into(), (*mtime).into())
                        }
                        dirstate_map::NodeData::None => (
                            Flags::DIRECTORY,
                            0.into(),
                            PackedTruncatedTimestamp::null(),
                        ),
                    };
                    Node {
                        children,
                        copy_source,
                        full_path,
                        base_name_start: u16::try_from(path.base_name_start())
                            // Could only panic for paths over 64 KiB
                            .expect("dirstate-v2 path length overflow")
                            .into(),
                        descendants_with_entry_count: node
                            .descendants_with_entry_count
                            .into(),
                        tracked_descendants_count: node
                            .tracked_descendants_count
                            .into(),
                        flags: flags.bits().into(),
                        size,
                        mtime,
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
        // … so we can write them contiguously, after writing everything else
        // they refer to.
        let start = self.current_offset();
        let len = child_nodes_len_from_usize(nodes_len);
        self.out.extend(on_disk_nodes.as_bytes());
        Ok(ChildNodes { start, len })
    }

    /// If the given slice of items is within `on_disk`, returns its offset
    /// from the start of `on_disk`.
    fn on_disk_offset_of<T>(&self, slice: &[T]) -> Option<Offset>
    where
        T: BytesCast,
    {
        fn address_range(slice: &[u8]) -> std::ops::RangeInclusive<usize> {
            let start = slice.as_ptr() as usize;
            let end = start + slice.len();
            start..=end
        }
        let slice_addresses = address_range(slice.as_bytes());
        let on_disk_addresses = address_range(self.dirstate_map.on_disk);
        if on_disk_addresses.contains(slice_addresses.start())
            && on_disk_addresses.contains(slice_addresses.end())
        {
            let offset = slice_addresses.start() - on_disk_addresses.start();
            Some(offset_from_usize(offset))
        } else {
            None
        }
    }

    fn current_offset(&mut self) -> Offset {
        let mut offset = self.out.len();
        if self.append {
            offset += self.dirstate_map.on_disk.len()
        }
        offset_from_usize(offset)
    }

    fn write_path(&mut self, slice: &[u8]) -> PathSlice {
        let len = path_len_from_usize(slice.len());
        // Reuse an already-written path if possible
        if self.append {
            if let Some(start) = self.on_disk_offset_of(slice) {
                return PathSlice { start, len };
            }
        }
        let start = self.current_offset();
        self.out.extend(slice.as_bytes());
        PathSlice { start, len }
    }
}

fn offset_from_usize(x: usize) -> Offset {
    u32::try_from(x)
        // Could only panic for a dirstate file larger than 4 GiB
        .expect("dirstate-v2 offset overflow")
        .into()
}

fn child_nodes_len_from_usize(x: usize) -> Size {
    u32::try_from(x)
        // Could only panic with over 4 billion nodes
        .expect("dirstate-v2 slice length overflow")
        .into()
}

fn path_len_from_usize(x: usize) -> PathSize {
    u16::try_from(x)
        // Could only panic for paths over 64 KiB
        .expect("dirstate-v2 path length overflow")
        .into()
}

impl From<TruncatedTimestamp> for PackedTruncatedTimestamp {
    fn from(timestamp: TruncatedTimestamp) -> Self {
        Self {
            truncated_seconds: timestamp.truncated_seconds().into(),
            nanoseconds: timestamp.nanoseconds().into(),
        }
    }
}

impl TryFrom<PackedTruncatedTimestamp> for TruncatedTimestamp {
    type Error = DirstateV2ParseError;

    fn try_from(
        timestamp: PackedTruncatedTimestamp,
    ) -> Result<Self, Self::Error> {
        Self::from_already_truncated(
            timestamp.truncated_seconds.get(),
            timestamp.nanoseconds.get(),
            false,
        )
    }
}
impl PackedTruncatedTimestamp {
    fn null() -> Self {
        Self {
            truncated_seconds: 0.into(),
            nanoseconds: 0.into(),
        }
    }
}

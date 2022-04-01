use crate::errors::{HgError, HgResultExt};
use bytes_cast::{unaligned, BytesCast};
use memmap2::Mmap;
use std::path::{Path, PathBuf};

use crate::utils::strip_suffix;
use crate::vfs::Vfs;

const ONDISK_VERSION: u8 = 1;

pub(super) struct NodeMapDocket {
    pub data_length: usize,
    // TODO: keep here more of the data from `parse()` when we need it
}

#[derive(BytesCast)]
#[repr(C)]
struct DocketHeader {
    uid_size: u8,
    _tip_rev: unaligned::U64Be,
    data_length: unaligned::U64Be,
    _data_unused: unaligned::U64Be,
    tip_node_size: unaligned::U64Be,
}

impl NodeMapDocket {
    /// Return `Ok(None)` when the caller should proceed without a persistent
    /// nodemap:
    ///
    /// * This revlog does not have a `.n` docket file (it is not generated for
    ///   small revlogs), or
    /// * The docket has an unsupported version number (repositories created by
    ///   later hg, maybe that should be a requirement instead?), or
    /// * The docket file points to a missing (likely deleted) data file (this
    ///   can happen in a rare race condition).
    pub fn read_from_file(
        store_vfs: &Vfs,
        index_path: &Path,
    ) -> Result<Option<(Self, Mmap)>, HgError> {
        let docket_path = index_path.with_extension("n");
        let docket_bytes = if let Some(bytes) =
            store_vfs.read(&docket_path).io_not_found_as_none()?
        {
            bytes
        } else {
            return Ok(None);
        };

        let input = if let Some((&ONDISK_VERSION, rest)) =
            docket_bytes.split_first()
        {
            rest
        } else {
            return Ok(None);
        };

        /// Treat any error as a parse error
        fn parse<T, E>(result: Result<T, E>) -> Result<T, HgError> {
            result
                .map_err(|_| HgError::corrupted("nodemap docket parse error"))
        }

        let (header, rest) = parse(DocketHeader::from_bytes(input))?;
        let uid_size = header.uid_size as usize;
        // TODO: do we care about overflow for 4 GB+ nodemap files on 32-bit
        // systems?
        let tip_node_size = header.tip_node_size.get() as usize;
        let data_length = header.data_length.get() as usize;
        let (uid, rest) = parse(u8::slice_from_bytes(rest, uid_size))?;
        let (_tip_node, _rest) =
            parse(u8::slice_from_bytes(rest, tip_node_size))?;
        let uid = parse(std::str::from_utf8(uid))?;
        let docket = NodeMapDocket { data_length };

        let data_path = rawdata_path(&docket_path, uid);
        // TODO: use `vfs.read()` here when the `persistent-nodemap.mmap`
        // config is false?
        if let Some(mmap) =
            store_vfs.mmap_open(&data_path).io_not_found_as_none()?
        {
            if mmap.len() >= data_length {
                Ok(Some((docket, mmap)))
            } else {
                Err(HgError::corrupted("persistent nodemap too short"))
            }
        } else {
            // Even if .hg/requires opted in, some revlogs are deemed small
            // enough to not need a persistent nodemap.
            Ok(None)
        }
    }
}

fn rawdata_path(docket_path: &Path, uid: &str) -> PathBuf {
    let docket_name = docket_path
        .file_name()
        .expect("expected a base name")
        .to_str()
        .expect("expected an ASCII file name in the store");
    let prefix = strip_suffix(docket_name, ".n.a")
        .or_else(|| strip_suffix(docket_name, ".n"))
        .expect("expected docket path in .n or .n.a");
    let name = format!("{}-{}.nd", prefix, uid);
    docket_path
        .parent()
        .expect("expected a non-root path")
        .join(name)
}

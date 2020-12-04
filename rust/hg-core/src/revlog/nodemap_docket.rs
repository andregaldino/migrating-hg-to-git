use memmap::Mmap;
use std::convert::TryInto;
use std::path::{Path, PathBuf};

use super::revlog::{mmap_open, RevlogError};
use crate::utils::strip_suffix;

const ONDISK_VERSION: u8 = 1;

pub(super) struct NodeMapDocket {
    pub data_length: usize,
    // TODO: keep here more of the data from `parse()` when we need it
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
        index_path: &Path,
    ) -> Result<Option<(Self, Mmap)>, RevlogError> {
        let docket_path = index_path.with_extension("n");
        let docket_bytes = match std::fs::read(&docket_path) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                return Ok(None)
            }
            Err(e) => return Err(RevlogError::IoError(e)),
            Ok(bytes) => bytes,
        };

        let mut input = if let Some((&ONDISK_VERSION, rest)) =
            docket_bytes.split_first()
        {
            rest
        } else {
            return Ok(None);
        };
        let input = &mut input;

        let uid_size = read_u8(input)? as usize;
        let _tip_rev = read_be_u64(input)?;
        // TODO: do we care about overflow for 4 GB+ nodemap files on 32-bit
        // systems?
        let data_length = read_be_u64(input)? as usize;
        let _data_unused = read_be_u64(input)?;
        let tip_node_size = read_be_u64(input)? as usize;
        let uid = read_bytes(input, uid_size)?;
        let _tip_node = read_bytes(input, tip_node_size)?;

        let uid =
            std::str::from_utf8(uid).map_err(|_| RevlogError::Corrupted)?;
        let docket = NodeMapDocket { data_length };

        let data_path = rawdata_path(&docket_path, uid);
        // TODO: use `std::fs::read` here when the `persistent-nodemap.mmap`
        // config is false?
        match mmap_open(&data_path) {
            Ok(mmap) => {
                if mmap.len() >= data_length {
                    Ok(Some((docket, mmap)))
                } else {
                    Err(RevlogError::Corrupted)
                }
            }
            Err(error) => {
                if error.kind() == std::io::ErrorKind::NotFound {
                    Ok(None)
                } else {
                    Err(RevlogError::IoError(error))
                }
            }
        }
    }
}

fn read_bytes<'a>(
    input: &mut &'a [u8],
    count: usize,
) -> Result<&'a [u8], RevlogError> {
    if let Some(start) = input.get(..count) {
        *input = &input[count..];
        Ok(start)
    } else {
        Err(RevlogError::Corrupted)
    }
}

fn read_u8<'a>(input: &mut &[u8]) -> Result<u8, RevlogError> {
    Ok(read_bytes(input, 1)?[0])
}

fn read_be_u64<'a>(input: &mut &[u8]) -> Result<u64, RevlogError> {
    let array = read_bytes(input, std::mem::size_of::<u64>())?
        .try_into()
        .unwrap();
    Ok(u64::from_be_bytes(array))
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

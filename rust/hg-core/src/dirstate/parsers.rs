// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::errors::HgError;
use crate::utils::hg_path::HgPath;
use crate::{dirstate::EntryState, DirstateEntry, DirstateParents};
use byteorder::{BigEndian, WriteBytesExt};
use bytes_cast::{unaligned, BytesCast};
use micro_timer::timed;
use std::convert::TryFrom;

/// Parents are stored in the dirstate as byte hashes.
pub const PARENT_SIZE: usize = 20;
/// Dirstate entries have a static part of 8 + 32 + 32 + 32 + 32 bits.
const MIN_ENTRY_SIZE: usize = 17;

type ParseResult<'a> = (
    &'a DirstateParents,
    Vec<(&'a HgPath, DirstateEntry)>,
    Vec<(&'a HgPath, &'a HgPath)>,
);

pub fn parse_dirstate_parents(
    contents: &[u8],
) -> Result<&DirstateParents, HgError> {
    let (parents, _rest) = DirstateParents::from_bytes(contents)
        .map_err(|_| HgError::corrupted("Too little data for dirstate."))?;
    Ok(parents)
}

#[timed]
pub fn parse_dirstate(contents: &[u8]) -> Result<ParseResult, HgError> {
    let mut copies = Vec::new();
    let mut entries = Vec::new();
    let parents =
        parse_dirstate_entries(contents, |path, entry, copy_source| {
            if let Some(source) = copy_source {
                copies.push((path, source));
            }
            entries.push((path, *entry));
            Ok(())
        })?;
    Ok((parents, entries, copies))
}

#[derive(BytesCast)]
#[repr(C)]
struct RawEntry {
    state: u8,
    mode: unaligned::I32Be,
    size: unaligned::I32Be,
    mtime: unaligned::I32Be,
    length: unaligned::I32Be,
}

pub fn parse_dirstate_entries<'a>(
    mut contents: &'a [u8],
    mut each_entry: impl FnMut(
        &'a HgPath,
        &DirstateEntry,
        Option<&'a HgPath>,
    ) -> Result<(), HgError>,
) -> Result<&'a DirstateParents, HgError> {
    let (parents, rest) = DirstateParents::from_bytes(contents)
        .map_err(|_| HgError::corrupted("Too little data for dirstate."))?;
    contents = rest;
    while !contents.is_empty() {
        let (raw_entry, rest) = RawEntry::from_bytes(contents)
            .map_err(|_| HgError::corrupted("Overflow in dirstate."))?;

        let entry = DirstateEntry::from_v1_data(
            EntryState::try_from(raw_entry.state)?,
            raw_entry.mode.get(),
            raw_entry.size.get(),
            raw_entry.mtime.get(),
        );
        let (paths, rest) =
            u8::slice_from_bytes(rest, raw_entry.length.get() as usize)
                .map_err(|_| HgError::corrupted("Overflow in dirstate."))?;

        // `paths` is either a single path, or two paths separated by a NULL
        // byte
        let mut iter = paths.splitn(2, |&byte| byte == b'\0');
        let path = HgPath::new(
            iter.next().expect("splitn always yields at least one item"),
        );
        let copy_source = iter.next().map(HgPath::new);
        each_entry(path, &entry, copy_source)?;

        contents = rest;
    }
    Ok(parents)
}

fn packed_filename_and_copy_source_size(
    filename: &HgPath,
    copy_source: Option<&HgPath>,
) -> usize {
    filename.len()
        + if let Some(source) = copy_source {
            b"\0".len() + source.len()
        } else {
            0
        }
}

pub fn packed_entry_size(
    filename: &HgPath,
    copy_source: Option<&HgPath>,
) -> usize {
    MIN_ENTRY_SIZE
        + packed_filename_and_copy_source_size(filename, copy_source)
}

pub fn pack_entry(
    filename: &HgPath,
    entry: &DirstateEntry,
    copy_source: Option<&HgPath>,
    packed: &mut Vec<u8>,
) {
    let length = packed_filename_and_copy_source_size(filename, copy_source);
    let (state, mode, size, mtime) = entry.v1_data();

    // Unwrapping because `impl std::io::Write for Vec<u8>` never errors
    packed.write_u8(state).unwrap();
    packed.write_i32::<BigEndian>(mode).unwrap();
    packed.write_i32::<BigEndian>(size).unwrap();
    packed.write_i32::<BigEndian>(mtime).unwrap();
    packed.write_i32::<BigEndian>(length as i32).unwrap();
    packed.extend(filename.as_bytes());
    if let Some(source) = copy_source {
        packed.push(b'\0');
        packed.extend(source.as_bytes());
    }
}

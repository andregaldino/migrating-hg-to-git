// dirstate module
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate_tree::on_disk::DirstateV2ParseError;
use crate::revlog::node::NULL_NODE;
use crate::revlog::Node;
use crate::utils::hg_path::HgPath;
use bytes_cast::BytesCast;

pub mod dirs_multiset;
pub mod entry;
pub mod parsers;
pub mod status;

pub use self::entry::*;

#[derive(Debug, PartialEq, Copy, Clone, BytesCast)]
#[repr(C)]
pub struct DirstateParents {
    pub p1: Node,
    pub p2: Node,
}

impl DirstateParents {
    pub const NULL: Self = Self {
        p1: NULL_NODE,
        p2: NULL_NODE,
    };
}

pub type StateMapIter<'a> = Box<
    dyn Iterator<
            Item = Result<(&'a HgPath, DirstateEntry), DirstateV2ParseError>,
        > + Send
        + 'a,
>;

pub type CopyMapIter<'a> = Box<
    dyn Iterator<Item = Result<(&'a HgPath, &'a HgPath), DirstateV2ParseError>>
        + Send
        + 'a,
>;

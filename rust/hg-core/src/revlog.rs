// Copyright 2018-2020 Georges Racinet <georges.racinet@octobus.net>
//           and Mercurial contributors
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.
//! Mercurial concepts for handling revision history

pub mod node;
pub mod nodemap;
mod nodemap_docket;
pub mod path_encode;
pub use node::{FromHexError, Node, NodePrefix};
pub mod changelog;
pub mod filelog;
pub mod index;
pub mod manifest;
pub mod patch;
pub mod revlog;

/// Mercurial revision numbers
///
/// As noted in revlog.c, revision numbers are actually encoded in
/// 4 bytes, and are liberally converted to ints, whence the i32
pub type Revision = i32;

/// Marker expressing the absence of a parent
///
/// Independently of the actual representation, `NULL_REVISION` is guaranteed
/// to be smaller than all existing revisions.
pub const NULL_REVISION: Revision = -1;

/// Same as `mercurial.node.wdirrev`
///
/// This is also equal to `i32::max_value()`, but it's better to spell
/// it out explicitely, same as in `mercurial.node`
#[allow(clippy::unreadable_literal)]
pub const WORKING_DIRECTORY_REVISION: Revision = 0x7fffffff;

pub const WORKING_DIRECTORY_HEX: &str =
    "ffffffffffffffffffffffffffffffffffffffff";

/// The simplest expression of what we need of Mercurial DAGs.
pub trait Graph {
    /// Return the two parents of the given `Revision`.
    ///
    /// Each of the parents can be independently `NULL_REVISION`
    fn parents(&self, rev: Revision) -> Result<[Revision; 2], GraphError>;
}

#[derive(Clone, Debug, PartialEq)]
pub enum GraphError {
    ParentOutOfRange(Revision),
    WorkingDirectoryUnsupported,
}

/// The Mercurial Revlog Index
///
/// This is currently limited to the minimal interface that is needed for
/// the [`nodemap`](nodemap/index.html) module
pub trait RevlogIndex {
    /// Total number of Revisions referenced in this index
    fn len(&self) -> usize;

    fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Return a reference to the Node or `None` if rev is out of bounds
    ///
    /// `NULL_REVISION` is not considered to be out of bounds.
    fn node(&self, rev: Revision) -> Option<&Node>;
}

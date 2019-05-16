// Copyright 2018 Georges Racinet <gracinet@anybox.fr>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.
extern crate byteorder;
extern crate memchr;
#[macro_use]
extern crate lazy_static;
extern crate regex;

mod ancestors;
pub mod dagops;
pub use ancestors::{AncestorsIterator, LazyAncestors, MissingAncestors};
mod dirstate;
pub mod discovery;
pub mod testing; // unconditionally built, for use from integration tests
pub use dirstate::{
    parsers::{pack_dirstate, parse_dirstate},
    CopyVec, CopyVecEntry, DirstateEntry, DirstateParents, DirstateVec,
};
mod filepatterns;

pub use filepatterns::{
    build_single_regex, read_pattern_file, PatternSyntax, PatternTuple,
};

/// Mercurial revision numbers
///
/// As noted in revlog.c, revision numbers are actually encoded in
/// 4 bytes, and are liberally converted to ints, whence the i32
pub type Revision = i32;

/// Marker expressing the absence of a parent
///
/// Independently of the actual representation, `NULL_REVISION` is guaranteed
/// to be smaller that all existing revisions.
pub const NULL_REVISION: Revision = -1;

/// Same as `mercurial.node.wdirrev`
///
/// This is also equal to `i32::max_value()`, but it's better to spell
/// it out explicitely, same as in `mercurial.node`
pub const WORKING_DIRECTORY_REVISION: Revision = 0x7fffffff;

/// The simplest expression of what we need of Mercurial DAGs.
pub trait Graph {
    /// Return the two parents of the given `Revision`.
    ///
    /// Each of the parents can be independently `NULL_REVISION`
    fn parents(&self, Revision) -> Result<[Revision; 2], GraphError>;
}

pub type LineNumber = usize;

#[derive(Clone, Debug, PartialEq)]
pub enum GraphError {
    ParentOutOfRange(Revision),
    WorkingDirectoryUnsupported,
}

#[derive(Clone, Debug, PartialEq)]
pub enum DirstateParseError {
    TooLittleData,
    Overflow,
    CorruptedEntry(String),
}

#[derive(Debug, PartialEq)]
pub enum DirstatePackError {
    CorruptedEntry(String),
    CorruptedParent,
    BadSize(usize, usize),
}

impl From<std::io::Error> for DirstatePackError {
    fn from(e: std::io::Error) -> Self {
        DirstatePackError::CorruptedEntry(e.to_string())
    }
}

impl From<std::io::Error> for DirstateParseError {
    fn from(e: std::io::Error) -> Self {
        DirstateParseError::CorruptedEntry(e.to_string())
    }
}

#[derive(Debug)]
pub enum PatternError {
    UnsupportedSyntax(String),
}

#[derive(Debug)]
pub enum PatternFileError {
    IO(std::io::Error),
    Pattern(PatternError, LineNumber),
}

impl From<std::io::Error> for PatternFileError {
    fn from(e: std::io::Error) -> Self {
        PatternFileError::IO(e)
    }
}

// Copyright 2018-2020 Georges Racinet <georges.racinet@octobus.net>
//           and Mercurial contributors
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.
mod ancestors;
pub mod dagops;
pub mod errors;
pub use ancestors::{AncestorsIterator, LazyAncestors, MissingAncestors};
mod dirstate;
pub mod discovery;
pub mod requirements;
pub mod testing; // unconditionally built, for use from integration tests
pub use dirstate::{
    dirs_multiset::{DirsMultiset, DirsMultisetIter},
    dirstate_map::DirstateMap,
    parsers::{pack_dirstate, parse_dirstate, PARENT_SIZE},
    status::{
        status, BadMatch, BadType, DirstateStatus, StatusError, StatusOptions,
    },
    CopyMap, CopyMapIter, DirstateEntry, DirstateParents, EntryState,
    StateMap, StateMapIter,
};
pub mod copy_tracing;
mod filepatterns;
pub mod matchers;
pub mod repo;
pub mod revlog;
pub use revlog::*;
pub mod config;
pub mod operations;
pub mod revset;
pub mod utils;

use crate::utils::hg_path::{HgPathBuf, HgPathError};
pub use filepatterns::{
    parse_pattern_syntax, read_pattern_file, IgnorePattern,
    PatternFileWarning, PatternSyntax,
};
use std::collections::HashMap;
use twox_hash::RandomXxHashBuilder64;

/// This is a contract between the `micro-timer` crate and us, to expose
/// the `log` crate as `crate::log`.
use log;

pub type LineNumber = usize;

/// Rust's default hasher is too slow because it tries to prevent collision
/// attacks. We are not concerned about those: if an ill-minded person has
/// write access to your repository, you have other issues.
pub type FastHashMap<K, V> = HashMap<K, V, RandomXxHashBuilder64>;

#[derive(Debug, PartialEq)]
pub enum DirstateMapError {
    PathNotFound(HgPathBuf),
    EmptyPath,
    InvalidPath(HgPathError),
}

impl ToString for DirstateMapError {
    fn to_string(&self) -> String {
        match self {
            DirstateMapError::PathNotFound(_) => {
                "expected a value, found none".to_string()
            }
            DirstateMapError::EmptyPath => "Overflow in dirstate.".to_string(),
            DirstateMapError::InvalidPath(e) => e.to_string(),
        }
    }
}

#[derive(Debug, derive_more::From)]
pub enum DirstateError {
    Map(DirstateMapError),
    Common(errors::HgError),
}

#[derive(Debug, derive_more::From)]
pub enum PatternError {
    #[from]
    Path(HgPathError),
    UnsupportedSyntax(String),
    UnsupportedSyntaxInFile(String, String, usize),
    TooLong(usize),
    #[from]
    IO(std::io::Error),
    /// Needed a pattern that can be turned into a regex but got one that
    /// can't. This should only happen through programmer error.
    NonRegexPattern(IgnorePattern),
}

impl ToString for PatternError {
    fn to_string(&self) -> String {
        match self {
            PatternError::UnsupportedSyntax(syntax) => {
                format!("Unsupported syntax {}", syntax)
            }
            PatternError::UnsupportedSyntaxInFile(syntax, file_path, line) => {
                format!(
                    "{}:{}: unsupported syntax {}",
                    file_path, line, syntax
                )
            }
            PatternError::TooLong(size) => {
                format!("matcher pattern is too long ({} bytes)", size)
            }
            PatternError::IO(e) => e.to_string(),
            PatternError::Path(e) => e.to_string(),
            PatternError::NonRegexPattern(pattern) => {
                format!("'{:?}' cannot be turned into a regex", pattern)
            }
        }
    }
}

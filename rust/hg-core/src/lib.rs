// Copyright 2018-2020 Georges Racinet <georges.racinet@octobus.net>
//           and Mercurial contributors
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

mod ancestors;
pub mod dagops;
pub mod errors;
pub use ancestors::{AncestorsIterator, LazyAncestors, MissingAncestors};
pub mod dirstate;
pub mod dirstate_tree;
pub mod discovery;
pub mod exit_codes;
pub mod requirements;
pub mod testing; // unconditionally built, for use from integration tests
pub use dirstate::{
    dirs_multiset::{DirsMultiset, DirsMultisetIter},
    status::{
        BadMatch, BadType, DirstateStatus, HgPathCow, StatusError,
        StatusOptions,
    },
    DirstateEntry, DirstateParents, EntryState,
};
pub mod copy_tracing;
mod filepatterns;
pub mod matchers;
pub mod repo;
pub mod revlog;
pub use revlog::*;
pub mod config;
pub mod lock;
pub mod logging;
pub mod operations;
pub mod revset;
pub mod utils;
pub mod vfs;

use crate::utils::hg_path::{HgPathBuf, HgPathError};
pub use filepatterns::{
    parse_pattern_syntax, read_pattern_file, IgnorePattern,
    PatternFileWarning, PatternSyntax,
};
use std::collections::HashMap;
use std::fmt;
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

impl fmt::Display for DirstateMapError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            DirstateMapError::PathNotFound(_) => {
                f.write_str("expected a value, found none")
            }
            DirstateMapError::EmptyPath => {
                f.write_str("Overflow in dirstate.")
            }
            DirstateMapError::InvalidPath(path_error) => path_error.fmt(f),
        }
    }
}

#[derive(Debug, derive_more::From)]
pub enum DirstateError {
    Map(DirstateMapError),
    Common(errors::HgError),
}

impl fmt::Display for DirstateError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            DirstateError::Map(error) => error.fmt(f),
            DirstateError::Common(error) => error.fmt(f),
        }
    }
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

impl fmt::Display for PatternError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            PatternError::UnsupportedSyntax(syntax) => {
                write!(f, "Unsupported syntax {}", syntax)
            }
            PatternError::UnsupportedSyntaxInFile(syntax, file_path, line) => {
                write!(
                    f,
                    "{}:{}: unsupported syntax {}",
                    file_path, line, syntax
                )
            }
            PatternError::TooLong(size) => {
                write!(f, "matcher pattern is too long ({} bytes)", size)
            }
            PatternError::IO(error) => error.fmt(f),
            PatternError::Path(error) => error.fmt(f),
            PatternError::NonRegexPattern(pattern) => {
                write!(f, "'{:?}' cannot be turned into a regex", pattern)
            }
        }
    }
}

// status.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Rust implementation of dirstate.status (dirstate.py).
//! It is currently missing a lot of functionality compared to the Python one
//! and will only be triggered in narrow cases.

use crate::dirstate::entry::TruncatedTimestamp;
use crate::dirstate_tree::on_disk::DirstateV2ParseError;
use crate::{
    utils::hg_path::{HgPath, HgPathError},
    PatternError,
};

use std::{borrow::Cow, fmt};

/// Wrong type of file from a `BadMatch`
/// Note: a lot of those don't exist on all platforms.
#[derive(Debug, Copy, Clone)]
pub enum BadType {
    CharacterDevice,
    BlockDevice,
    FIFO,
    Socket,
    Directory,
    Unknown,
}

impl fmt::Display for BadType {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(match self {
            BadType::CharacterDevice => "character device",
            BadType::BlockDevice => "block device",
            BadType::FIFO => "fifo",
            BadType::Socket => "socket",
            BadType::Directory => "directory",
            BadType::Unknown => "unknown",
        })
    }
}

/// Was explicitly matched but cannot be found/accessed
#[derive(Debug, Copy, Clone)]
pub enum BadMatch {
    OsError(i32),
    BadType(BadType),
}

/// `Box<dyn Trait>` is syntactic sugar for `Box<dyn Trait + 'static>`, so add
/// an explicit lifetime here to not fight `'static` bounds "out of nowhere".
pub type IgnoreFnType<'a> =
    Box<dyn for<'r> Fn(&'r HgPath) -> bool + Sync + 'a>;

/// We have a good mix of owned (from directory traversal) and borrowed (from
/// the dirstate/explicit) paths, this comes up a lot.
pub type HgPathCow<'a> = Cow<'a, HgPath>;

#[derive(Debug, Copy, Clone)]
pub struct StatusOptions {
    /// Whether we are on a filesystem with UNIX-like exec flags
    pub check_exec: bool,
    pub list_clean: bool,
    pub list_unknown: bool,
    pub list_ignored: bool,
    /// Whether to populate `StatusPath::copy_source`
    pub list_copies: bool,
    /// Whether to collect traversed dirs for applying a callback later.
    /// Used by `hg purge` for example.
    pub collect_traversed_dirs: bool,
}

#[derive(Default)]
pub struct DirstateStatus<'a> {
    /// The current time at the start of the `status()` algorithm, as measured
    /// and possibly truncated by the filesystem.
    pub filesystem_time_at_status_start: Option<TruncatedTimestamp>,

    /// Tracked files whose contents have changed since the parent revision
    pub modified: Vec<StatusPath<'a>>,

    /// Newly-tracked files that were not present in the parent
    pub added: Vec<StatusPath<'a>>,

    /// Previously-tracked files that have been (re)moved with an hg command
    pub removed: Vec<StatusPath<'a>>,

    /// (Still) tracked files that are missing, (re)moved with an non-hg
    /// command
    pub deleted: Vec<StatusPath<'a>>,

    /// Tracked files that are up to date with the parent.
    /// Only pupulated if `StatusOptions::list_clean` is true.
    pub clean: Vec<StatusPath<'a>>,

    /// Files in the working directory that are ignored with `.hgignore`.
    /// Only pupulated if `StatusOptions::list_ignored` is true.
    pub ignored: Vec<StatusPath<'a>>,

    /// Files in the working directory that are neither tracked nor ignored.
    /// Only pupulated if `StatusOptions::list_unknown` is true.
    pub unknown: Vec<StatusPath<'a>>,

    /// Was explicitly matched but cannot be found/accessed
    pub bad: Vec<(HgPathCow<'a>, BadMatch)>,

    /// Either clean or modified, but we can’t tell from filesystem metadata
    /// alone. The file contents need to be read and compared with that in
    /// the parent.
    pub unsure: Vec<StatusPath<'a>>,

    /// Only filled if `collect_traversed_dirs` is `true`
    pub traversed: Vec<HgPathCow<'a>>,

    /// Whether `status()` made changed to the `DirstateMap` that should be
    /// written back to disk
    pub dirty: bool,
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct StatusPath<'a> {
    pub path: HgPathCow<'a>,
    pub copy_source: Option<HgPathCow<'a>>,
}

#[derive(Debug, derive_more::From)]
pub enum StatusError {
    /// An invalid path that cannot be represented in Mercurial was found
    Path(HgPathError),
    /// An invalid "ignore" pattern was found
    Pattern(PatternError),
    /// Corrupted dirstate
    DirstateV2ParseError(DirstateV2ParseError),
}

impl fmt::Display for StatusError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            StatusError::Path(error) => error.fmt(f),
            StatusError::Pattern(error) => error.fmt(f),
            StatusError::DirstateV2ParseError(_) => {
                f.write_str("dirstate-v2 parse error")
            }
        }
    }
}

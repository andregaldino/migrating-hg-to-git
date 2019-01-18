// testing.rs
//
// Copyright 2018 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::{Graph, GraphError, Revision, NULL_REVISION};

/// A stub `Graph`, same as the one from `test-ancestor.py`
///
/// o  13
/// |
/// | o  12
/// | |
/// | | o    11
/// | | |\
/// | | | | o  10
/// | | | | |
/// | o---+ |  9
/// | | | | |
/// o | | | |  8
///  / / / /
/// | | o |  7
/// | | | |
/// o---+ |  6
///  / / /
/// | | o  5
/// | |/
/// | o  4
/// | |
/// o |  3
/// | |
/// | o  2
/// |/
/// o  1
/// |
/// o  0
#[derive(Clone, Debug)]
pub struct SampleGraph;

impl Graph for SampleGraph {
    fn parents(&self, rev: Revision) -> Result<[Revision; 2], GraphError> {
        match rev {
            0 => Ok([NULL_REVISION, NULL_REVISION]),
            1 => Ok([0, NULL_REVISION]),
            2 => Ok([1, NULL_REVISION]),
            3 => Ok([1, NULL_REVISION]),
            4 => Ok([2, NULL_REVISION]),
            5 => Ok([4, NULL_REVISION]),
            6 => Ok([4, NULL_REVISION]),
            7 => Ok([4, NULL_REVISION]),
            8 => Ok([NULL_REVISION, NULL_REVISION]),
            9 => Ok([6, 7]),
            10 => Ok([5, NULL_REVISION]),
            11 => Ok([3, 7]),
            12 => Ok([9, NULL_REVISION]),
            13 => Ok([8, NULL_REVISION]),
            r => Err(GraphError::ParentOutOfRange(r)),
        }
    }
}

// A Graph represented by a vector whose indices are revisions
// and values are parents of the revisions
pub type VecGraph = Vec<[Revision; 2]>;

impl Graph for VecGraph {
    fn parents(&self, rev: Revision) -> Result<[Revision; 2], GraphError> {
        Ok(self[rev as usize])
    }
}

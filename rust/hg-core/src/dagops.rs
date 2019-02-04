// dagops.rs
//
// Copyright 2019 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Miscellaneous DAG operations
//!
//! # Terminology
//! - By *relative heads* of a collection of revision numbers (`Revision`),
//!   we mean those revisions that have no children among the collection.
//! - Similarly *relative roots* of a collection of `Revision`, we mean
//!   those whose parents, if any, don't belong to the collection.
use super::{Graph, GraphError, Revision, NULL_REVISION};
use std::collections::HashSet;

fn remove_parents(
    graph: &impl Graph,
    rev: Revision,
    set: &mut HashSet<Revision>,
) -> Result<(), GraphError> {
    for parent in graph.parents(rev)?.iter() {
        if *parent != NULL_REVISION {
            set.remove(parent);
        }
    }
    Ok(())
}

/// Relative heads out of some revisions, passed as an iterator.
///
/// These heads are defined as those revisions that have no children
/// among those emitted by the iterator.
///
/// # Performance notes
/// Internally, this clones the iterator, and builds a `HashSet` out of it.
///
/// This function takes an `Iterator` instead of `impl IntoIterator` to
/// guarantee that cloning the iterator doesn't result in cloning the full
/// construct it comes from.
pub fn heads<'a>(
    graph: &impl Graph,
    iter_revs: impl Clone + Iterator<Item = &'a Revision>,
) -> Result<HashSet<Revision>, GraphError> {
    let mut heads: HashSet<Revision> = iter_revs.clone().cloned().collect();
    heads.remove(&NULL_REVISION);
    for rev in iter_revs {
        if *rev != NULL_REVISION {
            remove_parents(graph, *rev, &mut heads)?;
        }
    }
    Ok(heads)
}

/// Retain in `revs` only its relative heads.
///
/// This is an in-place operation, so that control of the incoming
/// set is left to the caller.
/// - a direct Python binding would probably need to build its own `HashSet`
///   from an incoming iterable, even if its sole purpose is to extract the
///   heads.
/// - a Rust caller can decide whether cloning beforehand is appropriate
///
/// # Performance notes
/// Internally, this function will store a full copy of `revs` in a `Vec`.
pub fn retain_heads(
    graph: &impl Graph,
    revs: &mut HashSet<Revision>,
) -> Result<(), GraphError> {
    revs.remove(&NULL_REVISION);
    // we need to construct an iterable copy of revs to avoid itering while
    // mutating
    let as_vec: Vec<Revision> = revs.iter().cloned().collect();
    for rev in as_vec {
        if rev != NULL_REVISION {
            remove_parents(graph, rev, revs)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {

    use super::*;
    use crate::testing::SampleGraph;

    /// Apply `retain_heads()` to the given slice and return as a sorted `Vec`
    fn retain_heads_sorted(
        graph: &impl Graph,
        revs: &[Revision],
    ) -> Result<Vec<Revision>, GraphError> {
        let mut revs: HashSet<Revision> = revs.iter().cloned().collect();
        retain_heads(graph, &mut revs)?;
        let mut as_vec: Vec<Revision> = revs.iter().cloned().collect();
        as_vec.sort();
        Ok(as_vec)
    }

    #[test]
    fn test_retain_heads() -> Result<(), GraphError> {
        assert_eq!(retain_heads_sorted(&SampleGraph, &[4, 5, 6])?, vec![5, 6]);
        assert_eq!(
            retain_heads_sorted(&SampleGraph, &[4, 1, 6, 12, 0])?,
            vec![1, 6, 12]
        );
        assert_eq!(
            retain_heads_sorted(&SampleGraph, &[1, 2, 3, 4, 5, 6, 7, 8, 9])?,
            vec![3, 5, 8, 9]
        );
        Ok(())
    }

    /// Apply `heads()` to the given slice and return as a sorted `Vec`
    fn heads_sorted(
        graph: &impl Graph,
        revs: &[Revision],
    ) -> Result<Vec<Revision>, GraphError> {
        let heads = heads(graph, revs.iter())?;
        let mut as_vec: Vec<Revision> = heads.iter().cloned().collect();
        as_vec.sort();
        Ok(as_vec)
    }

    #[test]
    fn test_heads() -> Result<(), GraphError> {
        assert_eq!(heads_sorted(&SampleGraph, &[4, 5, 6])?, vec![5, 6]);
        assert_eq!(
            heads_sorted(&SampleGraph, &[4, 1, 6, 12, 0])?,
            vec![1, 6, 12]
        );
        assert_eq!(
            heads_sorted(&SampleGraph, &[1, 2, 3, 4, 5, 6, 7, 8, 9])?,
            vec![3, 5, 8, 9]
        );
        Ok(())
    }

}

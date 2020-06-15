// dagops.rs
//
// Copyright 2019 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Miscellaneous DAG operations
//!
//! # Terminology
//! - By *relative heads* of a collection of revision numbers (`Revision`), we
//!   mean those revisions that have no children among the collection.
//! - Similarly *relative roots* of a collection of `Revision`, we mean those
//!   whose parents, if any, don't belong to the collection.
use super::{Graph, GraphError, Revision, NULL_REVISION};
use crate::ancestors::AncestorsIterator;
use std::collections::{BTreeSet, HashSet};

fn remove_parents<S: std::hash::BuildHasher>(
    graph: &impl Graph,
    rev: Revision,
    set: &mut HashSet<Revision, S>,
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
pub fn retain_heads<S: std::hash::BuildHasher>(
    graph: &impl Graph,
    revs: &mut HashSet<Revision, S>,
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

/// Roots of `revs`, passed as a `HashSet`
///
/// They are returned in arbitrary order
pub fn roots<G: Graph, S: std::hash::BuildHasher>(
    graph: &G,
    revs: &HashSet<Revision, S>,
) -> Result<Vec<Revision>, GraphError> {
    let mut roots: Vec<Revision> = Vec::new();
    for rev in revs {
        if graph
            .parents(*rev)?
            .iter()
            .filter(|p| **p != NULL_REVISION)
            .all(|p| !revs.contains(p))
        {
            roots.push(*rev);
        }
    }
    Ok(roots)
}

/// Compute the topological range between two collections of revisions
///
/// This is equivalent to the revset `<roots>::<heads>`.
///
/// Currently, the given `Graph` has to implement `Clone`, which means
/// actually cloning just a reference-counted Python pointer if
/// it's passed over through `rust-cpython`. This is due to the internal
/// use of `AncestorsIterator`
///
/// # Algorithmic details
///
/// This is a two-pass swipe inspired from what `reachableroots2` from
/// `mercurial.cext.parsers` does to obtain the same results.
///
/// - first, we climb up the DAG from `heads` in topological order, keeping
///   them in the vector `heads_ancestors` vector, and adding any element of
///   `roots` we find among them to the resulting range.
/// - Then, we iterate on that recorded vector so that a revision is always
///   emitted after its parents and add all revisions whose parents are already
///   in the range to the results.
///
/// # Performance notes
///
/// The main difference with the C implementation is that
/// the latter uses a flat array with bit flags, instead of complex structures
/// like `HashSet`, making it faster in most scenarios. In theory, it's
/// possible that the present implementation could be more memory efficient
/// for very large repositories with many branches.
pub fn range(
    graph: &(impl Graph + Clone),
    roots: impl IntoIterator<Item = Revision>,
    heads: impl IntoIterator<Item = Revision>,
) -> Result<BTreeSet<Revision>, GraphError> {
    let mut range = BTreeSet::new();
    let roots: HashSet<Revision> = roots.into_iter().collect();
    let min_root: Revision = match roots.iter().cloned().min() {
        None => {
            return Ok(range);
        }
        Some(r) => r,
    };

    // Internally, AncestorsIterator currently maintains a `HashSet`
    // of all seen revision, which is also what we record, albeit in an ordered
    // way. There's room for improvement on this duplication.
    let ait = AncestorsIterator::new(graph.clone(), heads, min_root, true)?;
    let mut heads_ancestors: Vec<Revision> = Vec::new();
    for revres in ait {
        let rev = revres?;
        if roots.contains(&rev) {
            range.insert(rev);
        }
        heads_ancestors.push(rev);
    }

    for rev in heads_ancestors.into_iter().rev() {
        for parent in graph.parents(rev)?.iter() {
            if *parent != NULL_REVISION && range.contains(parent) {
                range.insert(rev);
            }
        }
    }
    Ok(range)
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

    /// Apply `roots()` and sort the result for easier comparison
    fn roots_sorted(
        graph: &impl Graph,
        revs: &[Revision],
    ) -> Result<Vec<Revision>, GraphError> {
        let set: HashSet<_> = revs.iter().cloned().collect();
        let mut as_vec = roots(graph, &set)?;
        as_vec.sort();
        Ok(as_vec)
    }

    #[test]
    fn test_roots() -> Result<(), GraphError> {
        assert_eq!(roots_sorted(&SampleGraph, &[4, 5, 6])?, vec![4]);
        assert_eq!(
            roots_sorted(&SampleGraph, &[4, 1, 6, 12, 0])?,
            vec![0, 4, 12]
        );
        assert_eq!(
            roots_sorted(&SampleGraph, &[1, 2, 3, 4, 5, 6, 7, 8, 9])?,
            vec![1, 8]
        );
        Ok(())
    }

    /// Apply `range()` and convert the result into a Vec for easier comparison
    fn range_vec(
        graph: impl Graph + Clone,
        roots: &[Revision],
        heads: &[Revision],
    ) -> Result<Vec<Revision>, GraphError> {
        range(&graph, roots.iter().cloned(), heads.iter().cloned())
            .map(|bs| bs.into_iter().collect())
    }

    #[test]
    fn test_range() -> Result<(), GraphError> {
        assert_eq!(range_vec(SampleGraph, &[0], &[4])?, vec![0, 1, 2, 4]);
        assert_eq!(range_vec(SampleGraph, &[0], &[8])?, vec![]);
        assert_eq!(
            range_vec(SampleGraph, &[5, 6], &[10, 11, 13])?,
            vec![5, 10]
        );
        assert_eq!(
            range_vec(SampleGraph, &[5, 6], &[10, 12])?,
            vec![5, 6, 9, 10, 12]
        );
        Ok(())
    }
}

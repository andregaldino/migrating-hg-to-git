// discovery.rs
//
// Copyright 2019 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Discovery operations
//!
//! This is a Rust counterpart to the `partialdiscovery` class of
//! `mercurial.setdiscovery`

use super::{Graph, GraphError, Revision};
use crate::ancestors::MissingAncestors;
use crate::dagops;
use std::collections::HashSet;

pub struct PartialDiscovery<G: Graph + Clone> {
    target_heads: Option<Vec<Revision>>,
    graph: G, // plays the role of self._repo
    common: MissingAncestors<G>,
    undecided: Option<HashSet<Revision>>,
    missing: HashSet<Revision>,
}

pub struct DiscoveryStats {
    pub undecided: Option<usize>,
}

impl<G: Graph + Clone> PartialDiscovery<G> {
    /// Create a PartialDiscovery object, with the intent
    /// of comparing our `::<target_heads>` revset to the contents of another
    /// repo.
    ///
    /// For now `target_heads` is passed as a vector, and will be used
    /// at the first call to `ensure_undecided()`.
    ///
    /// If we want to make the signature more flexible,
    /// we'll have to make it a type argument of `PartialDiscovery` or a trait
    /// object since we'll keep it in the meanwhile
    pub fn new(graph: G, target_heads: Vec<Revision>) -> Self {
        PartialDiscovery {
            undecided: None,
            target_heads: Some(target_heads),
            graph: graph.clone(),
            common: MissingAncestors::new(graph, vec![]),
            missing: HashSet::new(),
        }
    }

    /// Register revisions known as being common
    pub fn add_common_revisions(
        &mut self,
        common: impl IntoIterator<Item = Revision>,
    ) -> Result<(), GraphError> {
        self.common.add_bases(common);
        if let Some(ref mut undecided) = self.undecided {
            self.common.remove_ancestors_from(undecided)?;
        }
        Ok(())
    }

    /// Register revisions known as being missing
    pub fn add_missing_revisions(
        &mut self,
        missing: impl IntoIterator<Item = Revision>,
    ) -> Result<(), GraphError> {
        self.ensure_undecided()?;
        let range = dagops::range(
            &self.graph,
            missing,
            self.undecided.as_ref().unwrap().iter().cloned(),
        )?;
        let undecided_mut = self.undecided.as_mut().unwrap();
        for missrev in range {
            self.missing.insert(missrev);
            undecided_mut.remove(&missrev);
        }
        Ok(())
    }

    /// Do we have any information about the peer?
    pub fn has_info(&self) -> bool {
        self.common.has_bases()
    }

    /// Did we acquire full knowledge of our Revisions that the peer has?
    pub fn is_complete(&self) -> bool {
        self.undecided.as_ref().map_or(false, |s| s.is_empty())
    }

    /// Return the heads of the currently known common set of revisions.
    ///
    /// If the discovery process is not complete (see `is_complete()`), the
    /// caller must be aware that this is an intermediate state.
    ///
    /// On the other hand, if it is complete, then this is currently
    /// the only way to retrieve the end results of the discovery process.
    ///
    /// We may introduce in the future an `into_common_heads` call that
    /// would be more appropriate for normal Rust callers, dropping `self`
    /// if it is complete.
    pub fn common_heads(&self) -> Result<HashSet<Revision>, GraphError> {
        self.common.bases_heads()
    }

    /// Force first computation of `self.undecided`
    ///
    /// After this, `self.undecided.as_ref()` and `.as_mut()` can be
    /// unwrapped to get workable immutable or mutable references without
    /// any panic.
    ///
    /// This is an imperative call instead of an access with added lazyness
    /// to reduce easily the scope of mutable borrow for the caller,
    /// compared to undecided(&'a mut self) -> &'a… that would keep it
    /// as long as the resulting immutable one.
    fn ensure_undecided(&mut self) -> Result<(), GraphError> {
        if self.undecided.is_some() {
            return Ok(());
        }
        let tgt = self.target_heads.take().unwrap();
        self.undecided =
            Some(self.common.missing_ancestors(tgt)?.into_iter().collect());
        Ok(())
    }

    /// Provide statistics about the current state of the discovery process
    pub fn stats(&self) -> DiscoveryStats {
        DiscoveryStats {
            undecided: self.undecided.as_ref().map(|s| s.len()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::SampleGraph;

    /// A PartialDiscovery as for pushing all the heads of `SampleGraph`
    fn full_disco() -> PartialDiscovery<SampleGraph> {
        PartialDiscovery::new(SampleGraph, vec![10, 11, 12, 13])
    }

    fn sorted_undecided(
        disco: &PartialDiscovery<SampleGraph>,
    ) -> Vec<Revision> {
        let mut as_vec: Vec<Revision> =
            disco.undecided.as_ref().unwrap().iter().cloned().collect();
        as_vec.sort();
        as_vec
    }

    fn sorted_missing(disco: &PartialDiscovery<SampleGraph>) -> Vec<Revision> {
        let mut as_vec: Vec<Revision> =
            disco.missing.iter().cloned().collect();
        as_vec.sort();
        as_vec
    }

    fn sorted_common_heads(
        disco: &PartialDiscovery<SampleGraph>,
    ) -> Result<Vec<Revision>, GraphError> {
        let mut as_vec: Vec<Revision> =
            disco.common_heads()?.iter().cloned().collect();
        as_vec.sort();
        Ok(as_vec)
    }

    #[test]
    fn test_add_common_get_undecided() -> Result<(), GraphError> {
        let mut disco = full_disco();
        assert_eq!(disco.undecided, None);
        assert!(!disco.has_info());
        assert_eq!(disco.stats().undecided, None);

        disco.add_common_revisions(vec![11, 12])?;
        assert!(disco.has_info());
        assert!(!disco.is_complete());
        assert!(disco.missing.is_empty());

        // add_common_revisions did not trigger a premature computation
        // of `undecided`, let's check that and ask for them
        assert_eq!(disco.undecided, None);
        disco.ensure_undecided()?;
        assert_eq!(sorted_undecided(&disco), vec![5, 8, 10, 13]);
        assert_eq!(disco.stats().undecided, Some(4));
        Ok(())
    }

    /// in this test, we pretend that our peer misses exactly (8+10)::
    /// and we're comparing all our repo to it (as in a bare push)
    #[test]
    fn test_discovery() -> Result<(), GraphError> {
        let mut disco = full_disco();
        disco.add_common_revisions(vec![11, 12])?;
        disco.add_missing_revisions(vec![8, 10])?;
        assert_eq!(sorted_undecided(&disco), vec![5]);
        assert_eq!(sorted_missing(&disco), vec![8, 10, 13]);
        assert!(!disco.is_complete());

        disco.add_common_revisions(vec![5])?;
        assert_eq!(sorted_undecided(&disco), vec![]);
        assert_eq!(sorted_missing(&disco), vec![8, 10, 13]);
        assert!(disco.is_complete());
        assert_eq!(sorted_common_heads(&disco)?, vec![5, 11, 12]);
        Ok(())
    }
}

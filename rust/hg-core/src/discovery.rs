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

extern crate rand;
extern crate rand_pcg;
use self::rand::seq::SliceRandom;
use self::rand::{thread_rng, RngCore, SeedableRng};
use super::{Graph, GraphError, Revision, NULL_REVISION};
use crate::ancestors::MissingAncestors;
use crate::dagops;
use std::collections::{HashMap, HashSet, VecDeque};

type Rng = self::rand_pcg::Pcg32;

pub struct PartialDiscovery<G: Graph + Clone> {
    target_heads: Option<Vec<Revision>>,
    graph: G, // plays the role of self._repo
    common: MissingAncestors<G>,
    undecided: Option<HashSet<Revision>>,
    missing: HashSet<Revision>,
    rng: Rng,
}

pub struct DiscoveryStats {
    pub undecided: Option<usize>,
}

/// Update an existing sample to match the expected size
///
/// The sample is updated with revisions exponentially distant from each
/// element of `heads`.
///
/// If a target size is specified, the sampling will stop once this size is
/// reached. Otherwise sampling will happen until roots of the <revs> set are
/// reached.
///
/// - `revs`: set of revs we want to discover (if None, `assume` the whole dag
///   represented by `parentfn`
/// - `heads`: set of DAG head revs
/// - `sample`: a sample to update
/// - `parentfn`: a callable to resolve parents for a revision
/// - `quicksamplesize`: optional target size of the sample
fn update_sample(
    revs: Option<&HashSet<Revision>>,
    heads: impl IntoIterator<Item = Revision>,
    sample: &mut HashSet<Revision>,
    parentsfn: impl Fn(Revision) -> Result<[Revision; 2], GraphError>,
    quicksamplesize: Option<usize>,
) -> Result<(), GraphError> {
    let mut distances: HashMap<Revision, u32> = HashMap::new();
    let mut visit: VecDeque<Revision> = heads.into_iter().collect();
    let mut factor: u32 = 1;
    let mut seen: HashSet<Revision> = HashSet::new();
    loop {
        let current = match visit.pop_front() {
            None => {
                break;
            }
            Some(r) => r,
        };
        if !seen.insert(current) {
            continue;
        }

        let d = *distances.entry(current).or_insert(1);
        if d > factor {
            factor *= 2;
        }
        if d == factor {
            sample.insert(current);
            if let Some(sz) = quicksamplesize {
                if sample.len() >= sz {
                    return Ok(());
                }
            }
        }
        for &p in &parentsfn(current)? {
            if p == NULL_REVISION {
                continue;
            }
            if let Some(revs) = revs {
                if !revs.contains(&p) {
                    continue;
                }
            }
            distances.entry(p).or_insert(d + 1);
            visit.push_back(p);
        }
    }
    Ok(())
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
        let mut seed: [u8; 16] = [0; 16];
        thread_rng().fill_bytes(&mut seed);
        Self::new_with_seed(graph, target_heads, seed)
    }

    pub fn new_with_seed(
        graph: G,
        target_heads: Vec<Revision>,
        seed: [u8; 16],
    ) -> Self {
        PartialDiscovery {
            undecided: None,
            target_heads: Some(target_heads),
            graph: graph.clone(),
            common: MissingAncestors::new(graph, vec![]),
            missing: HashSet::new(),
            rng: Rng::from_seed(seed),
        }
    }

    /// Extract at most `size` random elements from sample and return them
    /// as a vector
    fn limit_sample(
        &mut self,
        mut sample: Vec<Revision>,
        size: usize,
    ) -> Vec<Revision> {
        let sample_len = sample.len();
        if sample_len <= size {
            return sample;
        }
        let rng = &mut self.rng;
        let dropped_size = sample_len - size;
        let limited_slice = if size < dropped_size {
            sample.partial_shuffle(rng, size).0
        } else {
            sample.partial_shuffle(rng, dropped_size).1
        };
        limited_slice.to_owned()
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

    pub fn take_quick_sample(
        &mut self,
        headrevs: impl IntoIterator<Item = Revision>,
        size: usize,
    ) -> Result<Vec<Revision>, GraphError> {
        self.ensure_undecided()?;
        let mut sample = {
            let undecided = self.undecided.as_ref().unwrap();
            if undecided.len() <= size {
                return Ok(undecided.iter().cloned().collect());
            }
            dagops::heads(&self.graph, undecided.iter())?
        };
        if sample.len() >= size {
            return Ok(self.limit_sample(sample.into_iter().collect(), size));
        }
        update_sample(
            None,
            headrevs,
            &mut sample,
            |r| self.graph.parents(r),
            Some(size),
        )?;
        Ok(sample.into_iter().collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::SampleGraph;

    /// A PartialDiscovery as for pushing all the heads of `SampleGraph`
    ///
    /// To avoid actual randomness in tests, we give it a fixed random seed.
    fn full_disco() -> PartialDiscovery<SampleGraph> {
        PartialDiscovery::new_with_seed(
            SampleGraph,
            vec![10, 11, 12, 13],
            [0; 16],
        )
    }

    /// A PartialDiscovery as for pushing the 12 head of `SampleGraph`
    ///
    /// To avoid actual randomness in tests, we give it a fixed random seed.
    fn disco12() -> PartialDiscovery<SampleGraph> {
        PartialDiscovery::new_with_seed(SampleGraph, vec![12], [0; 16])
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

    #[test]
    fn test_limit_sample_no_need_to() {
        let sample = vec![1, 2, 3, 4];
        assert_eq!(full_disco().limit_sample(sample, 10), vec![1, 2, 3, 4]);
    }

    #[test]
    fn test_limit_sample_less_than_half() {
        assert_eq!(full_disco().limit_sample((1..6).collect(), 2), vec![4, 2]);
    }

    #[test]
    fn test_limit_sample_more_than_half() {
        assert_eq!(full_disco().limit_sample((1..4).collect(), 2), vec![3, 2]);
    }

    #[test]
    fn test_quick_sample_enough_undecided_heads() -> Result<(), GraphError> {
        let mut disco = full_disco();
        disco.undecided = Some((1..=13).collect());

        let mut sample_vec = disco.take_quick_sample(vec![], 4)?;
        sample_vec.sort();
        assert_eq!(sample_vec, vec![10, 11, 12, 13]);
        Ok(())
    }

    #[test]
    fn test_quick_sample_climbing_from_12() -> Result<(), GraphError> {
        let mut disco = disco12();
        disco.ensure_undecided()?;

        let mut sample_vec = disco.take_quick_sample(vec![12], 4)?;
        sample_vec.sort();
        // r12's only parent is r9, whose unique grand-parent through the
        // diamond shape is r4. This ends there because the distance from r4
        // to the root is only 3.
        assert_eq!(sample_vec, vec![4, 9, 12]);
        Ok(())
    }
}

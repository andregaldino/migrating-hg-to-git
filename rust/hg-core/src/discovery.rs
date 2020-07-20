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

use super::{Graph, GraphError, Revision, NULL_REVISION};
use crate::{ancestors::MissingAncestors, dagops, FastHashMap};
use rand::seq::SliceRandom;
use rand::{thread_rng, RngCore, SeedableRng};
use std::cmp::{max, min};
use std::collections::{HashSet, VecDeque};

type Rng = rand_pcg::Pcg32;
type Seed = [u8; 16];

pub struct PartialDiscovery<G: Graph + Clone> {
    target_heads: Option<Vec<Revision>>,
    graph: G, // plays the role of self._repo
    common: MissingAncestors<G>,
    undecided: Option<HashSet<Revision>>,
    children_cache: Option<FastHashMap<Revision, Vec<Revision>>>,
    missing: HashSet<Revision>,
    rng: Rng,
    respect_size: bool,
    randomize: bool,
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
fn update_sample<I>(
    revs: Option<&HashSet<Revision>>,
    heads: impl IntoIterator<Item = Revision>,
    sample: &mut HashSet<Revision>,
    parentsfn: impl Fn(Revision) -> Result<I, GraphError>,
    quicksamplesize: Option<usize>,
) -> Result<(), GraphError>
where
    I: Iterator<Item = Revision>,
{
    let mut distances: FastHashMap<Revision, u32> = FastHashMap::default();
    let mut visit: VecDeque<Revision> = heads.into_iter().collect();
    let mut factor: u32 = 1;
    let mut seen: HashSet<Revision> = HashSet::new();
    while let Some(current) = visit.pop_front() {
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
        for p in parentsfn(current)? {
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

struct ParentsIterator {
    parents: [Revision; 2],
    cur: usize,
}

impl ParentsIterator {
    fn graph_parents(
        graph: &impl Graph,
        r: Revision,
    ) -> Result<ParentsIterator, GraphError> {
        Ok(ParentsIterator {
            parents: graph.parents(r)?,
            cur: 0,
        })
    }
}

impl Iterator for ParentsIterator {
    type Item = Revision;

    fn next(&mut self) -> Option<Revision> {
        if self.cur > 1 {
            return None;
        }
        let rev = self.parents[self.cur];
        self.cur += 1;
        if rev == NULL_REVISION {
            return self.next();
        }
        Some(rev)
    }
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
    ///
    /// The `respect_size` boolean controls how the sampling methods
    /// will interpret the size argument requested by the caller. If it's
    /// `false`, they are allowed to produce a sample whose size is more
    /// appropriate to the situation (typically bigger).
    ///
    /// The `randomize` boolean affects sampling, and specifically how
    /// limiting or last-minute expanding is been done:
    ///
    /// If `true`, both will perform random picking from `self.undecided`.
    /// This is currently the best for actual discoveries.
    ///
    /// If `false`, a reproductible picking strategy is performed. This is
    /// useful for integration tests.
    pub fn new(
        graph: G,
        target_heads: Vec<Revision>,
        respect_size: bool,
        randomize: bool,
    ) -> Self {
        let mut seed = [0; 16];
        if randomize {
            thread_rng().fill_bytes(&mut seed);
        }
        Self::new_with_seed(graph, target_heads, seed, respect_size, randomize)
    }

    pub fn new_with_seed(
        graph: G,
        target_heads: Vec<Revision>,
        seed: Seed,
        respect_size: bool,
        randomize: bool,
    ) -> Self {
        PartialDiscovery {
            undecided: None,
            children_cache: None,
            target_heads: Some(target_heads),
            graph: graph.clone(),
            common: MissingAncestors::new(graph, vec![]),
            missing: HashSet::new(),
            rng: Rng::from_seed(seed),
            respect_size,
            randomize,
        }
    }

    /// Extract at most `size` random elements from sample and return them
    /// as a vector
    fn limit_sample(
        &mut self,
        mut sample: Vec<Revision>,
        size: usize,
    ) -> Vec<Revision> {
        if !self.randomize {
            sample.sort();
            sample.truncate(size);
            return sample;
        }
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
        let before_len = self.common.get_bases().len();
        self.common.add_bases(common);
        if self.common.get_bases().len() == before_len {
            return Ok(());
        }
        if let Some(ref mut undecided) = self.undecided {
            self.common.remove_ancestors_from(undecided)?;
        }
        Ok(())
    }

    /// Register revisions known as being missing
    ///
    /// # Performance note
    ///
    /// Except in the most trivial case, the first call of this method has
    /// the side effect of computing `self.undecided` set for the first time,
    /// and the related caches it might need for efficiency of its internal
    /// computation. This is typically faster if more information is
    /// available in `self.common`. Therefore, for good performance, the
    /// caller should avoid calling this too early.
    pub fn add_missing_revisions(
        &mut self,
        missing: impl IntoIterator<Item = Revision>,
    ) -> Result<(), GraphError> {
        let mut tovisit: VecDeque<Revision> = missing.into_iter().collect();
        if tovisit.is_empty() {
            return Ok(());
        }
        self.ensure_children_cache()?;
        self.ensure_undecided()?; // for safety of possible future refactors
        let children = self.children_cache.as_ref().unwrap();
        let mut seen: HashSet<Revision> = HashSet::new();
        let undecided_mut = self.undecided.as_mut().unwrap();
        while let Some(rev) = tovisit.pop_front() {
            if !self.missing.insert(rev) {
                // either it's known to be missing from a previous
                // invocation, and there's no need to iterate on its
                // children (we now they are all missing)
                // or it's from a previous iteration of this loop
                // and its children have already been queued
                continue;
            }
            undecided_mut.remove(&rev);
            match children.get(&rev) {
                None => {
                    continue;
                }
                Some(this_children) => {
                    for child in this_children.iter().cloned() {
                        if seen.insert(child) {
                            tovisit.push_back(child);
                        }
                    }
                }
            }
        }
        Ok(())
    }

    /// Do we have any information about the peer?
    pub fn has_info(&self) -> bool {
        self.common.has_bases()
    }

    /// Did we acquire full knowledge of our Revisions that the peer has?
    pub fn is_complete(&self) -> bool {
        self.undecided.as_ref().map_or(false, HashSet::is_empty)
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

    fn ensure_children_cache(&mut self) -> Result<(), GraphError> {
        if self.children_cache.is_some() {
            return Ok(());
        }
        self.ensure_undecided()?;

        let mut children: FastHashMap<Revision, Vec<Revision>> =
            FastHashMap::default();
        for &rev in self.undecided.as_ref().unwrap() {
            for p in ParentsIterator::graph_parents(&self.graph, rev)? {
                children.entry(p).or_insert_with(Vec::new).push(rev);
            }
        }
        self.children_cache = Some(children);
        Ok(())
    }

    /// Provide statistics about the current state of the discovery process
    pub fn stats(&self) -> DiscoveryStats {
        DiscoveryStats {
            undecided: self.undecided.as_ref().map(HashSet::len),
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
            |r| ParentsIterator::graph_parents(&self.graph, r),
            Some(size),
        )?;
        Ok(sample.into_iter().collect())
    }

    /// Extract a sample from `self.undecided`, going from its heads and roots.
    ///
    /// The `size` parameter is used to avoid useless computations if
    /// it turns out to be bigger than the whole set of undecided Revisions.
    ///
    /// The sample is taken by using `update_sample` from the heads, then
    /// from the roots, working on the reverse DAG,
    /// expressed by `self.children_cache`.
    ///
    /// No effort is being made to complete or limit the sample to `size`
    /// but this method returns another interesting size that it derives
    /// from its knowledge of the structure of the various sets, leaving
    /// to the caller the decision to use it or not.
    fn bidirectional_sample(
        &mut self,
        size: usize,
    ) -> Result<(HashSet<Revision>, usize), GraphError> {
        self.ensure_undecided()?;
        {
            // we don't want to compute children_cache before this
            // but doing it after extracting self.undecided takes a mutable
            // ref to self while a shareable one is still active.
            let undecided = self.undecided.as_ref().unwrap();
            if undecided.len() <= size {
                return Ok((undecided.clone(), size));
            }
        }

        self.ensure_children_cache()?;
        let revs = self.undecided.as_ref().unwrap();
        let mut sample: HashSet<Revision> = revs.clone();

        // it's possible that leveraging the children cache would be more
        // efficient here
        dagops::retain_heads(&self.graph, &mut sample)?;
        let revsheads = sample.clone(); // was again heads(revs) in python

        // update from heads
        update_sample(
            Some(revs),
            revsheads.iter().cloned(),
            &mut sample,
            |r| ParentsIterator::graph_parents(&self.graph, r),
            None,
        )?;

        // update from roots
        let revroots: HashSet<Revision> =
            dagops::roots(&self.graph, revs)?.into_iter().collect();
        let prescribed_size = max(size, min(revroots.len(), revsheads.len()));

        let children = self.children_cache.as_ref().unwrap();
        let empty_vec: Vec<Revision> = Vec::new();
        update_sample(
            Some(revs),
            revroots,
            &mut sample,
            |r| Ok(children.get(&r).unwrap_or(&empty_vec).iter().cloned()),
            None,
        )?;
        Ok((sample, prescribed_size))
    }

    /// Fill up sample up to the wished size with random undecided Revisions.
    ///
    /// This is intended to be used as a last resort completion if the
    /// regular sampling algorithm returns too few elements.
    fn random_complete_sample(
        &mut self,
        sample: &mut Vec<Revision>,
        size: usize,
    ) {
        let sample_len = sample.len();
        if size <= sample_len {
            return;
        }
        let take_from: Vec<Revision> = self
            .undecided
            .as_ref()
            .unwrap()
            .iter()
            .filter(|&r| !sample.contains(r))
            .cloned()
            .collect();
        sample.extend(self.limit_sample(take_from, size - sample_len));
    }

    pub fn take_full_sample(
        &mut self,
        size: usize,
    ) -> Result<Vec<Revision>, GraphError> {
        let (sample_set, prescribed_size) = self.bidirectional_sample(size)?;
        let size = if self.respect_size {
            size
        } else {
            prescribed_size
        };
        let mut sample =
            self.limit_sample(sample_set.into_iter().collect(), size);
        self.random_complete_sample(&mut sample, size);
        Ok(sample)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::SampleGraph;

    /// A PartialDiscovery as for pushing all the heads of `SampleGraph`
    ///
    /// To avoid actual randomness in these tests, we give it a fixed
    /// random seed, but by default we'll test the random version.
    fn full_disco() -> PartialDiscovery<SampleGraph> {
        PartialDiscovery::new_with_seed(
            SampleGraph,
            vec![10, 11, 12, 13],
            [0; 16],
            true,
            true,
        )
    }

    /// A PartialDiscovery as for pushing the 12 head of `SampleGraph`
    ///
    /// To avoid actual randomness in tests, we give it a fixed random seed.
    fn disco12() -> PartialDiscovery<SampleGraph> {
        PartialDiscovery::new_with_seed(
            SampleGraph,
            vec![12],
            [0; 16],
            true,
            true,
        )
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
    fn test_add_missing_early_continue() -> Result<(), GraphError> {
        eprintln!("test_add_missing_early_stop");
        let mut disco = full_disco();
        disco.add_common_revisions(vec![13, 3, 4])?;
        disco.ensure_children_cache()?;
        // 12 is grand-child of 6 through 9
        // passing them in this order maximizes the chances of the
        // early continue to do the wrong thing
        disco.add_missing_revisions(vec![6, 9, 12])?;
        assert_eq!(sorted_undecided(&disco), vec![5, 7, 10, 11]);
        assert_eq!(sorted_missing(&disco), vec![6, 9, 12]);
        assert!(!disco.is_complete());
        Ok(())
    }

    #[test]
    fn test_limit_sample_no_need_to() {
        let sample = vec![1, 2, 3, 4];
        assert_eq!(full_disco().limit_sample(sample, 10), vec![1, 2, 3, 4]);
    }

    #[test]
    fn test_limit_sample_less_than_half() {
        assert_eq!(full_disco().limit_sample((1..6).collect(), 2), vec![2, 5]);
    }

    #[test]
    fn test_limit_sample_more_than_half() {
        assert_eq!(full_disco().limit_sample((1..4).collect(), 2), vec![1, 2]);
    }

    #[test]
    fn test_limit_sample_no_random() {
        let mut disco = full_disco();
        disco.randomize = false;
        assert_eq!(
            disco.limit_sample(vec![1, 8, 13, 5, 7, 3], 4),
            vec![1, 3, 5, 7]
        );
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

    #[test]
    fn test_children_cache() -> Result<(), GraphError> {
        let mut disco = full_disco();
        disco.ensure_children_cache()?;

        let cache = disco.children_cache.unwrap();
        assert_eq!(cache.get(&2).cloned(), Some(vec![4]));
        assert_eq!(cache.get(&10).cloned(), None);

        let mut children_4 = cache.get(&4).cloned().unwrap();
        children_4.sort();
        assert_eq!(children_4, vec![5, 6, 7]);

        let mut children_7 = cache.get(&7).cloned().unwrap();
        children_7.sort();
        assert_eq!(children_7, vec![9, 11]);

        Ok(())
    }

    #[test]
    fn test_complete_sample() {
        let mut disco = full_disco();
        let undecided: HashSet<Revision> =
            [4, 7, 9, 2, 3].iter().cloned().collect();
        disco.undecided = Some(undecided);

        let mut sample = vec![0];
        disco.random_complete_sample(&mut sample, 3);
        assert_eq!(sample.len(), 3);

        let mut sample = vec![2, 4, 7];
        disco.random_complete_sample(&mut sample, 1);
        assert_eq!(sample.len(), 3);
    }

    #[test]
    fn test_bidirectional_sample() -> Result<(), GraphError> {
        let mut disco = full_disco();
        disco.undecided = Some((0..=13).into_iter().collect());

        let (sample_set, size) = disco.bidirectional_sample(7)?;
        assert_eq!(size, 7);
        let mut sample: Vec<Revision> = sample_set.into_iter().collect();
        sample.sort();
        // our DAG is a bit too small for the results to be really interesting
        // at least it shows that
        // - we went both ways
        // - we didn't take all Revisions (6 is not in the sample)
        assert_eq!(sample, vec![0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13]);
        Ok(())
    }
}

use hg::testing::VecGraph;
use hg::Revision;
use hg::*;
use rand::distributions::{Distribution, Uniform};
use rand::{thread_rng, Rng, RngCore, SeedableRng};
use rand_distr::LogNormal;
use std::cmp::min;
use std::collections::HashSet;
use std::env;
use std::fmt::Debug;

fn build_random_graph(
    nodes_opt: Option<usize>,
    rootprob_opt: Option<f64>,
    mergeprob_opt: Option<f64>,
    prevprob_opt: Option<f64>,
) -> VecGraph {
    let nodes = nodes_opt.unwrap_or(100);
    let rootprob = rootprob_opt.unwrap_or(0.05);
    let mergeprob = mergeprob_opt.unwrap_or(0.2);
    let prevprob = prevprob_opt.unwrap_or(0.7);

    let mut rng = thread_rng();
    let mut vg: VecGraph = Vec::with_capacity(nodes);
    for i in 0..nodes {
        if i == 0 || rng.gen_bool(rootprob) {
            vg.push([NULL_REVISION, NULL_REVISION])
        } else if i == 1 {
            vg.push([0, NULL_REVISION])
        } else if rng.gen_bool(mergeprob) {
            let p1 = {
                if i == 2 || rng.gen_bool(prevprob) {
                    (i - 1) as Revision
                } else {
                    rng.gen_range(0..i - 1) as Revision
                }
            };
            // p2 is a random revision lower than i and different from p1
            let mut p2 = rng.gen_range(0..i - 1) as Revision;
            if p2 >= p1 {
                p2 = p2 + 1;
            }
            vg.push([p1, p2]);
        } else if rng.gen_bool(prevprob) {
            vg.push([(i - 1) as Revision, NULL_REVISION])
        } else {
            vg.push([rng.gen_range(0..i - 1) as Revision, NULL_REVISION])
        }
    }
    vg
}

/// Compute the ancestors set of all revisions of a VecGraph
fn ancestors_sets(vg: &VecGraph) -> Vec<HashSet<Revision>> {
    let mut ancs: Vec<HashSet<Revision>> = Vec::new();
    for i in 0..vg.len() {
        let mut ancs_i = HashSet::new();
        ancs_i.insert(i as Revision);
        for p in vg[i].iter().cloned() {
            if p != NULL_REVISION {
                ancs_i.extend(&ancs[p as usize]);
            }
        }
        ancs.push(ancs_i);
    }
    ancs
}

#[derive(Clone, Debug)]
enum MissingAncestorsAction {
    InitialBases(HashSet<Revision>),
    AddBases(HashSet<Revision>),
    RemoveAncestorsFrom(HashSet<Revision>),
    MissingAncestors(HashSet<Revision>),
}

/// An instrumented naive yet obviously correct implementation
///
/// It also records all its actions for easy reproduction for replay
/// of problematic cases
struct NaiveMissingAncestors<'a> {
    ancestors_sets: &'a Vec<HashSet<Revision>>,
    graph: &'a VecGraph, // used for error reporting only
    bases: HashSet<Revision>,
    history: Vec<MissingAncestorsAction>,
    // for error reporting, assuming we are in a random test
    random_seed: String,
}

impl<'a> NaiveMissingAncestors<'a> {
    fn new(
        graph: &'a VecGraph,
        ancestors_sets: &'a Vec<HashSet<Revision>>,
        bases: &HashSet<Revision>,
        random_seed: &str,
    ) -> Self {
        Self {
            ancestors_sets: ancestors_sets,
            bases: bases.clone(),
            graph: graph,
            history: vec![MissingAncestorsAction::InitialBases(bases.clone())],
            random_seed: random_seed.into(),
        }
    }

    fn add_bases(&mut self, new_bases: HashSet<Revision>) {
        self.bases.extend(&new_bases);
        self.history
            .push(MissingAncestorsAction::AddBases(new_bases))
    }

    fn remove_ancestors_from(&mut self, revs: &mut HashSet<Revision>) {
        revs.remove(&NULL_REVISION);
        self.history
            .push(MissingAncestorsAction::RemoveAncestorsFrom(revs.clone()));
        for base in self.bases.iter().cloned() {
            if base != NULL_REVISION {
                for rev in &self.ancestors_sets[base as usize] {
                    revs.remove(&rev);
                }
            }
        }
    }

    fn missing_ancestors(
        &mut self,
        revs: impl IntoIterator<Item = Revision>,
    ) -> Vec<Revision> {
        let revs_as_set: HashSet<Revision> = revs.into_iter().collect();

        let mut missing: HashSet<Revision> = HashSet::new();
        for rev in revs_as_set.iter().cloned() {
            if rev != NULL_REVISION {
                missing.extend(&self.ancestors_sets[rev as usize])
            }
        }
        self.history
            .push(MissingAncestorsAction::MissingAncestors(revs_as_set));

        for base in self.bases.iter().cloned() {
            if base != NULL_REVISION {
                for rev in &self.ancestors_sets[base as usize] {
                    missing.remove(&rev);
                }
            }
        }
        let mut res: Vec<Revision> = missing.iter().cloned().collect();
        res.sort();
        res
    }

    fn assert_eq<T>(&self, left: T, right: T)
    where
        T: PartialEq + Debug,
    {
        if left == right {
            return;
        }
        panic!(
            "Equality assertion failed (left != right)
                left={:?}
                right={:?}
                graph={:?}
                current bases={:?}
                history={:?}
                random seed={}
            ",
            left,
            right,
            self.graph,
            self.bases,
            self.history,
            self.random_seed,
        );
    }
}

/// Choose a set of random revisions
///
/// The size of the set is taken from a LogNormal distribution
/// with default mu=1.1 and default sigma=0.8. Quoting the Python
/// test this is taken from:
///     the default mu and sigma give us a nice distribution of mostly
///     single-digit counts (including 0) with some higher ones
/// The sample may include NULL_REVISION
fn sample_revs<R: RngCore>(
    rng: &mut R,
    maxrev: Revision,
    mu_opt: Option<f64>,
    sigma_opt: Option<f64>,
) -> HashSet<Revision> {
    let mu = mu_opt.unwrap_or(1.1);
    let sigma = sigma_opt.unwrap_or(0.8);

    let log_normal = LogNormal::new(mu, sigma).unwrap();
    let nb = min(maxrev as usize, log_normal.sample(rng).floor() as usize);

    let dist = Uniform::from(NULL_REVISION..maxrev);
    return rng.sample_iter(&dist).take(nb).collect();
}

/// Produces the hexadecimal representation of a slice of bytes
fn hex_bytes(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{:x}", b));
    }
    s
}

/// Fill a random seed from its hexadecimal representation.
///
/// This signature is meant to be consistent with `RngCore::fill_bytes`
fn seed_parse_in(hex: &str, seed: &mut [u8]) {
    if hex.len() != 32 {
        panic!("Seed {} is too short for 128 bits hex", hex);
    }
    for i in 0..8 {
        seed[i] = u8::from_str_radix(&hex[2 * i..2 * (i + 1)], 16)
            .unwrap_or_else(|_e| panic!("Seed {} is not 128 bits hex", hex));
    }
}

/// Parse the parameters for `test_missing_ancestors()`
///
/// Returns (graphs, instances, calls per instance)
fn parse_test_missing_ancestors_params(var: &str) -> (usize, usize, usize) {
    let err_msg = "TEST_MISSING_ANCESTORS format: GRAPHS,INSTANCES,CALLS";
    let params: Vec<usize> = var
        .split(',')
        .map(|n| n.trim().parse().expect(err_msg))
        .collect();
    if params.len() != 3 {
        panic!("{}", err_msg);
    }
    (params[0], params[1], params[2])
}

#[test]
/// This test creates lots of random VecGraphs,
/// and compare a bunch of MissingAncestors for them with
/// NaiveMissingAncestors that rely on precomputed transitive closures of
/// these VecGraphs (ancestors_sets).
///
/// For each generater graph, several instances of `MissingAncestors` are
/// created, whose methods are called and checked a given number of times.
///
/// This test can be parametrized by two environment variables:
///
/// - TEST_RANDOM_SEED: must be 128 bits in hexadecimal
/// - TEST_MISSING_ANCESTORS: "GRAPHS,INSTANCES,CALLS". The default is
///   "100,10,10"
///
/// This is slow: it runs on my workstation in about 5 seconds with the
/// default parameters with a plain `cargo --test`.
///
/// If you want to run it faster, especially if you're changing the
/// parameters, use `cargo test --release`.
/// For me, that gets it down to 0.15 seconds with the default parameters
fn test_missing_ancestors_compare_naive() {
    let (graphcount, testcount, inccount) =
        match env::var("TEST_MISSING_ANCESTORS") {
            Err(env::VarError::NotPresent) => (100, 10, 10),
            Ok(val) => parse_test_missing_ancestors_params(&val),
            Err(env::VarError::NotUnicode(_)) => {
                panic!("TEST_MISSING_ANCESTORS is invalid");
            }
        };
    let mut seed: [u8; 16] = [0; 16];
    match env::var("TEST_RANDOM_SEED") {
        Ok(val) => {
            seed_parse_in(&val, &mut seed);
        }
        Err(env::VarError::NotPresent) => {
            thread_rng().fill_bytes(&mut seed);
        }
        Err(env::VarError::NotUnicode(_)) => {
            panic!("TEST_RANDOM_SEED must be 128 bits in hex");
        }
    }
    let hex_seed = hex_bytes(&seed);
    eprintln!("Random seed: {}", hex_seed);

    let mut rng = rand_pcg::Pcg32::from_seed(seed);

    eprint!("Checking MissingAncestors against brute force implementation ");
    eprint!("for {} random graphs, ", graphcount);
    eprintln!(
        "with {} instances for each and {} calls per instance",
        testcount, inccount,
    );
    for g in 0..graphcount {
        if g != 0 && g % 100 == 0 {
            eprintln!("Tested with {} graphs", g);
        }
        let graph = build_random_graph(None, None, None, None);
        let graph_len = graph.len() as Revision;
        let ancestors_sets = ancestors_sets(&graph);
        for _testno in 0..testcount {
            let bases: HashSet<Revision> =
                sample_revs(&mut rng, graph_len, None, None);
            let mut inc = MissingAncestors::<VecGraph>::new(
                graph.clone(),
                bases.clone(),
            );
            let mut naive = NaiveMissingAncestors::new(
                &graph,
                &ancestors_sets,
                &bases,
                &hex_seed,
            );
            for _m in 0..inccount {
                if rng.gen_bool(0.2) {
                    let new_bases =
                        sample_revs(&mut rng, graph_len, None, None);
                    inc.add_bases(new_bases.iter().cloned());
                    naive.add_bases(new_bases);
                }
                if rng.gen_bool(0.4) {
                    // larger set so that there are more revs to remove from
                    let mut hrevs =
                        sample_revs(&mut rng, graph_len, Some(1.5), None);
                    let mut rrevs = hrevs.clone();
                    inc.remove_ancestors_from(&mut hrevs).unwrap();
                    naive.remove_ancestors_from(&mut rrevs);
                    naive.assert_eq(hrevs, rrevs);
                } else {
                    let revs = sample_revs(&mut rng, graph_len, None, None);
                    let hm =
                        inc.missing_ancestors(revs.iter().cloned()).unwrap();
                    let rm = naive.missing_ancestors(revs.iter().cloned());
                    naive.assert_eq(hm, rm);
                }
            }
        }
    }
}

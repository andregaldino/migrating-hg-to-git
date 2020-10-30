use crate::utils::hg_path::HgPath;
use crate::utils::hg_path::HgPathBuf;
use crate::Revision;

use im_rc::ordmap::DiffItem;
use im_rc::ordmap::OrdMap;

use std::collections::HashMap;
use std::collections::HashSet;

pub type PathCopies = HashMap<HgPathBuf, HgPathBuf>;

#[derive(Clone, Debug, PartialEq)]
struct TimeStampedPathCopy {
    /// revision at which the copy information was added
    rev: Revision,
    /// the copy source, (Set to None in case of deletion of the associated
    /// key)
    path: Option<HgPathBuf>,
}

/// maps CopyDestination to Copy Source (+ a "timestamp" for the operation)
type TimeStampedPathCopies = OrdMap<HgPathBuf, TimeStampedPathCopy>;

/// hold parent 1, parent 2 and relevant files actions.
pub type RevInfo = (Revision, Revision, ChangedFiles);

/// represent the files affected by a changesets
///
/// This hold a subset of mercurial.metadata.ChangingFiles as we do not need
/// all the data categories tracked by it.
pub struct ChangedFiles {
    removed: HashSet<HgPathBuf>,
    merged: HashSet<HgPathBuf>,
    salvaged: HashSet<HgPathBuf>,
    copied_from_p1: PathCopies,
    copied_from_p2: PathCopies,
}

/// Represent active changes that affect the copy tracing.
enum Action<'a> {
    /// The parent ? children edge is removing a file
    ///
    /// (actually, this could be the edge from the other parent, but it does
    /// not matters)
    Removed(&'a HgPath),
    /// The parent ? children edge introduce copy information between (dest,
    /// source)
    Copied(&'a HgPath, &'a HgPath),
}

impl ChangedFiles {
    pub fn new(
        removed: HashSet<HgPathBuf>,
        merged: HashSet<HgPathBuf>,
        salvaged: HashSet<HgPathBuf>,
        copied_from_p1: PathCopies,
        copied_from_p2: PathCopies,
    ) -> Self {
        ChangedFiles {
            removed,
            merged,
            salvaged,
            copied_from_p1,
            copied_from_p2,
        }
    }

    pub fn new_empty() -> Self {
        ChangedFiles {
            removed: HashSet::new(),
            merged: HashSet::new(),
            salvaged: HashSet::new(),
            copied_from_p1: PathCopies::new(),
            copied_from_p2: PathCopies::new(),
        }
    }

    /// Return an iterator over all the `Action` in this instance.
    fn iter_actions(&self, parent: usize) -> impl Iterator<Item = Action> {
        let copies_iter = match parent {
            1 => self.copied_from_p1.iter(),
            2 => self.copied_from_p2.iter(),
            _ => unreachable!(),
        };
        let remove_iter = self.removed.iter();
        let copies_iter = copies_iter.map(|(x, y)| Action::Copied(x, y));
        let remove_iter = remove_iter.map(|x| Action::Removed(x));
        copies_iter.chain(remove_iter)
    }
}

/// A struct responsible for answering "is X ancestors of Y" quickly
///
/// The structure will delegate ancestors call to a callback, and cache the
/// result.
#[derive(Debug)]
struct AncestorOracle<'a, A: Fn(Revision, Revision) -> bool> {
    inner: &'a A,
    pairs: HashMap<(Revision, Revision), bool>,
}

impl<'a, A: Fn(Revision, Revision) -> bool> AncestorOracle<'a, A> {
    fn new(func: &'a A) -> Self {
        Self {
            inner: func,
            pairs: HashMap::default(),
        }
    }

    /// returns `true` if `anc` is an ancestors of `desc`, `false` otherwise
    fn is_ancestor(&mut self, anc: Revision, desc: Revision) -> bool {
        if anc > desc {
            false
        } else if anc == desc {
            true
        } else {
            if let Some(b) = self.pairs.get(&(anc, desc)) {
                *b
            } else {
                let b = (self.inner)(anc, desc);
                self.pairs.insert((anc, desc), b);
                b
            }
        }
    }
}

/// Same as mercurial.copies._combine_changeset_copies, but in Rust.
///
/// Arguments are:
///
/// revs: all revisions to be considered
/// children: a {parent ? [childrens]} mapping
/// target_rev: the final revision we are combining copies to
/// rev_info(rev): callback to get revision information:
///   * first parent
///   * second parent
///   * ChangedFiles
/// isancestors(low_rev, high_rev): callback to check if a revision is an
///                                 ancestor of another
pub fn combine_changeset_copies<A: Fn(Revision, Revision) -> bool>(
    revs: Vec<Revision>,
    children: HashMap<Revision, Vec<Revision>>,
    target_rev: Revision,
    rev_info: &impl Fn(Revision) -> RevInfo,
    is_ancestor: &A,
) -> PathCopies {
    let mut all_copies = HashMap::new();
    let mut oracle = AncestorOracle::new(is_ancestor);

    for rev in revs {
        // Retrieve data computed in a previous iteration
        let copies = all_copies.remove(&rev);
        let copies = match copies {
            Some(c) => c,
            None => TimeStampedPathCopies::default(), // root of the walked set
        };

        let current_children = match children.get(&rev) {
            Some(c) => c,
            None => panic!("inconsistent `revs` and `children`"),
        };

        for child in current_children {
            // We will chain the copies information accumulated for `rev` with
            // the individual copies information for each of its children.
            // Creating a new PathCopies for each `rev` ? `children` vertex.
            let (p1, p2, changes) = rev_info(*child);

            let parent = if rev == p1 {
                1
            } else {
                assert_eq!(rev, p2);
                2
            };
            let mut new_copies = copies.clone();

            for action in changes.iter_actions(parent) {
                match action {
                    Action::Copied(dest, source) => {
                        let entry;
                        if let Some(v) = copies.get(source) {
                            entry = match &v.path {
                                Some(path) => Some((*(path)).to_owned()),
                                None => Some(source.to_owned()),
                            }
                        } else {
                            entry = Some(source.to_owned());
                        }
                        // Each new entry is introduced by the children, we
                        // record this information as we will need it to take
                        // the right decision when merging conflicting copy
                        // information. See merge_copies_dict for details.
                        let ttpc = TimeStampedPathCopy {
                            rev: *child,
                            path: entry,
                        };
                        new_copies.insert(dest.to_owned(), ttpc);
                    }
                    Action::Removed(f) => {
                        // We must drop copy information for removed file.
                        //
                        // We need to explicitly record them as dropped to
                        // propagate this information when merging two
                        // TimeStampedPathCopies object.
                        if new_copies.contains_key(f.as_ref()) {
                            let ttpc = TimeStampedPathCopy {
                                rev: *child,
                                path: None,
                            };
                            new_copies.insert(f.to_owned(), ttpc);
                        }
                    }
                }
            }

            // Merge has two parents needs to combines their copy information.
            //
            // If the vertex from the other parent was already processed, we
            // will have a value for the child ready to be used. We need to
            // grab it and combine it with the one we already
            // computed. If not we can simply store the newly
            // computed data. The processing happening at
            // the time of the second parent will take care of combining the
            // two TimeStampedPathCopies instance.
            match all_copies.remove(child) {
                None => {
                    all_copies.insert(child, new_copies);
                }
                Some(other_copies) => {
                    let (minor, major) = match parent {
                        1 => (other_copies, new_copies),
                        2 => (new_copies, other_copies),
                        _ => unreachable!(),
                    };
                    let merged_copies =
                        merge_copies_dict(minor, major, &changes, &mut oracle);
                    all_copies.insert(child, merged_copies);
                }
            };
        }
    }

    // Drop internal information (like the timestamp) and return the final
    // mapping.
    let tt_result = all_copies
        .remove(&target_rev)
        .expect("target revision was not processed");
    let mut result = PathCopies::default();
    for (dest, tt_source) in tt_result {
        if let Some(path) = tt_source.path {
            result.insert(dest, path);
        }
    }
    result
}

/// merge two copies-mapping together, minor and major
///
/// In case of conflict, value from "major" will be picked, unless in some
/// cases. See inline documentation for details.
#[allow(clippy::if_same_then_else)]
fn merge_copies_dict<A: Fn(Revision, Revision) -> bool>(
    minor: TimeStampedPathCopies,
    major: TimeStampedPathCopies,
    changes: &ChangedFiles,
    oracle: &mut AncestorOracle<A>,
) -> TimeStampedPathCopies {
    if minor.is_empty() {
        return major;
    } else if major.is_empty() {
        return minor;
    }
    let mut override_minor = Vec::new();
    let mut override_major = Vec::new();

    let mut to_major = |k: &HgPathBuf, v: &TimeStampedPathCopy| {
        override_major.push((k.clone(), v.clone()))
    };
    let mut to_minor = |k: &HgPathBuf, v: &TimeStampedPathCopy| {
        override_minor.push((k.clone(), v.clone()))
    };

    // The diff function leverage detection of the identical subpart if minor
    // and major has some common ancestors. This make it very fast is most
    // case.
    //
    // In case where the two map are vastly different in size, the current
    // approach is still slowish because the iteration will iterate over
    // all the "exclusive" content of the larger on. This situation can be
    // frequent when the subgraph of revision we are processing has a lot
    // of roots. Each roots adding they own fully new map to the mix (and
    // likely a small map, if the path from the root to the "main path" is
    // small.
    //
    // We could do better by detecting such situation and processing them
    // differently.
    for d in minor.diff(&major) {
        match d {
            DiffItem::Add(k, v) => to_minor(k, v),
            DiffItem::Remove(k, v) => to_major(k, v),
            DiffItem::Update { old, new } => {
                let (dest, src_major) = new;
                let (_, src_minor) = old;
                let mut pick_minor = || (to_major(dest, src_minor));
                let mut pick_major = || (to_minor(dest, src_major));
                if src_major.path == src_minor.path {
                    // we have the same value, but from other source;
                    if src_major.rev == src_minor.rev {
                        // If the two entry are identical, no need to do
                        // anything (but diff should not have yield them)
                        unreachable!();
                    } else if oracle.is_ancestor(src_major.rev, src_minor.rev)
                    {
                        pick_minor();
                    } else {
                        pick_major();
                    }
                } else if src_major.rev == src_minor.rev {
                    // We cannot get copy information for both p1 and p2 in the
                    // same rev. So this is the same value.
                    unreachable!();
                } else {
                    if src_major.path.is_none()
                        && changes.salvaged.contains(dest)
                    {
                        // If the file is "deleted" in the major side but was
                        // salvaged by the merge, we keep the minor side alive
                        pick_minor();
                    } else if src_minor.path.is_none()
                        && changes.salvaged.contains(dest)
                    {
                        // If the file is "deleted" in the minor side but was
                        // salvaged by the merge, unconditionnaly preserve the
                        // major side.
                        pick_major();
                    } else if changes.merged.contains(dest) {
                        // If the file was actively merged, copy information
                        // from each side might conflict.  The major side will
                        // win such conflict.
                        pick_major();
                    } else if oracle.is_ancestor(src_major.rev, src_minor.rev)
                    {
                        // If the minor side is strictly newer than the major
                        // side, it should be kept.
                        pick_minor();
                    } else if src_major.path.is_some() {
                        // without any special case, the "major" value win
                        // other the "minor" one.
                        pick_major();
                    } else if oracle.is_ancestor(src_minor.rev, src_major.rev)
                    {
                        // the "major" rev is a direct ancestors of "minor",
                        // any different value should
                        // overwrite
                        pick_major();
                    } else {
                        // major version is None (so the file was deleted on
                        // that branch) and that branch is independant (neither
                        // minor nor major is an ancestors of the other one.)
                        // We preserve the new
                        // information about the new file.
                        pick_minor();
                    }
                }
            }
        };
    }

    let updates;
    let mut result;
    if override_major.is_empty() {
        result = major
    } else if override_minor.is_empty() {
        result = minor
    } else {
        if override_minor.len() < override_major.len() {
            updates = override_minor;
            result = minor;
        } else {
            updates = override_major;
            result = major;
        }
        for (k, v) in updates {
            result.insert(k, v);
        }
    }
    result
}

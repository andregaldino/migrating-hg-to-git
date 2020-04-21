use crate::utils::hg_path::HgPathBuf;
use crate::Revision;

use im_rc::ordmap::OrdMap;

use std::collections::HashMap;
use std::collections::HashSet;

pub type PathCopies = HashMap<HgPathBuf, HgPathBuf>;

#[derive(Clone, Debug)]
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
pub fn combine_changeset_copies(
    revs: Vec<Revision>,
    children: HashMap<Revision, Vec<Revision>>,
    target_rev: Revision,
    rev_info: &impl Fn(Revision) -> RevInfo,
    is_ancestor: &impl Fn(Revision, Revision) -> bool,
) -> PathCopies {
    let mut all_copies = HashMap::new();

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

            let (parent, child_copies) = if rev == p1 {
                (1, &changes.copied_from_p1)
            } else {
                assert_eq!(rev, p2);
                (2, &changes.copied_from_p2)
            };
            let mut new_copies = copies.clone();

            for (dest, source) in child_copies {
                let entry;
                if let Some(v) = copies.get(source) {
                    entry = match &v.path {
                        Some(path) => Some((*(path)).to_owned()),
                        None => Some(source.to_owned()),
                    }
                } else {
                    entry = Some(source.to_owned());
                }
                // Each new entry is introduced by the children, we record this
                // information as we will need it to take the right decision
                // when merging conflicting copy information. See
                // merge_copies_dict for details.
                let ttpc = TimeStampedPathCopy {
                    rev: *child,
                    path: entry,
                };
                new_copies.insert(dest.to_owned(), ttpc);
            }

            // We must drop copy information for removed file.
            //
            // We need to explicitly record them as dropped to propagate this
            // information when merging two TimeStampedPathCopies object.
            for f in changes.removed.iter() {
                if new_copies.contains_key(f.as_ref()) {
                    let ttpc = TimeStampedPathCopy {
                        rev: *child,
                        path: None,
                    };
                    new_copies.insert(f.to_owned(), ttpc);
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
                        merge_copies_dict(minor, major, &changes, is_ancestor);
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
fn merge_copies_dict(
    minor: TimeStampedPathCopies,
    major: TimeStampedPathCopies,
    changes: &ChangedFiles,
    is_ancestor: &impl Fn(Revision, Revision) -> bool,
) -> TimeStampedPathCopies {
    let mut result = minor.clone();
    for (dest, src_major) in major {
        let overwrite;
        if let Some(src_minor) = minor.get(&dest) {
            if src_major.path == src_minor.path {
                // we have the same value, but from other source;
                if src_major.rev == src_minor.rev {
                    // If the two entry are identical, no need to do anything
                    overwrite = false;
                } else if is_ancestor(src_major.rev, src_minor.rev) {
                    overwrite = false;
                } else {
                    overwrite = true;
                }
            } else if src_major.rev == src_minor.rev {
                // We cannot get copy information for both p1 and p2 in the
                // same rev. So this is the same value.
                overwrite = false;
            } else if src_major.path.is_none()
                && changes.salvaged.contains(&dest)
            {
                // If the file is "deleted" in the major side but was salvaged
                // by the merge, we keep the minor side alive
                overwrite = false;
            } else if src_minor.path.is_none()
                && changes.salvaged.contains(&dest)
            {
                // If the file is "deleted" in the minor side but was salvaged
                // by the merge, unconditionnaly preserve the major side.
                overwrite = true;
            } else if changes.merged.contains(&dest) {
                // If the file was actively merged, copy information from each
                // side might conflict. The major side will win such conflict.
                overwrite = true;
            } else if is_ancestor(src_major.rev, src_minor.rev) {
                // If the minor side is strictly newer than the major side, it
                // should be kept.
                overwrite = false;
            } else if src_major.path.is_some() {
                // without any special case, the "major" value win other the
                // "minor" one.
                overwrite = true;
            } else if is_ancestor(src_minor.rev, src_major.rev) {
                // the "major" rev is a direct ancestors of "minor", any
                // different value should overwrite
                overwrite = true;
            } else {
                // major version is None (so the file was deleted on that
                // branch) annd that branch is independant (neither minor nor
                // major is an ancestors of the other one.) We preserve the new
                // information about the new file.
                overwrite = false;
            }
        } else {
            // minor had no value
            overwrite = true;
        }
        if overwrite {
            result.insert(dest, src_major);
        }
    }
    result
}

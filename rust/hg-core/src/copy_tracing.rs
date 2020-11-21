use crate::utils::hg_path::HgPath;
use crate::utils::hg_path::HgPathBuf;
use crate::Revision;

use im_rc::ordmap::DiffItem;
use im_rc::ordmap::OrdMap;

use std::cmp::Ordering;
use std::collections::HashMap;
use std::convert::TryInto;

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
pub type RevInfo<'a> = (Revision, Revision, ChangedFiles<'a>);

/// represent the files affected by a changesets
///
/// This hold a subset of mercurial.metadata.ChangingFiles as we do not need
/// all the data categories tracked by it.
/// This hold a subset of mercurial.metadata.ChangingFiles as we do not need
/// all the data categories tracked by it.
pub struct ChangedFiles<'a> {
    nb_items: u32,
    index: &'a [u8],
    data: &'a [u8],
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

/// This express the possible "special" case we can get in a merge
///
/// See mercurial/metadata.py for details on these values.
#[derive(PartialEq)]
enum MergeCase {
    /// Merged: file had history on both side that needed to be merged
    Merged,
    /// Salvaged: file was candidate for deletion, but survived the merge
    Salvaged,
    /// Normal: Not one of the two cases above
    Normal,
}

type FileChange<'a> = (u8, &'a HgPath, &'a HgPath);

const EMPTY: &[u8] = b"";
const COPY_MASK: u8 = 3;
const P1_COPY: u8 = 2;
const P2_COPY: u8 = 3;
const ACTION_MASK: u8 = 28;
const REMOVED: u8 = 12;
const MERGED: u8 = 8;
const SALVAGED: u8 = 16;

impl<'a> ChangedFiles<'a> {
    const INDEX_START: usize = 4;
    const ENTRY_SIZE: u32 = 9;
    const FILENAME_START: u32 = 1;
    const COPY_SOURCE_START: u32 = 5;

    pub fn new(data: &'a [u8]) -> Self {
        assert!(
            data.len() >= 4,
            "data size ({}) is too small to contain the header (4)",
            data.len()
        );
        let nb_items_raw: [u8; 4] = (&data[0..=3])
            .try_into()
            .expect("failed to turn 4 bytes into 4 bytes");
        let nb_items = u32::from_be_bytes(nb_items_raw);

        let index_size = (nb_items * Self::ENTRY_SIZE) as usize;
        let index_end = Self::INDEX_START + index_size;

        assert!(
            data.len() >= index_end,
            "data size ({}) is too small to fit the index_data ({})",
            data.len(),
            index_end
        );

        let ret = ChangedFiles {
            nb_items,
            index: &data[Self::INDEX_START..index_end],
            data: &data[index_end..],
        };
        let max_data = ret.filename_end(nb_items - 1) as usize;
        assert!(
            ret.data.len() >= max_data,
            "data size ({}) is too small to fit all data ({})",
            data.len(),
            index_end + max_data
        );
        ret
    }

    pub fn new_empty() -> Self {
        ChangedFiles {
            nb_items: 0,
            index: EMPTY,
            data: EMPTY,
        }
    }

    /// internal function to return an individual entry at a given index
    fn entry(&'a self, idx: u32) -> FileChange<'a> {
        if idx >= self.nb_items {
            panic!(
                "index for entry is higher that the number of file {} >= {}",
                idx, self.nb_items
            )
        }
        let flags = self.flags(idx);
        let filename = self.filename(idx);
        let copy_idx = self.copy_idx(idx);
        let copy_source = self.filename(copy_idx);
        (flags, filename, copy_source)
    }

    /// internal function to return the filename of the entry at a given index
    fn filename(&self, idx: u32) -> &HgPath {
        let filename_start;
        if idx == 0 {
            filename_start = 0;
        } else {
            filename_start = self.filename_end(idx - 1)
        }
        let filename_end = self.filename_end(idx);
        let filename_start = filename_start as usize;
        let filename_end = filename_end as usize;
        HgPath::new(&self.data[filename_start..filename_end])
    }

    /// internal function to return the flag field of the entry at a given
    /// index
    fn flags(&self, idx: u32) -> u8 {
        let idx = idx as usize;
        self.index[idx * (Self::ENTRY_SIZE as usize)]
    }

    /// internal function to return the end of a filename part at a given index
    fn filename_end(&self, idx: u32) -> u32 {
        let start = (idx * Self::ENTRY_SIZE) + Self::FILENAME_START;
        let end = (idx * Self::ENTRY_SIZE) + Self::COPY_SOURCE_START;
        let start = start as usize;
        let end = end as usize;
        let raw = (&self.index[start..end])
            .try_into()
            .expect("failed to turn 4 bytes into 4 bytes");
        u32::from_be_bytes(raw)
    }

    /// internal function to return index of the copy source of the entry at a
    /// given index
    fn copy_idx(&self, idx: u32) -> u32 {
        let start = (idx * Self::ENTRY_SIZE) + Self::COPY_SOURCE_START;
        let end = (idx + 1) * Self::ENTRY_SIZE;
        let start = start as usize;
        let end = end as usize;
        let raw = (&self.index[start..end])
            .try_into()
            .expect("failed to turn 4 bytes into 4 bytes");
        u32::from_be_bytes(raw)
    }

    /// Return an iterator over all the `Action` in this instance.
    fn iter_actions(&self, parent: Parent) -> ActionsIterator {
        ActionsIterator {
            changes: &self,
            parent: parent,
            current: 0,
        }
    }

    /// return the MergeCase value associated with a filename
    fn get_merge_case(&self, path: &HgPath) -> MergeCase {
        if self.nb_items == 0 {
            return MergeCase::Normal;
        }
        let mut low_part = 0;
        let mut high_part = self.nb_items;

        while low_part < high_part {
            let cursor = (low_part + high_part - 1) / 2;
            let (flags, filename, _source) = self.entry(cursor);
            match path.cmp(filename) {
                Ordering::Less => low_part = cursor + 1,
                Ordering::Greater => high_part = cursor,
                Ordering::Equal => {
                    return match flags & ACTION_MASK {
                        MERGED => MergeCase::Merged,
                        SALVAGED => MergeCase::Salvaged,
                        _ => MergeCase::Normal,
                    };
                }
            }
        }
        MergeCase::Normal
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

struct ActionsIterator<'a> {
    changes: &'a ChangedFiles<'a>,
    parent: Parent,
    current: u32,
}

impl<'a> Iterator for ActionsIterator<'a> {
    type Item = Action<'a>;

    fn next(&mut self) -> Option<Action<'a>> {
        let copy_flag = match self.parent {
            Parent::FirstParent => P1_COPY,
            Parent::SecondParent => P2_COPY,
        };
        while self.current < self.changes.nb_items {
            let (flags, file, source) = self.changes.entry(self.current);
            self.current += 1;
            if (flags & ACTION_MASK) == REMOVED {
                return Some(Action::Removed(file));
            }
            let copy = flags & COPY_MASK;
            if copy == copy_flag {
                return Some(Action::Copied(file, source));
            }
        }
        return None;
    }
}

/// A small struct whose purpose is to ensure lifetime of bytes referenced in
/// ChangedFiles
///
/// It is passed to the RevInfoMaker callback who can assign any necessary
/// content to the `data` attribute. The copy tracing code is responsible for
/// keeping the DataHolder alive at least as long as the ChangedFiles object.
pub struct DataHolder<D> {
    /// RevInfoMaker callback should assign data referenced by the
    /// ChangedFiles struct it return to this attribute. The DataHolder
    /// lifetime will be at least as long as the ChangedFiles one.
    pub data: Option<D>,
}

pub type RevInfoMaker<'a, D> =
    Box<dyn for<'r> Fn(Revision, &'r mut DataHolder<D>) -> RevInfo<'r> + 'a>;

/// enum used to carry information about the parent → child currently processed
#[derive(Copy, Clone, Debug)]
enum Parent {
    /// The `p1(x) → x` edge
    FirstParent,
    /// The `p2(x) → x` edge
    SecondParent,
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
pub fn combine_changeset_copies<A: Fn(Revision, Revision) -> bool, D>(
    revs: Vec<Revision>,
    children: HashMap<Revision, Vec<Revision>>,
    target_rev: Revision,
    rev_info: RevInfoMaker<D>,
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
            // Creating a new PathCopies for each `rev` → `children` vertex.
            let mut d: DataHolder<D> = DataHolder { data: None };
            let (p1, p2, changes) = rev_info(*child, &mut d);

            let parent = if rev == p1 {
                Parent::FirstParent
            } else {
                assert_eq!(rev, p2);
                Parent::SecondParent
            };
            let new_copies =
                add_from_changes(&copies, &changes, parent, *child);

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
                        Parent::FirstParent => (other_copies, new_copies),
                        Parent::SecondParent => (new_copies, other_copies),
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

/// Combine ChangedFiles with some existing PathCopies information and return
/// the result
fn add_from_changes(
    base_copies: &TimeStampedPathCopies,
    changes: &ChangedFiles,
    parent: Parent,
    current_rev: Revision,
) -> TimeStampedPathCopies {
    let mut copies = base_copies.clone();
    for action in changes.iter_actions(parent) {
        match action {
            Action::Copied(dest, source) => {
                let entry;
                if let Some(v) = base_copies.get(source) {
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
                    rev: current_rev,
                    path: entry,
                };
                copies.insert(dest.to_owned(), ttpc);
            }
            Action::Removed(f) => {
                // We must drop copy information for removed file.
                //
                // We need to explicitly record them as dropped to
                // propagate this information when merging two
                // TimeStampedPathCopies object.
                if copies.contains_key(f.as_ref()) {
                    let ttpc = TimeStampedPathCopy {
                        rev: current_rev,
                        path: None,
                    };
                    copies.insert(f.to_owned(), ttpc);
                }
            }
        }
    }
    copies
}

/// merge two copies-mapping together, minor and major
///
/// In case of conflict, value from "major" will be picked, unless in some
/// cases. See inline documentation for details.
fn merge_copies_dict<A: Fn(Revision, Revision) -> bool>(
    mut minor: TimeStampedPathCopies,
    mut major: TimeStampedPathCopies,
    changes: &ChangedFiles,
    oracle: &mut AncestorOracle<A>,
) -> TimeStampedPathCopies {
    // This closure exist as temporary help while multiple developper are
    // actively working on this code. Feel free to re-inline it once this
    // code is more settled.
    let mut cmp_value =
        |dest: &HgPathBuf,
         src_minor: &TimeStampedPathCopy,
         src_major: &TimeStampedPathCopy| {
            compare_value(changes, oracle, dest, src_minor, src_major)
        };
    if minor.is_empty() {
        major
    } else if major.is_empty() {
        minor
    } else if minor.len() * 2 < major.len() {
        // Lets says we are merging two TimeStampedPathCopies instance A and B.
        //
        // If A contains N items, the merge result will never contains more
        // than N values differents than the one in A
        //
        // If B contains M items, with M > N, the merge result will always
        // result in a minimum of M - N value differents than the on in
        // A
        //
        // As a result, if N < (M-N), we know that simply iterating over A will
        // yield less difference than iterating over the difference
        // between A and B.
        //
        // This help performance a lot in case were a tiny
        // TimeStampedPathCopies is merged with a much larger one.
        for (dest, src_minor) in minor {
            let src_major = major.get(&dest);
            match src_major {
                None => major.insert(dest, src_minor),
                Some(src_major) => {
                    match cmp_value(&dest, &src_minor, src_major) {
                        MergePick::Any | MergePick::Major => None,
                        MergePick::Minor => major.insert(dest, src_minor),
                    }
                }
            };
        }
        major
    } else if major.len() * 2 < minor.len() {
        // This use the same rational than the previous block.
        // (Check previous block documentation for details.)
        for (dest, src_major) in major {
            let src_minor = minor.get(&dest);
            match src_minor {
                None => minor.insert(dest, src_major),
                Some(src_minor) => {
                    match cmp_value(&dest, src_minor, &src_major) {
                        MergePick::Any | MergePick::Minor => None,
                        MergePick::Major => minor.insert(dest, src_major),
                    }
                }
            };
        }
        minor
    } else {
        let mut override_minor = Vec::new();
        let mut override_major = Vec::new();

        let mut to_major = |k: &HgPathBuf, v: &TimeStampedPathCopy| {
            override_major.push((k.clone(), v.clone()))
        };
        let mut to_minor = |k: &HgPathBuf, v: &TimeStampedPathCopy| {
            override_minor.push((k.clone(), v.clone()))
        };

        // The diff function leverage detection of the identical subpart if
        // minor and major has some common ancestors. This make it very
        // fast is most case.
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
                    match cmp_value(dest, src_minor, src_major) {
                        MergePick::Major => to_minor(dest, src_major),
                        MergePick::Minor => to_major(dest, src_minor),
                        // If the two entry are identical, no need to do
                        // anything (but diff should not have yield them)
                        MergePick::Any => unreachable!(),
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
}

/// represent the side that should prevail when merging two
/// TimeStampedPathCopies
enum MergePick {
    /// The "major" (p1) side prevails
    Major,
    /// The "minor" (p2) side prevails
    Minor,
    /// Any side could be used (because they are the same)
    Any,
}

/// decide which side prevails in case of conflicting values
#[allow(clippy::if_same_then_else)]
fn compare_value<A: Fn(Revision, Revision) -> bool>(
    changes: &ChangedFiles,
    oracle: &mut AncestorOracle<A>,
    dest: &HgPathBuf,
    src_minor: &TimeStampedPathCopy,
    src_major: &TimeStampedPathCopy,
) -> MergePick {
    if src_major.path == src_minor.path {
        // we have the same value, but from other source;
        if src_major.rev == src_minor.rev {
            // If the two entry are identical, they are both valid
            MergePick::Any
        } else if oracle.is_ancestor(src_major.rev, src_minor.rev) {
            MergePick::Minor
        } else {
            MergePick::Major
        }
    } else if src_major.rev == src_minor.rev {
        // We cannot get copy information for both p1 and p2 in the
        // same rev. So this is the same value.
        unreachable!(
            "conflict information from p1 and p2 in the same revision"
        );
    } else {
        let action = changes.get_merge_case(&dest);
        if src_major.path.is_none() && action == MergeCase::Salvaged {
            // If the file is "deleted" in the major side but was
            // salvaged by the merge, we keep the minor side alive
            MergePick::Minor
        } else if src_minor.path.is_none() && action == MergeCase::Salvaged {
            // If the file is "deleted" in the minor side but was
            // salvaged by the merge, unconditionnaly preserve the
            // major side.
            MergePick::Major
        } else if action == MergeCase::Merged {
            // If the file was actively merged, copy information
            // from each side might conflict.  The major side will
            // win such conflict.
            MergePick::Major
        } else if oracle.is_ancestor(src_major.rev, src_minor.rev) {
            // If the minor side is strictly newer than the major
            // side, it should be kept.
            MergePick::Minor
        } else if src_major.path.is_some() {
            // without any special case, the "major" value win
            // other the "minor" one.
            MergePick::Major
        } else if oracle.is_ancestor(src_minor.rev, src_major.rev) {
            // the "major" rev is a direct ancestors of "minor",
            // any different value should
            // overwrite
            MergePick::Major
        } else {
            // major version is None (so the file was deleted on
            // that branch) and that branch is independant (neither
            // minor nor major is an ancestors of the other one.)
            // We preserve the new
            // information about the new file.
            MergePick::Minor
        }
    }
}

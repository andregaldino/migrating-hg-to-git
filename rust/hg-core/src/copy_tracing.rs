use crate::utils::hg_path::HgPath;
use crate::utils::hg_path::HgPathBuf;
use crate::Revision;
use crate::NULL_REVISION;

use im_rc::ordmap::DiffItem;
use im_rc::ordmap::Entry;
use im_rc::ordmap::OrdMap;

use std::cmp::Ordering;
use std::collections::HashMap;
use std::collections::HashSet;
use std::convert::TryInto;

pub type PathCopies = HashMap<HgPathBuf, HgPathBuf>;

type PathToken = usize;

#[derive(Clone, Debug, PartialEq)]
struct CopySource {
    /// revision at which the copy information was added
    rev: Revision,
    /// the copy source, (Set to None in case of deletion of the associated
    /// key)
    path: Option<PathToken>,
    /// a set of previous `CopySource.rev` value directly or indirectly
    /// overwritten by this one.
    overwritten: HashSet<Revision>,
}

impl CopySource {
    /// create a new CopySource
    ///
    /// Use this when no previous copy source existed.
    fn new(rev: Revision, path: Option<PathToken>) -> Self {
        Self {
            rev,
            path,
            overwritten: HashSet::new(),
        }
    }

    /// create a new CopySource from merging two others
    ///
    /// Use this when merging two InternalPathCopies requires active merging of
    /// some entries.
    fn new_from_merge(rev: Revision, winner: &Self, loser: &Self) -> Self {
        let mut overwritten = HashSet::new();
        overwritten.extend(winner.overwritten.iter().copied());
        overwritten.extend(loser.overwritten.iter().copied());
        overwritten.insert(winner.rev);
        overwritten.insert(loser.rev);
        Self {
            rev,
            path: winner.path,
            overwritten: overwritten,
        }
    }

    /// Update the value of a pre-existing CopySource
    ///
    /// Use this when recording copy information from  parent → child edges
    fn overwrite(&mut self, rev: Revision, path: Option<PathToken>) {
        self.overwritten.insert(self.rev);
        self.rev = rev;
        self.path = path;
    }

    /// Mark pre-existing copy information as "dropped" by a file deletion
    ///
    /// Use this when recording copy information from  parent → child edges
    fn mark_delete(&mut self, rev: Revision) {
        self.overwritten.insert(self.rev);
        self.rev = rev;
        self.path = None;
    }

    fn is_overwritten_by(&self, other: &Self) -> bool {
        other.overwritten.contains(&self.rev)
    }
}

/// maps CopyDestination to Copy Source (+ a "timestamp" for the operation)
type InternalPathCopies = OrdMap<PathToken, CopySource>;

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

/// A small "tokenizer" responsible of turning full HgPath into lighter
/// PathToken
///
/// Dealing with small object, like integer is much faster, so HgPath input are
/// turned into integer "PathToken" and converted back in the end.
#[derive(Clone, Debug, Default)]
struct TwoWayPathMap {
    token: HashMap<HgPathBuf, PathToken>,
    path: Vec<HgPathBuf>,
}

impl TwoWayPathMap {
    fn tokenize(&mut self, path: &HgPath) -> PathToken {
        match self.token.get(path) {
            Some(a) => *a,
            None => {
                let a = self.token.len();
                let buf = path.to_owned();
                self.path.push(buf.clone());
                self.token.insert(buf, a);
                a
            }
        }
    }

    fn untokenize(&self, token: PathToken) -> &HgPathBuf {
        assert!(token < self.path.len(), format!("Unknown token: {}", token));
        &self.path[token]
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
pub fn combine_changeset_copies<D>(
    revs: Vec<Revision>,
    mut children_count: HashMap<Revision, usize>,
    target_rev: Revision,
    rev_info: RevInfoMaker<D>,
) -> PathCopies {
    let mut all_copies = HashMap::new();

    let mut path_map = TwoWayPathMap::default();

    for rev in revs {
        let mut d: DataHolder<D> = DataHolder { data: None };
        let (p1, p2, changes) = rev_info(rev, &mut d);

        // We will chain the copies information accumulated for the parent with
        // the individual copies information the curent revision.  Creating a
        // new TimeStampedPath for each `rev` → `children` vertex.
        let mut copies: Option<InternalPathCopies> = None;
        // Retrieve data computed in a previous iteration
        let p1_copies = match p1 {
            NULL_REVISION => None,
            _ => get_and_clean_parent_copies(
                &mut all_copies,
                &mut children_count,
                p1,
            ), // will be None if the vertex is not to be traversed
        };
        let p2_copies = match p2 {
            NULL_REVISION => None,
            _ => get_and_clean_parent_copies(
                &mut all_copies,
                &mut children_count,
                p2,
            ), // will be None if the vertex is not to be traversed
        };
        // combine it with data for that revision
        let p1_copies = match p1_copies {
            None => None,
            Some(parent_copies) => Some(add_from_changes(
                &mut path_map,
                &parent_copies,
                &changes,
                Parent::FirstParent,
                rev,
            )),
        };
        let p2_copies = match p2_copies {
            None => None,
            Some(parent_copies) => Some(add_from_changes(
                &mut path_map,
                &parent_copies,
                &changes,
                Parent::SecondParent,
                rev,
            )),
        };
        let copies = match (p1_copies, p2_copies) {
            (None, None) => None,
            (c, None) => c,
            (None, c) => c,
            (Some(p1_copies), Some(p2_copies)) => Some(merge_copies_dict(
                &path_map, rev, p2_copies, p1_copies, &changes,
            )),
        };
        if let Some(c) = copies {
            all_copies.insert(rev, c);
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
            let path_dest = path_map.untokenize(dest).to_owned();
            let path_path = path_map.untokenize(path).to_owned();
            result.insert(path_dest, path_path);
        }
    }
    result
}

/// fetch previous computed information
///
/// If no other children are expected to need this information, we drop it from
/// the cache.
///
/// If parent is not part of the set we are expected to walk, return None.
fn get_and_clean_parent_copies(
    all_copies: &mut HashMap<Revision, InternalPathCopies>,
    children_count: &mut HashMap<Revision, usize>,
    parent_rev: Revision,
) -> Option<InternalPathCopies> {
    let count = children_count.get_mut(&parent_rev)?;
    *count -= 1;
    if *count == 0 {
        match all_copies.remove(&parent_rev) {
            Some(c) => Some(c),
            None => Some(InternalPathCopies::default()),
        }
    } else {
        match all_copies.get(&parent_rev) {
            Some(c) => Some(c.clone()),
            None => Some(InternalPathCopies::default()),
        }
    }
}

/// Combine ChangedFiles with some existing PathCopies information and return
/// the result
fn add_from_changes(
    path_map: &mut TwoWayPathMap,
    base_copies: &InternalPathCopies,
    changes: &ChangedFiles,
    parent: Parent,
    current_rev: Revision,
) -> InternalPathCopies {
    let mut copies = base_copies.clone();
    for action in changes.iter_actions(parent) {
        match action {
            Action::Copied(path_dest, path_source) => {
                let dest = path_map.tokenize(path_dest);
                let source = path_map.tokenize(path_source);
                let entry;
                if let Some(v) = base_copies.get(&source) {
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
                match copies.entry(dest) {
                    Entry::Vacant(slot) => {
                        let ttpc = CopySource::new(current_rev, entry);
                        slot.insert(ttpc);
                    }
                    Entry::Occupied(mut slot) => {
                        let ttpc = slot.get_mut();
                        ttpc.overwrite(current_rev, entry);
                    }
                }
            }
            Action::Removed(deleted_path) => {
                // We must drop copy information for removed file.
                //
                // We need to explicitly record them as dropped to
                // propagate this information when merging two
                // InternalPathCopies object.
                let deleted = path_map.tokenize(deleted_path);
                copies.entry(deleted).and_modify(|old| {
                    old.mark_delete(current_rev);
                });
            }
        }
    }
    copies
}

/// merge two copies-mapping together, minor and major
///
/// In case of conflict, value from "major" will be picked, unless in some
/// cases. See inline documentation for details.
fn merge_copies_dict(
    path_map: &TwoWayPathMap,
    current_merge: Revision,
    mut minor: InternalPathCopies,
    mut major: InternalPathCopies,
    changes: &ChangedFiles,
) -> InternalPathCopies {
    // This closure exist as temporary help while multiple developper are
    // actively working on this code. Feel free to re-inline it once this
    // code is more settled.
    let cmp_value =
        |dest: &PathToken, src_minor: &CopySource, src_major: &CopySource| {
            compare_value(
                path_map,
                current_merge,
                changes,
                dest,
                src_minor,
                src_major,
            )
        };
    if minor.is_empty() {
        major
    } else if major.is_empty() {
        minor
    } else if minor.len() * 2 < major.len() {
        // Lets says we are merging two InternalPathCopies instance A and B.
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
        // InternalPathCopies is merged with a much larger one.
        for (dest, src_minor) in minor {
            let src_major = major.get(&dest);
            match src_major {
                None => {
                    major.insert(dest, src_minor);
                }
                Some(src_major) => {
                    let (pick, overwrite) =
                        cmp_value(&dest, &src_minor, src_major);
                    if overwrite {
                        let src = match pick {
                            MergePick::Major => CopySource::new_from_merge(
                                current_merge,
                                src_major,
                                &src_minor,
                            ),
                            MergePick::Minor => CopySource::new_from_merge(
                                current_merge,
                                &src_minor,
                                src_major,
                            ),
                            MergePick::Any => CopySource::new_from_merge(
                                current_merge,
                                src_major,
                                &src_minor,
                            ),
                        };
                        major.insert(dest, src);
                    } else {
                        match pick {
                            MergePick::Any | MergePick::Major => None,
                            MergePick::Minor => major.insert(dest, src_minor),
                        };
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
                None => {
                    minor.insert(dest, src_major);
                }
                Some(src_minor) => {
                    let (pick, overwrite) =
                        cmp_value(&dest, src_minor, &src_major);
                    if overwrite {
                        let src = match pick {
                            MergePick::Major => CopySource::new_from_merge(
                                current_merge,
                                &src_major,
                                src_minor,
                            ),
                            MergePick::Minor => CopySource::new_from_merge(
                                current_merge,
                                src_minor,
                                &src_major,
                            ),
                            MergePick::Any => CopySource::new_from_merge(
                                current_merge,
                                &src_major,
                                src_minor,
                            ),
                        };
                        minor.insert(dest, src);
                    } else {
                        match pick {
                            MergePick::Any | MergePick::Minor => None,
                            MergePick::Major => minor.insert(dest, src_major),
                        };
                    }
                }
            };
        }
        minor
    } else {
        let mut override_minor = Vec::new();
        let mut override_major = Vec::new();

        let mut to_major = |k: &PathToken, v: &CopySource| {
            override_major.push((k.clone(), v.clone()))
        };
        let mut to_minor = |k: &PathToken, v: &CopySource| {
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
                    let (pick, overwrite) =
                        cmp_value(dest, src_minor, src_major);
                    if overwrite {
                        let src = match pick {
                            MergePick::Major => CopySource::new_from_merge(
                                current_merge,
                                src_major,
                                src_minor,
                            ),
                            MergePick::Minor => CopySource::new_from_merge(
                                current_merge,
                                src_minor,
                                src_major,
                            ),
                            MergePick::Any => CopySource::new_from_merge(
                                current_merge,
                                src_major,
                                src_minor,
                            ),
                        };
                        to_minor(dest, &src);
                        to_major(dest, &src);
                    } else {
                        match pick {
                            MergePick::Major => to_minor(dest, src_major),
                            MergePick::Minor => to_major(dest, src_minor),
                            // If the two entry are identical, no need to do
                            // anything (but diff should not have yield them)
                            MergePick::Any => unreachable!(),
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
}

/// represent the side that should prevail when merging two
/// InternalPathCopies
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
fn compare_value(
    path_map: &TwoWayPathMap,
    current_merge: Revision,
    changes: &ChangedFiles,
    dest: &PathToken,
    src_minor: &CopySource,
    src_major: &CopySource,
) -> (MergePick, bool) {
    if src_major.rev == current_merge {
        if src_minor.rev == current_merge {
            if src_major.path.is_none() {
                // We cannot get different copy information for both p1 and p2
                // from the same revision. Unless this was a
                // deletion.
                //
                // However the deletion might come over different data on each
                // branch.
                let need_over = src_major.overwritten != src_minor.overwritten;
                (MergePick::Any, need_over)
            } else {
                unreachable!();
            }
        } else {
            // The last value comes the current merge, this value -will- win
            // eventually.
            (MergePick::Major, true)
        }
    } else if src_minor.rev == current_merge {
        // The last value comes the current merge, this value -will- win
        // eventually.
        (MergePick::Minor, true)
    } else if src_major.path == src_minor.path {
        // we have the same value, but from other source;
        if src_major.rev == src_minor.rev {
            // If the two entry are identical, they are both valid
            debug_assert!(src_minor.overwritten == src_minor.overwritten);
            (MergePick::Any, false)
        } else if src_major.is_overwritten_by(src_minor) {
            (MergePick::Minor, false)
        } else if src_minor.is_overwritten_by(src_major) {
            (MergePick::Major, false)
        } else {
            (MergePick::Any, true)
        }
    } else if src_major.rev == src_minor.rev {
        // We cannot get copy information for both p1 and p2 in the
        // same rev. So this is the same value.
        unreachable!(
            "conflicting information from p1 and p2 in the same revision"
        );
    } else {
        let dest_path = path_map.untokenize(*dest);
        let action = changes.get_merge_case(dest_path);
        if src_minor.path.is_some()
            && src_major.path.is_none()
            && action == MergeCase::Salvaged
        {
            // If the file is "deleted" in the major side but was
            // salvaged by the merge, we keep the minor side alive
            (MergePick::Minor, true)
        } else if src_major.path.is_some()
            && src_minor.path.is_none()
            && action == MergeCase::Salvaged
        {
            // If the file is "deleted" in the minor side but was
            // salvaged by the merge, unconditionnaly preserve the
            // major side.
            (MergePick::Major, true)
        } else if src_minor.is_overwritten_by(src_major) {
            // The information from the minor version are strictly older than
            // the major version
            if action == MergeCase::Merged {
                // If the file was actively merged, its means some non-copy
                // activity happened on the other branch. It
                // mean the older copy information are still relevant.
                //
                // The major side wins such conflict.
                (MergePick::Major, true)
            } else {
                // No activity on the minor branch, pick the newer one.
                (MergePick::Major, false)
            }
        } else if src_major.is_overwritten_by(src_minor) {
            if action == MergeCase::Merged {
                // If the file was actively merged, its means some non-copy
                // activity happened on the other branch. It
                // mean the older copy information are still relevant.
                //
                // The major side wins such conflict.
                (MergePick::Major, true)
            } else {
                // No activity on the minor branch, pick the newer one.
                (MergePick::Minor, false)
            }
        } else if src_minor.path.is_none() {
            // the minor side has no relevant information, pick the alive one
            (MergePick::Major, true)
        } else if src_major.path.is_none() {
            // the major side has no relevant information, pick the alive one
            (MergePick::Minor, true)
        } else {
            // by default the major side wins
            (MergePick::Major, true)
        }
    }
}

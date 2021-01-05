use crate::utils::hg_path::HgPath;
use crate::utils::hg_path::HgPathBuf;
use crate::Revision;
use crate::NULL_REVISION;

use im_rc::ordmap::Entry;
use im_rc::ordmap::OrdMap;
use im_rc::OrdSet;

use std::cmp::Ordering;
use std::collections::HashMap;
use std::convert::TryInto;

pub type PathCopies = HashMap<HgPathBuf, HgPathBuf>;

type PathToken = usize;

#[derive(Clone, Debug)]
struct CopySource {
    /// revision at which the copy information was added
    rev: Revision,
    /// the copy source, (Set to None in case of deletion of the associated
    /// key)
    path: Option<PathToken>,
    /// a set of previous `CopySource.rev` value directly or indirectly
    /// overwritten by this one.
    overwritten: OrdSet<Revision>,
}

impl CopySource {
    /// create a new CopySource
    ///
    /// Use this when no previous copy source existed.
    fn new(rev: Revision, path: Option<PathToken>) -> Self {
        Self {
            rev,
            path,
            overwritten: OrdSet::new(),
        }
    }

    /// create a new CopySource from merging two others
    ///
    /// Use this when merging two InternalPathCopies requires active merging of
    /// some entries.
    fn new_from_merge(rev: Revision, winner: &Self, loser: &Self) -> Self {
        let mut overwritten = OrdSet::new();
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

    /// Mark pre-existing copy information as "dropped" by a file deletion
    ///
    /// Use this when recording copy information from  parent → child edges
    fn mark_delete_with_pair(&mut self, rev: Revision, other: &Self) {
        self.overwritten.insert(self.rev);
        if other.rev != rev {
            self.overwritten.insert(other.rev);
        }
        self.overwritten.extend(other.overwritten.iter().copied());
        self.rev = rev;
        self.path = None;
    }

    fn is_overwritten_by(&self, other: &Self) -> bool {
        other.overwritten.contains(&self.rev)
    }
}

// For the same "dest", content generated for a given revision will always be
// the same.
impl PartialEq for CopySource {
    fn eq(&self, other: &Self) -> bool {
        #[cfg(debug_assertions)]
        {
            if self.rev == other.rev {
                debug_assert!(self.path == other.path);
                debug_assert!(self.overwritten == other.overwritten);
            }
        }
        self.rev == other.rev
    }
}

/// maps CopyDestination to Copy Source (+ a "timestamp" for the operation)
type InternalPathCopies = OrdMap<PathToken, CopySource>;

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
    CopiedFromP1(&'a HgPath, &'a HgPath),
    CopiedFromP2(&'a HgPath, &'a HgPath),
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
    fn iter_actions(&self) -> ActionsIterator {
        ActionsIterator {
            changes: &self,
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
    current: u32,
}

impl<'a> Iterator for ActionsIterator<'a> {
    type Item = Action<'a>;

    fn next(&mut self) -> Option<Action<'a>> {
        while self.current < self.changes.nb_items {
            let (flags, file, source) = self.changes.entry(self.current);
            self.current += 1;
            if (flags & ACTION_MASK) == REMOVED {
                return Some(Action::Removed(file));
            }
            let copy = flags & COPY_MASK;
            if copy == P1_COPY {
                return Some(Action::CopiedFromP1(file, source));
            } else if copy == P2_COPY {
                return Some(Action::CopiedFromP2(file, source));
            }
        }
        return None;
    }
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
pub struct CombineChangesetCopies {
    all_copies: HashMap<Revision, InternalPathCopies>,
    path_map: TwoWayPathMap,
    children_count: HashMap<Revision, usize>,
}

impl CombineChangesetCopies {
    pub fn new(children_count: HashMap<Revision, usize>) -> Self {
        Self {
            all_copies: HashMap::new(),
            path_map: TwoWayPathMap::default(),
            children_count,
        }
    }

    /// Combined the given `changes` data specific to `rev` with the data
    /// previously given for its parents (and transitively, its ancestors).
    pub fn add_revision(
        &mut self,
        rev: Revision,
        p1: Revision,
        p2: Revision,
        changes: ChangedFiles<'_>,
    ) {
        // Retrieve data computed in a previous iteration
        let p1_copies = match p1 {
            NULL_REVISION => None,
            _ => get_and_clean_parent_copies(
                &mut self.all_copies,
                &mut self.children_count,
                p1,
            ), // will be None if the vertex is not to be traversed
        };
        let p2_copies = match p2 {
            NULL_REVISION => None,
            _ => get_and_clean_parent_copies(
                &mut self.all_copies,
                &mut self.children_count,
                p2,
            ), // will be None if the vertex is not to be traversed
        };
        // combine it with data for that revision
        let (p1_copies, p2_copies) = chain_changes(
            &mut self.path_map,
            p1_copies,
            p2_copies,
            &changes,
            rev,
        );
        let copies = match (p1_copies, p2_copies) {
            (None, None) => None,
            (c, None) => c,
            (None, c) => c,
            (Some(p1_copies), Some(p2_copies)) => Some(merge_copies_dict(
                &self.path_map,
                rev,
                p2_copies,
                p1_copies,
                &changes,
            )),
        };
        if let Some(c) = copies {
            self.all_copies.insert(rev, c);
        }
    }

    /// Drop intermediate data (such as which revision a copy was from) and
    /// return the final mapping.
    pub fn finish(mut self, target_rev: Revision) -> PathCopies {
        let tt_result = self
            .all_copies
            .remove(&target_rev)
            .expect("target revision was not processed");
        let mut result = PathCopies::default();
        for (dest, tt_source) in tt_result {
            if let Some(path) = tt_source.path {
                let path_dest = self.path_map.untokenize(dest).to_owned();
                let path_path = self.path_map.untokenize(path).to_owned();
                result.insert(path_dest, path_path);
            }
        }
        result
    }
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
fn chain_changes(
    path_map: &mut TwoWayPathMap,
    base_p1_copies: Option<InternalPathCopies>,
    base_p2_copies: Option<InternalPathCopies>,
    changes: &ChangedFiles,
    current_rev: Revision,
) -> (Option<InternalPathCopies>, Option<InternalPathCopies>) {
    // Fast path the "nothing to do" case.
    if let (None, None) = (&base_p1_copies, &base_p2_copies) {
        return (None, None);
    }

    let mut p1_copies = base_p1_copies.clone();
    let mut p2_copies = base_p2_copies.clone();
    for action in changes.iter_actions() {
        match action {
            Action::CopiedFromP1(path_dest, path_source) => {
                match &mut p1_copies {
                    None => (), // This is not a vertex we should proceed.
                    Some(copies) => add_one_copy(
                        current_rev,
                        path_map,
                        copies,
                        base_p1_copies.as_ref().unwrap(),
                        path_dest,
                        path_source,
                    ),
                }
            }
            Action::CopiedFromP2(path_dest, path_source) => {
                match &mut p2_copies {
                    None => (), // This is not a vertex we should proceed.
                    Some(copies) => add_one_copy(
                        current_rev,
                        path_map,
                        copies,
                        base_p2_copies.as_ref().unwrap(),
                        path_dest,
                        path_source,
                    ),
                }
            }
            Action::Removed(deleted_path) => {
                // We must drop copy information for removed file.
                //
                // We need to explicitly record them as dropped to
                // propagate this information when merging two
                // InternalPathCopies object.
                let deleted = path_map.tokenize(deleted_path);

                let p1_entry = match &mut p1_copies {
                    None => None,
                    Some(copies) => match copies.entry(deleted) {
                        Entry::Occupied(e) => Some(e),
                        Entry::Vacant(_) => None,
                    },
                };
                let p2_entry = match &mut p2_copies {
                    None => None,
                    Some(copies) => match copies.entry(deleted) {
                        Entry::Occupied(e) => Some(e),
                        Entry::Vacant(_) => None,
                    },
                };

                match (p1_entry, p2_entry) {
                    (None, None) => (),
                    (Some(mut e), None) => {
                        e.get_mut().mark_delete(current_rev)
                    }
                    (None, Some(mut e)) => {
                        e.get_mut().mark_delete(current_rev)
                    }
                    (Some(mut e1), Some(mut e2)) => {
                        let cs1 = e1.get_mut();
                        let cs2 = e2.get();
                        if cs1 == cs2 {
                            cs1.mark_delete(current_rev);
                        } else {
                            cs1.mark_delete_with_pair(current_rev, &cs2);
                        }
                        e2.insert(cs1.clone());
                    }
                }
            }
        }
    }
    (p1_copies, p2_copies)
}

// insert one new copy information in an InternalPathCopies
//
// This deal with chaining and overwrite.
fn add_one_copy(
    current_rev: Revision,
    path_map: &mut TwoWayPathMap,
    copies: &mut InternalPathCopies,
    base_copies: &InternalPathCopies,
    path_dest: &HgPath,
    path_source: &HgPath,
) {
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

/// merge two copies-mapping together, minor and major
///
/// In case of conflict, value from "major" will be picked, unless in some
/// cases. See inline documentation for details.
fn merge_copies_dict(
    path_map: &TwoWayPathMap,
    current_merge: Revision,
    minor: InternalPathCopies,
    major: InternalPathCopies,
    changes: &ChangedFiles,
) -> InternalPathCopies {
    use crate::utils::{ordmap_union_with_merge, MergeResult};

    ordmap_union_with_merge(minor, major, |dest, src_minor, src_major| {
        let (pick, overwrite) = compare_value(
            path_map,
            current_merge,
            changes,
            dest,
            src_minor,
            src_major,
        );
        if overwrite {
            let (winner, loser) = match pick {
                MergePick::Major | MergePick::Any => (src_major, src_minor),
                MergePick::Minor => (src_minor, src_major),
            };
            MergeResult::UseNewValue(CopySource::new_from_merge(
                current_merge,
                winner,
                loser,
            ))
        } else {
            match pick {
                MergePick::Any | MergePick::Major => {
                    MergeResult::UseRightValue
                }
                MergePick::Minor => MergeResult::UseLeftValue,
            }
        }
    })
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
    if src_major == src_minor {
        (MergePick::Any, false)
    } else if src_major.rev == current_merge {
        // minor is different according to per minor == major check earlier
        debug_assert!(src_minor.rev != current_merge);

        // The last value comes the current merge, this value -will- win
        // eventually.
        (MergePick::Major, true)
    } else if src_minor.rev == current_merge {
        // The last value comes the current merge, this value -will- win
        // eventually.
        (MergePick::Minor, true)
    } else if src_major.path == src_minor.path {
        debug_assert!(src_major.rev != src_major.rev);
        // we have the same value, but from other source;
        if src_major.is_overwritten_by(src_minor) {
            (MergePick::Minor, false)
        } else if src_minor.is_overwritten_by(src_major) {
            (MergePick::Major, false)
        } else {
            (MergePick::Any, true)
        }
    } else {
        debug_assert!(src_major.rev != src_major.rev);
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

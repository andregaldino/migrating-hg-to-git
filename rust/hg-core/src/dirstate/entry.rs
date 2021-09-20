use crate::errors::HgError;
use bitflags::bitflags;
use std::convert::TryFrom;

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum EntryState {
    Normal,
    Added,
    Removed,
    Merged,
}

/// The C implementation uses all signed types. This will be an issue
/// either when 4GB+ source files are commonplace or in 2038, whichever
/// comes first.
#[derive(Debug, PartialEq, Copy, Clone)]
pub struct DirstateEntry {
    flags: Flags,
    mode: i32,
    size: i32,
    mtime: i32,
}

bitflags! {
    struct Flags: u8 {
        const WDIR_TRACKED = 1 << 0;
        const P1_TRACKED = 1 << 1;
        const P2_TRACKED = 1 << 2;
        const POSSIBLY_DIRTY = 1 << 3;
        const MERGED = 1 << 4;
        const CLEAN_P1 = 1 << 5;
        const CLEAN_P2 = 1 << 6;
        const ENTRYLESS_TREE_NODE = 1 << 7;
    }
}

pub const V1_RANGEMASK: i32 = 0x7FFFFFFF;

pub const MTIME_UNSET: i32 = -1;

/// A `DirstateEntry` with a size of `-2` means that it was merged from the
/// other parent. This allows revert to pick the right status back during a
/// merge.
pub const SIZE_FROM_OTHER_PARENT: i32 = -2;
/// A special value used for internal representation of special case in
/// dirstate v1 format.
pub const SIZE_NON_NORMAL: i32 = -1;

impl DirstateEntry {
    pub fn from_v1_data(
        state: EntryState,
        mode: i32,
        size: i32,
        mtime: i32,
    ) -> Self {
        match state {
            EntryState::Normal => {
                if size == SIZE_FROM_OTHER_PARENT {
                    Self::new_from_p2()
                } else if size == SIZE_NON_NORMAL {
                    Self::new_possibly_dirty()
                } else if mtime == MTIME_UNSET {
                    Self {
                        flags: Flags::WDIR_TRACKED
                            | Flags::P1_TRACKED
                            | Flags::POSSIBLY_DIRTY,
                        mode,
                        size,
                        mtime: 0,
                    }
                } else {
                    Self {
                        flags: Flags::WDIR_TRACKED | Flags::P1_TRACKED,
                        mode,
                        size,
                        mtime,
                    }
                }
            }
            EntryState::Added => Self::new_added(),
            EntryState::Removed => Self {
                flags: if size == SIZE_NON_NORMAL {
                    Flags::P1_TRACKED // might not be true because of rename ?
                    | Flags::P2_TRACKED // might not be true because of rename ?
                    | Flags::MERGED
                } else if size == SIZE_FROM_OTHER_PARENT {
                    // We don’t know if P1_TRACKED should be set (file history)
                    Flags::P2_TRACKED | Flags::CLEAN_P2
                } else {
                    Flags::P1_TRACKED
                },
                mode: 0,
                size: 0,
                mtime: 0,
            },
            EntryState::Merged => Self::new_merged(),
        }
    }

    fn new_from_p2() -> Self {
        Self {
            // might be missing P1_TRACKED
            flags: Flags::WDIR_TRACKED | Flags::P2_TRACKED | Flags::CLEAN_P2,
            mode: 0,
            size: SIZE_FROM_OTHER_PARENT,
            mtime: MTIME_UNSET,
        }
    }

    fn new_possibly_dirty() -> Self {
        Self {
            flags: Flags::WDIR_TRACKED
                | Flags::P1_TRACKED
                | Flags::POSSIBLY_DIRTY,
            mode: 0,
            size: SIZE_NON_NORMAL,
            mtime: MTIME_UNSET,
        }
    }

    fn new_added() -> Self {
        Self {
            flags: Flags::WDIR_TRACKED,
            mode: 0,
            size: SIZE_NON_NORMAL,
            mtime: MTIME_UNSET,
        }
    }

    fn new_merged() -> Self {
        Self {
            flags: Flags::WDIR_TRACKED
                | Flags::P1_TRACKED // might not be true because of rename ?
                | Flags::P2_TRACKED // might not be true because of rename ?
                | Flags::MERGED,
            mode: 0,
            size: SIZE_NON_NORMAL,
            mtime: MTIME_UNSET,
        }
    }

    /// Creates a new entry in "removed" state.
    ///
    /// `size` is expected to be zero, `SIZE_NON_NORMAL`, or
    /// `SIZE_FROM_OTHER_PARENT`
    pub fn new_removed(size: i32) -> Self {
        Self::from_v1_data(EntryState::Removed, 0, size, 0)
    }

    /// TODO: refactor `DirstateMap::add_file` to not take a `DirstateEntry`
    /// parameter and remove this constructor
    pub fn new_for_add_file(mode: i32, size: i32, mtime: i32) -> Self {
        // XXX Arbitrary default value since the value is determined later
        let state = EntryState::Normal;
        Self::from_v1_data(state, mode, size, mtime)
    }

    fn tracked_in_any_parent(&self) -> bool {
        self.flags.intersects(Flags::P1_TRACKED | Flags::P2_TRACKED)
    }

    fn removed(&self) -> bool {
        self.tracked_in_any_parent()
            && !self.flags.contains(Flags::WDIR_TRACKED)
    }

    fn merged_removed(&self) -> bool {
        self.removed() && self.flags.contains(Flags::MERGED)
    }

    fn from_p2_removed(&self) -> bool {
        self.removed() && self.flags.contains(Flags::CLEAN_P2)
    }

    fn merged(&self) -> bool {
        self.flags.contains(Flags::WDIR_TRACKED | Flags::MERGED)
    }

    fn added(&self) -> bool {
        self.flags.contains(Flags::WDIR_TRACKED)
            && !self.tracked_in_any_parent()
    }

    fn from_p2(&self) -> bool {
        self.flags.contains(Flags::WDIR_TRACKED | Flags::CLEAN_P2)
    }

    pub fn state(&self) -> EntryState {
        if self.removed() {
            EntryState::Removed
        } else if self.merged() {
            EntryState::Merged
        } else if self.added() {
            EntryState::Added
        } else {
            EntryState::Normal
        }
    }

    pub fn mode(&self) -> i32 {
        self.mode
    }

    pub fn size(&self) -> i32 {
        if self.merged_removed() {
            SIZE_NON_NORMAL
        } else if self.from_p2_removed() {
            SIZE_FROM_OTHER_PARENT
        } else if self.removed() {
            0
        } else if self.merged() {
            SIZE_FROM_OTHER_PARENT
        } else if self.added() {
            SIZE_NON_NORMAL
        } else if self.from_p2() {
            SIZE_FROM_OTHER_PARENT
        } else if self.flags.contains(Flags::POSSIBLY_DIRTY) {
            self.size // TODO: SIZE_NON_NORMAL ?
        } else {
            self.size
        }
    }

    pub fn mtime(&self) -> i32 {
        if self.removed() {
            0
        } else if self.flags.contains(Flags::POSSIBLY_DIRTY) {
            MTIME_UNSET
        } else if self.merged() {
            MTIME_UNSET
        } else if self.added() {
            MTIME_UNSET
        } else if self.from_p2() {
            MTIME_UNSET
        } else {
            self.mtime
        }
    }

    /// Returns `(state, mode, size, mtime)` for the puprose of serialization
    /// in the dirstate-v1 format.
    ///
    /// This includes marker values such as `mtime == -1`. In the future we may
    /// want to not represent these cases that way in memory, but serialization
    /// will need to keep the same format.
    pub fn v1_data(&self) -> (u8, i32, i32, i32) {
        (self.state().into(), self.mode(), self.size(), self.mtime())
    }

    pub fn is_non_normal(&self) -> bool {
        self.state() != EntryState::Normal || self.mtime() == MTIME_UNSET
    }

    pub fn is_from_other_parent(&self) -> bool {
        self.state() == EntryState::Normal
            && self.size() == SIZE_FROM_OTHER_PARENT
    }

    // TODO: other platforms
    #[cfg(unix)]
    pub fn mode_changed(
        &self,
        filesystem_metadata: &std::fs::Metadata,
    ) -> bool {
        use std::os::unix::fs::MetadataExt;
        const EXEC_BIT_MASK: u32 = 0o100;
        let dirstate_exec_bit = (self.mode() as u32) & EXEC_BIT_MASK;
        let fs_exec_bit = filesystem_metadata.mode() & EXEC_BIT_MASK;
        dirstate_exec_bit != fs_exec_bit
    }

    /// Returns a `(state, mode, size, mtime)` tuple as for
    /// `DirstateMapMethods::debug_iter`.
    pub fn debug_tuple(&self) -> (u8, i32, i32, i32) {
        let state = if self.flags.contains(Flags::ENTRYLESS_TREE_NODE) {
            b' '
        } else {
            self.state().into()
        };
        (state, self.mode(), self.size(), self.mtime())
    }

    pub fn mtime_is_ambiguous(&self, now: i32) -> bool {
        self.state() == EntryState::Normal && self.mtime() == now
    }

    pub fn clear_ambiguous_mtime(&mut self, now: i32) -> bool {
        let ambiguous = self.mtime_is_ambiguous(now);
        if ambiguous {
            // The file was last modified "simultaneously" with the current
            // write to dirstate (i.e. within the same second for file-
            // systems with a granularity of 1 sec). This commonly happens
            // for at least a couple of files on 'update'.
            // The user could change the file without changing its size
            // within the same second. Invalidate the file's mtime in
            // dirstate, forcing future 'status' calls to compare the
            // contents of the file if the size is the same. This prevents
            // mistakenly treating such files as clean.
            self.clear_mtime()
        }
        ambiguous
    }

    pub fn clear_mtime(&mut self) {
        self.mtime = -1;
    }
}

impl EntryState {
    pub fn is_tracked(self) -> bool {
        use EntryState::*;
        match self {
            Normal | Added | Merged => true,
            Removed => false,
        }
    }
}

impl TryFrom<u8> for EntryState {
    type Error = HgError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            b'n' => Ok(EntryState::Normal),
            b'a' => Ok(EntryState::Added),
            b'r' => Ok(EntryState::Removed),
            b'm' => Ok(EntryState::Merged),
            _ => Err(HgError::CorruptedRepository(format!(
                "Incorrect dirstate entry state {}",
                value
            ))),
        }
    }
}

impl Into<u8> for EntryState {
    fn into(self) -> u8 {
        match self {
            EntryState::Normal => b'n',
            EntryState::Added => b'a',
            EntryState::Removed => b'r',
            EntryState::Merged => b'm',
        }
    }
}

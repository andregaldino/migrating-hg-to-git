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
    pub struct Flags: u8 {
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
    pub fn new(
        flags: Flags,
        mode_size_mtime: Option<(i32, i32, i32)>,
    ) -> Self {
        let (mode, size, mtime) =
            mode_size_mtime.unwrap_or((0, SIZE_NON_NORMAL, MTIME_UNSET));
        Self {
            flags,
            mode,
            size,
            mtime,
        }
    }

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
                    Self::new_normal(mode, size, mtime)
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

    pub fn new_from_p2() -> Self {
        Self {
            // might be missing P1_TRACKED
            flags: Flags::WDIR_TRACKED | Flags::P2_TRACKED | Flags::CLEAN_P2,
            mode: 0,
            size: SIZE_FROM_OTHER_PARENT,
            mtime: MTIME_UNSET,
        }
    }

    pub fn new_possibly_dirty() -> Self {
        Self {
            flags: Flags::WDIR_TRACKED
                | Flags::P1_TRACKED
                | Flags::POSSIBLY_DIRTY,
            mode: 0,
            size: SIZE_NON_NORMAL,
            mtime: MTIME_UNSET,
        }
    }

    pub fn new_added() -> Self {
        Self {
            flags: Flags::WDIR_TRACKED,
            mode: 0,
            size: SIZE_NON_NORMAL,
            mtime: MTIME_UNSET,
        }
    }

    pub fn new_merged() -> Self {
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

    pub fn new_normal(mode: i32, size: i32, mtime: i32) -> Self {
        Self {
            flags: Flags::WDIR_TRACKED | Flags::P1_TRACKED,
            mode,
            size,
            mtime,
        }
    }

    /// Creates a new entry in "removed" state.
    ///
    /// `size` is expected to be zero, `SIZE_NON_NORMAL`, or
    /// `SIZE_FROM_OTHER_PARENT`
    pub fn new_removed(size: i32) -> Self {
        Self::from_v1_data(EntryState::Removed, 0, size, 0)
    }

    pub fn tracked(&self) -> bool {
        self.flags.contains(Flags::WDIR_TRACKED)
    }

    fn tracked_in_any_parent(&self) -> bool {
        self.flags.intersects(Flags::P1_TRACKED | Flags::P2_TRACKED)
    }

    pub fn removed(&self) -> bool {
        self.tracked_in_any_parent()
            && !self.flags.contains(Flags::WDIR_TRACKED)
    }

    pub fn merged(&self) -> bool {
        self.flags.contains(Flags::WDIR_TRACKED | Flags::MERGED)
    }

    pub fn added(&self) -> bool {
        self.flags.contains(Flags::WDIR_TRACKED)
            && !self.tracked_in_any_parent()
    }

    pub fn from_p2(&self) -> bool {
        self.flags.contains(Flags::WDIR_TRACKED | Flags::CLEAN_P2)
    }

    pub fn maybe_clean(&self) -> bool {
        if !self.flags.contains(Flags::WDIR_TRACKED) {
            false
        } else if self.added() {
            false
        } else if self.flags.contains(Flags::MERGED) {
            false
        } else if self.flags.contains(Flags::CLEAN_P2) {
            false
        } else {
            true
        }
    }

    pub fn any_tracked(&self) -> bool {
        self.flags.intersects(
            Flags::WDIR_TRACKED | Flags::P1_TRACKED | Flags::P2_TRACKED,
        )
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
        if self.removed() && self.flags.contains(Flags::MERGED) {
            SIZE_NON_NORMAL
        } else if self.removed() && self.flags.contains(Flags::CLEAN_P2) {
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

    pub fn drop_merge_data(&mut self) {
        if self.flags.contains(Flags::CLEAN_P1)
            || self.flags.contains(Flags::CLEAN_P2)
            || self.flags.contains(Flags::MERGED)
            || self.flags.contains(Flags::P2_TRACKED)
        {
            if self.flags.contains(Flags::MERGED) {
                self.flags.insert(Flags::P1_TRACKED);
            } else {
                self.flags.remove(Flags::P1_TRACKED);
            }
            self.flags.remove(
                Flags::MERGED
                    | Flags::CLEAN_P1
                    | Flags::CLEAN_P2
                    | Flags::P2_TRACKED,
            );
            self.flags.insert(Flags::POSSIBLY_DIRTY);
            self.mode = 0;
            self.mtime = 0;
            // size = None on the python size turn into size = NON_NORMAL when
            // accessed. So the next line is currently required, but a some
            // future clean up would be welcome.
            self.size = SIZE_NON_NORMAL;
        }
    }

    pub fn set_possibly_dirty(&mut self) {
        self.flags.insert(Flags::POSSIBLY_DIRTY)
    }

    pub fn set_clean(&mut self, mode: i32, size: i32, mtime: i32) {
        self.flags.insert(Flags::WDIR_TRACKED | Flags::P1_TRACKED);
        self.flags.remove(
            Flags::P2_TRACKED // This might be wrong
                | Flags::MERGED
                | Flags::CLEAN_P2
                | Flags::POSSIBLY_DIRTY,
        );
        self.mode = mode;
        self.size = size;
        self.mtime = mtime;
    }

    pub fn set_tracked(&mut self) {
        self.flags
            .insert(Flags::WDIR_TRACKED | Flags::POSSIBLY_DIRTY);
        // size = None on the python size turn into size = NON_NORMAL when
        // accessed. So the next line is currently required, but a some future
        // clean up would be welcome.
        self.size = SIZE_NON_NORMAL;
    }

    pub fn set_untracked(&mut self) {
        self.flags.remove(Flags::WDIR_TRACKED);
        self.mode = 0;
        self.size = 0;
        self.mtime = 0;
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

    pub(crate) fn is_from_other_parent(&self) -> bool {
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

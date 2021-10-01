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
    pub(crate) flags: Flags,
    mode_size: Option<(i32, i32)>,
    mtime: Option<i32>,
}

bitflags! {
    pub(crate) struct Flags: u8 {
        const WDIR_TRACKED = 1 << 0;
        const P1_TRACKED = 1 << 1;
        const P2_INFO = 1 << 2;
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
    pub fn from_v2_data(
        wdir_tracked: bool,
        p1_tracked: bool,
        p2_info: bool,
        mode_size: Option<(i32, i32)>,
        mtime: Option<i32>,
    ) -> Self {
        let mut flags = Flags::empty();
        flags.set(Flags::WDIR_TRACKED, wdir_tracked);
        flags.set(Flags::P1_TRACKED, p1_tracked);
        flags.set(Flags::P2_INFO, p2_info);
        Self {
            flags,
            mode_size,
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
                    Self {
                        // might be missing P1_TRACKED
                        flags: Flags::WDIR_TRACKED | Flags::P2_INFO,
                        mode_size: None,
                        mtime: None,
                    }
                } else if size == SIZE_NON_NORMAL {
                    Self::new_possibly_dirty()
                } else if mtime == MTIME_UNSET {
                    Self {
                        flags: Flags::WDIR_TRACKED | Flags::P1_TRACKED,
                        mode_size: Some((mode, size)),
                        mtime: None,
                    }
                } else {
                    Self::new_normal(mode, size, mtime)
                }
            }
            EntryState::Added => Self {
                flags: Flags::WDIR_TRACKED,
                mode_size: None,
                mtime: None,
            },
            EntryState::Removed => Self {
                flags: if size == SIZE_NON_NORMAL {
                    Flags::P1_TRACKED | Flags::P2_INFO
                } else if size == SIZE_FROM_OTHER_PARENT {
                    // We don’t know if P1_TRACKED should be set (file history)
                    Flags::P2_INFO
                } else {
                    Flags::P1_TRACKED
                },
                mode_size: None,
                mtime: None,
            },
            EntryState::Merged => Self {
                flags: Flags::WDIR_TRACKED
                    | Flags::P1_TRACKED // might not be true because of rename ?
                    | Flags::P2_INFO, // might not be true because of rename ?
                mode_size: None,
                mtime: None,
            },
        }
    }

    pub fn new_possibly_dirty() -> Self {
        Self {
            flags: Flags::WDIR_TRACKED | Flags::P1_TRACKED,
            mode_size: None,
            mtime: None,
        }
    }

    pub fn new_normal(mode: i32, size: i32, mtime: i32) -> Self {
        Self {
            flags: Flags::WDIR_TRACKED | Flags::P1_TRACKED,
            mode_size: Some((mode, size)),
            mtime: Some(mtime),
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

    pub fn p1_tracked(&self) -> bool {
        self.flags.contains(Flags::P1_TRACKED)
    }

    fn in_either_parent(&self) -> bool {
        self.flags.intersects(Flags::P1_TRACKED | Flags::P2_INFO)
    }

    pub fn removed(&self) -> bool {
        self.in_either_parent() && !self.flags.contains(Flags::WDIR_TRACKED)
    }

    pub fn p2_info(&self) -> bool {
        self.flags.contains(Flags::WDIR_TRACKED | Flags::P2_INFO)
    }

    pub fn added(&self) -> bool {
        self.flags.contains(Flags::WDIR_TRACKED) && !self.in_either_parent()
    }

    pub fn maybe_clean(&self) -> bool {
        if !self.flags.contains(Flags::WDIR_TRACKED) {
            false
        } else if !self.flags.contains(Flags::P1_TRACKED) {
            false
        } else if self.flags.contains(Flags::P2_INFO) {
            false
        } else {
            true
        }
    }

    pub fn any_tracked(&self) -> bool {
        self.flags.intersects(
            Flags::WDIR_TRACKED | Flags::P1_TRACKED | Flags::P2_INFO,
        )
    }

    /// Returns `(wdir_tracked, p1_tracked, p2_info, mode_size, mtime)`
    pub(crate) fn v2_data(
        &self,
    ) -> (bool, bool, bool, Option<(i32, i32)>, Option<i32>) {
        if !self.any_tracked() {
            // TODO: return an Option instead?
            panic!("Accessing v1_state of an untracked DirstateEntry")
        }
        let wdir_tracked = self.flags.contains(Flags::WDIR_TRACKED);
        let p1_tracked = self.flags.contains(Flags::P1_TRACKED);
        let p2_info = self.flags.contains(Flags::P2_INFO);
        let mode_size = self.mode_size;
        let mtime = self.mtime;
        (wdir_tracked, p1_tracked, p2_info, mode_size, mtime)
    }

    fn v1_state(&self) -> EntryState {
        if !self.any_tracked() {
            // TODO: return an Option instead?
            panic!("Accessing v1_state of an untracked DirstateEntry")
        }
        if self.removed() {
            EntryState::Removed
        } else if self
            .flags
            .contains(Flags::WDIR_TRACKED | Flags::P1_TRACKED | Flags::P2_INFO)
        {
            EntryState::Merged
        } else if self.added() {
            EntryState::Added
        } else {
            EntryState::Normal
        }
    }

    fn v1_mode(&self) -> i32 {
        if let Some((mode, _size)) = self.mode_size {
            mode
        } else {
            0
        }
    }

    fn v1_size(&self) -> i32 {
        if !self.any_tracked() {
            // TODO: return an Option instead?
            panic!("Accessing v1_size of an untracked DirstateEntry")
        }
        if self.removed()
            && self.flags.contains(Flags::P1_TRACKED | Flags::P2_INFO)
        {
            SIZE_NON_NORMAL
        } else if self.flags.contains(Flags::P2_INFO) {
            SIZE_FROM_OTHER_PARENT
        } else if self.removed() {
            0
        } else if self.added() {
            SIZE_NON_NORMAL
        } else if let Some((_mode, size)) = self.mode_size {
            size
        } else {
            SIZE_NON_NORMAL
        }
    }

    fn v1_mtime(&self) -> i32 {
        if !self.any_tracked() {
            // TODO: return an Option instead?
            panic!("Accessing v1_mtime of an untracked DirstateEntry")
        }
        if self.removed() {
            0
        } else if self.flags.contains(Flags::P2_INFO) {
            MTIME_UNSET
        } else if !self.flags.contains(Flags::P1_TRACKED) {
            MTIME_UNSET
        } else {
            self.mtime.unwrap_or(MTIME_UNSET)
        }
    }

    // TODO: return `Option<EntryState>`? None when `!self.any_tracked`
    pub fn state(&self) -> EntryState {
        self.v1_state()
    }

    // TODO: return Option?
    pub fn mode(&self) -> i32 {
        self.v1_mode()
    }

    // TODO: return Option?
    pub fn size(&self) -> i32 {
        self.v1_size()
    }

    // TODO: return Option?
    pub fn mtime(&self) -> i32 {
        self.v1_mtime()
    }

    pub fn drop_merge_data(&mut self) {
        if self.flags.contains(Flags::P2_INFO) {
            self.flags.remove(Flags::P2_INFO);
            self.mode_size = None;
            self.mtime = None;
        }
    }

    pub fn set_possibly_dirty(&mut self) {
        self.mtime = None
    }

    pub fn set_clean(&mut self, mode: i32, size: i32, mtime: i32) {
        self.flags.insert(Flags::WDIR_TRACKED | Flags::P1_TRACKED);
        self.mode_size = Some((mode, size));
        self.mtime = Some(mtime);
    }

    pub fn set_tracked(&mut self) {
        self.flags.insert(Flags::WDIR_TRACKED);
        // `set_tracked` is replacing various `normallookup` call. So we mark
        // the files as needing lookup
        //
        // Consider dropping this in the future in favor of something less
        // broad.
        self.mtime = None;
    }

    pub fn set_untracked(&mut self) {
        self.flags.remove(Flags::WDIR_TRACKED);
        self.mode_size = None;
        self.mtime = None;
    }

    /// Returns `(state, mode, size, mtime)` for the puprose of serialization
    /// in the dirstate-v1 format.
    ///
    /// This includes marker values such as `mtime == -1`. In the future we may
    /// want to not represent these cases that way in memory, but serialization
    /// will need to keep the same format.
    pub fn v1_data(&self) -> (u8, i32, i32, i32) {
        (
            self.v1_state().into(),
            self.v1_mode(),
            self.v1_size(),
            self.v1_mtime(),
        )
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
        (self.state().into(), self.mode(), self.size(), self.mtime())
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
            self.set_possibly_dirty()
        }
        ambiguous
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

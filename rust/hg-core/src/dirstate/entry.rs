use crate::dirstate_tree::on_disk::DirstateV2ParseError;
use crate::errors::HgError;
use bitflags::bitflags;
use std::convert::{TryFrom, TryInto};
use std::fs;
use std::io;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum EntryState {
    Normal,
    Added,
    Removed,
    Merged,
}

/// `size` and `mtime.seconds` are truncated to 31 bits.
///
/// TODO: double-check status algorithm correctness for files
/// larger than 2 GiB or modified after 2038.
#[derive(Debug, Copy, Clone)]
pub struct DirstateEntry {
    pub(crate) flags: Flags,
    mode_size: Option<(u32, u32)>,
    mtime: Option<TruncatedTimestamp>,
}

bitflags! {
    pub(crate) struct Flags: u8 {
        const WDIR_TRACKED = 1 << 0;
        const P1_TRACKED = 1 << 1;
        const P2_INFO = 1 << 2;
        const HAS_FALLBACK_EXEC = 1 << 3;
        const FALLBACK_EXEC = 1 << 4;
        const HAS_FALLBACK_SYMLINK = 1 << 5;
        const FALLBACK_SYMLINK = 1 << 6;
    }
}

/// A Unix timestamp with nanoseconds precision
#[derive(Debug, Copy, Clone)]
pub struct TruncatedTimestamp {
    truncated_seconds: u32,
    /// Always in the `0 .. 1_000_000_000` range.
    nanoseconds: u32,
}

impl TruncatedTimestamp {
    /// Constructs from a timestamp potentially outside of the supported range,
    /// and truncate the seconds components to its lower 31 bits.
    ///
    /// Panics if the nanoseconds components is not in the expected range.
    pub fn new_truncate(seconds: i64, nanoseconds: u32) -> Self {
        assert!(nanoseconds < NSEC_PER_SEC);
        Self {
            truncated_seconds: seconds as u32 & RANGE_MASK_31BIT,
            nanoseconds,
        }
    }

    /// Construct from components. Returns an error if they are not in the
    /// expcted range.
    pub fn from_already_truncated(
        truncated_seconds: u32,
        nanoseconds: u32,
    ) -> Result<Self, DirstateV2ParseError> {
        if truncated_seconds & !RANGE_MASK_31BIT == 0
            && nanoseconds < NSEC_PER_SEC
        {
            Ok(Self {
                truncated_seconds,
                nanoseconds,
            })
        } else {
            Err(DirstateV2ParseError)
        }
    }

    pub fn for_mtime_of(metadata: &fs::Metadata) -> io::Result<Self> {
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            let seconds = metadata.mtime();
            // i64 -> u32 with value always in the `0 .. NSEC_PER_SEC` range
            let nanoseconds = metadata.mtime_nsec().try_into().unwrap();
            Ok(Self::new_truncate(seconds, nanoseconds))
        }
        #[cfg(not(unix))]
        {
            metadata.modified().map(Self::from)
        }
    }

    /// The lower 31 bits of the number of seconds since the epoch.
    pub fn truncated_seconds(&self) -> u32 {
        self.truncated_seconds
    }

    /// The sub-second component of this timestamp, in nanoseconds.
    /// Always in the `0 .. 1_000_000_000` range.
    ///
    /// This timestamp is after `(seconds, 0)` by this many nanoseconds.
    pub fn nanoseconds(&self) -> u32 {
        self.nanoseconds
    }

    /// Returns whether two timestamps are equal modulo 2**31 seconds.
    ///
    /// If this returns `true`, the original values converted from `SystemTime`
    /// or given to `new_truncate` were very likely equal. A false positive is
    /// possible if they were exactly a multiple of 2**31 seconds apart (around
    /// 68 years). This is deemed very unlikely to happen by chance, especially
    /// on filesystems that support sub-second precision.
    ///
    /// If someone is manipulating the modification times of some files to
    /// intentionally make `hg status` return incorrect results, not truncating
    /// wouldn’t help much since they can set exactly the expected timestamp.
    ///
    /// Sub-second precision is ignored if it is zero in either value.
    /// Some APIs simply return zero when more precision is not available.
    /// When comparing values from different sources, if only one is truncated
    /// in that way, doing a simple comparison would cause many false
    /// negatives.
    pub fn likely_equal(self, other: Self) -> bool {
        self.truncated_seconds == other.truncated_seconds
            && (self.nanoseconds == other.nanoseconds
                || self.nanoseconds == 0
                || other.nanoseconds == 0)
    }

    pub fn likely_equal_to_mtime_of(
        self,
        metadata: &fs::Metadata,
    ) -> io::Result<bool> {
        Ok(self.likely_equal(Self::for_mtime_of(metadata)?))
    }
}

impl From<SystemTime> for TruncatedTimestamp {
    fn from(system_time: SystemTime) -> Self {
        // On Unix, `SystemTime` is a wrapper for the `timespec` C struct:
        // https://www.gnu.org/software/libc/manual/html_node/Time-Types.html#index-struct-timespec
        // We want to effectively access its fields, but the Rust standard
        // library does not expose them. The best we can do is:
        let seconds;
        let nanoseconds;
        match system_time.duration_since(UNIX_EPOCH) {
            Ok(duration) => {
                seconds = duration.as_secs() as i64;
                nanoseconds = duration.subsec_nanos();
            }
            Err(error) => {
                // `system_time` is before `UNIX_EPOCH`.
                // We need to undo this algorithm:
                // https://github.com/rust-lang/rust/blob/6bed1f0bc3cc50c10aab26d5f94b16a00776b8a5/library/std/src/sys/unix/time.rs#L40-L41
                let negative = error.duration();
                let negative_secs = negative.as_secs() as i64;
                let negative_nanos = negative.subsec_nanos();
                if negative_nanos == 0 {
                    seconds = -negative_secs;
                    nanoseconds = 0;
                } else {
                    // For example if `system_time` was 4.3 seconds before
                    // the Unix epoch we get a Duration that represents
                    // `(-4, -0.3)` but we want `(-5, +0.7)`:
                    seconds = -1 - negative_secs;
                    nanoseconds = NSEC_PER_SEC - negative_nanos;
                }
            }
        };
        Self::new_truncate(seconds, nanoseconds)
    }
}

const NSEC_PER_SEC: u32 = 1_000_000_000;
const RANGE_MASK_31BIT: u32 = 0x7FFF_FFFF;

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
        mode_size: Option<(u32, u32)>,
        mtime: Option<TruncatedTimestamp>,
        fallback_exec: Option<bool>,
        fallback_symlink: Option<bool>,
    ) -> Self {
        if let Some((mode, size)) = mode_size {
            // TODO: return an error for out of range values?
            assert!(mode & !RANGE_MASK_31BIT == 0);
            assert!(size & !RANGE_MASK_31BIT == 0);
        }
        let mut flags = Flags::empty();
        flags.set(Flags::WDIR_TRACKED, wdir_tracked);
        flags.set(Flags::P1_TRACKED, p1_tracked);
        flags.set(Flags::P2_INFO, p2_info);
        if let Some(exec) = fallback_exec {
            flags.insert(Flags::HAS_FALLBACK_EXEC);
            if exec {
                flags.insert(Flags::FALLBACK_EXEC);
            }
        }
        if let Some(exec) = fallback_symlink {
            flags.insert(Flags::HAS_FALLBACK_SYMLINK);
            if exec {
                flags.insert(Flags::FALLBACK_SYMLINK);
            }
        }
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
                    Self {
                        flags: Flags::WDIR_TRACKED | Flags::P1_TRACKED,
                        mode_size: None,
                        mtime: None,
                    }
                } else if mtime == MTIME_UNSET {
                    // TODO: return an error for negative values?
                    let mode = u32::try_from(mode).unwrap();
                    let size = u32::try_from(size).unwrap();
                    Self {
                        flags: Flags::WDIR_TRACKED | Flags::P1_TRACKED,
                        mode_size: Some((mode, size)),
                        mtime: None,
                    }
                } else {
                    // TODO: return an error for negative values?
                    let mode = u32::try_from(mode).unwrap();
                    let size = u32::try_from(size).unwrap();
                    let mtime = u32::try_from(mtime).unwrap();
                    let mtime =
                        TruncatedTimestamp::from_already_truncated(mtime, 0)
                            .unwrap();
                    Self {
                        flags: Flags::WDIR_TRACKED | Flags::P1_TRACKED,
                        mode_size: Some((mode, size)),
                        mtime: Some(mtime),
                    }
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
    ) -> (
        bool,
        bool,
        bool,
        Option<(u32, u32)>,
        Option<TruncatedTimestamp>,
        Option<bool>,
        Option<bool>,
    ) {
        if !self.any_tracked() {
            // TODO: return an Option instead?
            panic!("Accessing v1_state of an untracked DirstateEntry")
        }
        let wdir_tracked = self.flags.contains(Flags::WDIR_TRACKED);
        let p1_tracked = self.flags.contains(Flags::P1_TRACKED);
        let p2_info = self.flags.contains(Flags::P2_INFO);
        let mode_size = self.mode_size;
        let mtime = self.mtime;
        (
            wdir_tracked,
            p1_tracked,
            p2_info,
            mode_size,
            mtime,
            self.get_fallback_exec(),
            self.get_fallback_symlink(),
        )
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
            i32::try_from(mode).unwrap()
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
            i32::try_from(size).unwrap()
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
        } else if let Some(mtime) = self.mtime {
            i32::try_from(mtime.truncated_seconds()).unwrap()
        } else {
            MTIME_UNSET
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

    pub fn get_fallback_exec(&self) -> Option<bool> {
        if self.flags.contains(Flags::HAS_FALLBACK_EXEC) {
            Some(self.flags.contains(Flags::FALLBACK_EXEC))
        } else {
            None
        }
    }

    pub fn set_fallback_exec(&mut self, value: Option<bool>) {
        match value {
            None => {
                self.flags.remove(Flags::HAS_FALLBACK_EXEC);
                self.flags.remove(Flags::FALLBACK_EXEC);
            }
            Some(exec) => {
                self.flags.insert(Flags::HAS_FALLBACK_EXEC);
                if exec {
                    self.flags.insert(Flags::FALLBACK_EXEC);
                }
            }
        }
    }

    pub fn get_fallback_symlink(&self) -> Option<bool> {
        if self.flags.contains(Flags::HAS_FALLBACK_SYMLINK) {
            Some(self.flags.contains(Flags::FALLBACK_SYMLINK))
        } else {
            None
        }
    }

    pub fn set_fallback_symlink(&mut self, value: Option<bool>) {
        match value {
            None => {
                self.flags.remove(Flags::HAS_FALLBACK_SYMLINK);
                self.flags.remove(Flags::FALLBACK_SYMLINK);
            }
            Some(symlink) => {
                self.flags.insert(Flags::HAS_FALLBACK_SYMLINK);
                if symlink {
                    self.flags.insert(Flags::FALLBACK_SYMLINK);
                }
            }
        }
    }

    pub fn truncated_mtime(&self) -> Option<TruncatedTimestamp> {
        self.mtime
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

    pub fn set_clean(
        &mut self,
        mode: u32,
        size: u32,
        mtime: TruncatedTimestamp,
    ) {
        let size = size & RANGE_MASK_31BIT;
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
        let dirstate_exec_bit = (self.mode() as u32 & EXEC_BIT_MASK) != 0;
        let fs_exec_bit = has_exec_bit(filesystem_metadata);
        dirstate_exec_bit != fs_exec_bit
    }

    /// Returns a `(state, mode, size, mtime)` tuple as for
    /// `DirstateMapMethods::debug_iter`.
    pub fn debug_tuple(&self) -> (u8, i32, i32, i32) {
        (self.state().into(), self.mode(), self.size(), self.mtime())
    }

    /// True if the stored mtime would be ambiguous with the current time
    pub fn need_delay(&self, now: TruncatedTimestamp) -> bool {
        if let Some(mtime) = self.mtime {
            self.state() == EntryState::Normal
                && mtime.truncated_seconds() == now.truncated_seconds()
        } else {
            false
        }
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

const EXEC_BIT_MASK: u32 = 0o100;

pub fn has_exec_bit(metadata: &std::fs::Metadata) -> bool {
    // TODO: How to handle executable permissions on Windows?
    use std::os::unix::fs::MetadataExt;
    (metadata.mode() & EXEC_BIT_MASK) != 0
}

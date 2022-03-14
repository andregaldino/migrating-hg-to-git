//! Filesystem-based locks for local repositories

use crate::errors::HgError;
use crate::errors::HgResultExt;
use crate::utils::StrExt;
use crate::vfs::Vfs;
use std::io;
use std::io::ErrorKind;

#[derive(derive_more::From)]
pub enum LockError {
    AlreadyHeld,
    #[from]
    Other(HgError),
}

/// Try to call `f` with the lock acquired, without waiting.
///
/// If the lock is aready held, `f` is not called and `LockError::AlreadyHeld`
/// is returned. `LockError::Io` is returned for any unexpected I/O error
/// accessing the lock file, including for removing it after `f` was called.
/// The return value of `f` is dropped in that case. If all is successful, the
/// return value of `f` is forwarded.
pub fn try_with_lock_no_wait<R>(
    hg_vfs: Vfs,
    lock_filename: &str,
    f: impl FnOnce() -> R,
) -> Result<R, LockError> {
    let our_lock_data = &*OUR_LOCK_DATA;
    for _retry in 0..5 {
        match make_lock(hg_vfs, lock_filename, our_lock_data) {
            Ok(()) => {
                let result = f();
                unlock(hg_vfs, lock_filename)?;
                return Ok(result);
            }
            Err(HgError::IoError { error, .. })
                if error.kind() == ErrorKind::AlreadyExists =>
            {
                let lock_data = read_lock(hg_vfs, lock_filename)?;
                if lock_data.is_none() {
                    // Lock was apparently just released, retry acquiring it
                    continue;
                }
                if !lock_should_be_broken(&lock_data) {
                    return Err(LockError::AlreadyHeld);
                }
                // The lock file is left over from a process not running
                // anymore. Break it, but with another lock to
                // avoid a race.
                break_lock(hg_vfs, lock_filename)?;

                // Retry acquiring
            }
            Err(error) => Err(error)?,
        }
    }
    Err(LockError::AlreadyHeld)
}

fn break_lock(hg_vfs: Vfs, lock_filename: &str) -> Result<(), LockError> {
    try_with_lock_no_wait(hg_vfs, &format!("{}.break", lock_filename), || {
        // Check again in case some other process broke and
        // acquired the lock in the meantime
        let lock_data = read_lock(hg_vfs, lock_filename)?;
        if !lock_should_be_broken(&lock_data) {
            return Err(LockError::AlreadyHeld);
        }
        Ok(hg_vfs.remove_file(lock_filename)?)
    })?
}

#[cfg(unix)]
fn make_lock(
    hg_vfs: Vfs,
    lock_filename: &str,
    data: &str,
) -> Result<(), HgError> {
    // Use a symbolic link because creating it is atomic.
    // The link’s "target" contains data not representing any path.
    let fake_symlink_target = data;
    hg_vfs.create_symlink(lock_filename, fake_symlink_target)
}

fn read_lock(
    hg_vfs: Vfs,
    lock_filename: &str,
) -> Result<Option<String>, HgError> {
    let link_target =
        hg_vfs.read_link(lock_filename).io_not_found_as_none()?;
    if let Some(target) = link_target {
        let data = target
            .into_os_string()
            .into_string()
            .map_err(|_| HgError::corrupted("non-UTF-8 lock data"))?;
        Ok(Some(data))
    } else {
        Ok(None)
    }
}

fn unlock(hg_vfs: Vfs, lock_filename: &str) -> Result<(), HgError> {
    hg_vfs.remove_file(lock_filename)
}

/// Return whether the process that is/was holding the lock is known not to be
/// running anymore.
fn lock_should_be_broken(data: &Option<String>) -> bool {
    (|| -> Option<bool> {
        let (prefix, pid) = data.as_ref()?.split_2(':')?;
        if prefix != &*LOCK_PREFIX {
            return Some(false);
        }
        let process_is_running;

        #[cfg(unix)]
        {
            let pid: libc::pid_t = pid.parse().ok()?;
            unsafe {
                let signal = 0; // Test if we could send a signal, without sending
                let result = libc::kill(pid, signal);
                if result == 0 {
                    process_is_running = true
                } else {
                    let errno =
                        io::Error::last_os_error().raw_os_error().unwrap();
                    process_is_running = errno != libc::ESRCH
                }
            }
        }

        Some(!process_is_running)
    })()
    .unwrap_or(false)
}

lazy_static::lazy_static! {
    /// A string which is used to differentiate pid namespaces
    ///
    /// It's useful to detect "dead" processes and remove stale locks with
    /// confidence. Typically it's just hostname. On modern linux, we include an
    /// extra Linux-specific pid namespace identifier.
    static ref LOCK_PREFIX: String = {
        // Note: this must match the behavior of `_getlockprefix` in `mercurial/lock.py`

        /// Same as https://github.com/python/cpython/blob/v3.10.0/Modules/socketmodule.c#L5414
        const BUFFER_SIZE: usize = 1024;
        let mut buffer = [0 as libc::c_char; BUFFER_SIZE];
        let hostname_bytes = unsafe {
            let result = libc::gethostname(buffer.as_mut_ptr(), BUFFER_SIZE);
            if result != 0 {
                panic!("gethostname: {}", io::Error::last_os_error())
            }
            std::ffi::CStr::from_ptr(buffer.as_mut_ptr()).to_bytes()
        };
        let hostname =
            std::str::from_utf8(hostname_bytes).expect("non-UTF-8 hostname");

        #[cfg(target_os = "linux")]
        {
            use std::os::linux::fs::MetadataExt;
            match std::fs::metadata("/proc/self/ns/pid") {
                Ok(meta) => {
                    return format!("{}/{:x}", hostname, meta.st_ino())
                }
                Err(error) => {
                    // TODO: match on `error.kind()` when `NotADirectory`
                    // is available on all supported Rust versions:
                    // https://github.com/rust-lang/rust/issues/86442
                    use libc::{
                        ENOENT, // ErrorKind::NotFound
                        ENOTDIR, // ErrorKind::NotADirectory
                        EACCES, // ErrorKind::PermissionDenied
                    };
                    match error.raw_os_error() {
                        Some(ENOENT) | Some(ENOTDIR) | Some(EACCES) => {}
                        _ => panic!("stat /proc/self/ns/pid: {}", error),
                    }
                }
            }
        }

        hostname.to_owned()
    };

    static ref OUR_LOCK_DATA: String = format!("{}:{}", &*LOCK_PREFIX, std::process::id());
}

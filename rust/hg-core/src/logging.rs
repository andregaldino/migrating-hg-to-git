use crate::errors::{HgError, HgResultExt, IoErrorContext, IoResultExt};
use crate::vfs::Vfs;
use std::io::Write;

/// An utility to append to a log file with the given name, and optionally
/// rotate it after it reaches a certain maximum size.
///
/// Rotation works by renaming "example.log" to "example.log.1", after renaming
/// "example.log.1" to "example.log.2" etc up to the given maximum number of
/// files.
pub struct LogFile<'a> {
    vfs: Vfs<'a>,
    name: &'a str,
    max_size: Option<u64>,
    max_files: u32,
}

impl<'a> LogFile<'a> {
    pub fn new(vfs: Vfs<'a>, name: &'a str) -> Self {
        Self {
            vfs,
            name,
            max_size: None,
            max_files: 0,
        }
    }

    /// Rotate before writing to a log file that was already larger than the
    /// given size, in bytes. `None` disables rotation.
    pub fn max_size(mut self, value: Option<u64>) -> Self {
        self.max_size = value;
        self
    }

    /// Keep this many rotated files `{name}.1` up to `{name}.{max}`, in
    /// addition to the original `{name}` file.
    pub fn max_files(mut self, value: u32) -> Self {
        self.max_files = value;
        self
    }

    /// Append the given `bytes` as-is to the log file, after rotating if
    /// needed.
    ///
    /// No trailing newline is added. Make sure to include one in `bytes` if
    /// desired.
    pub fn write(&self, bytes: &[u8]) -> Result<(), HgError> {
        let path = self.vfs.join(self.name);
        let context = || IoErrorContext::WritingFile(path.clone());
        let open = || {
            std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&path)
                .with_context(context)
        };
        let mut file = open()?;
        if let Some(max_size) = self.max_size {
            if file.metadata().with_context(context)?.len() >= max_size {
                // For example with `max_files == 5`, the first iteration of
                // this loop has `i == 4` and renames `{name}.4` to `{name}.5`.
                // The last iteration renames `{name}.1` to
                // `{name}.2`
                for i in (1..self.max_files).rev() {
                    self.vfs
                        .rename(
                            format!("{}.{}", self.name, i),
                            format!("{}.{}", self.name, i + 1),
                        )
                        .io_not_found_as_none()?;
                }
                // Then rename `{name}` to `{name}.1`. This is the
                // previously-opened `file`.
                self.vfs
                    .rename(self.name, format!("{}.1", self.name))
                    .io_not_found_as_none()?;
                // Finally, create a new `{name}` file and replace our `file`
                // handle.
                file = open()?;
            }
        }
        file.write_all(bytes).with_context(context)?;
        file.sync_all().with_context(context)
    }
}

#[test]
fn test_rotation() {
    let temp = tempfile::tempdir().unwrap();
    let vfs = Vfs { base: temp.path() };
    let logger = LogFile::new(vfs, "log").max_size(Some(3)).max_files(2);
    logger.write(b"one\n").unwrap();
    logger.write(b"two\n").unwrap();
    logger.write(b"3\n").unwrap();
    logger.write(b"four\n").unwrap();
    logger.write(b"five\n").unwrap();
    assert_eq!(vfs.read("log").unwrap(), b"five\n");
    assert_eq!(vfs.read("log.1").unwrap(), b"3\nfour\n");
    assert_eq!(vfs.read("log.2").unwrap(), b"two\n");
    assert!(vfs.read("log.3").io_not_found_as_none().unwrap().is_none());
}

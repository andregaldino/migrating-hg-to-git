//! Logging for repository events, including commands run in the repository.

use crate::CliInvocation;
use format_bytes::format_bytes;
use hg::errors::HgError;
use hg::repo::Repo;
use hg::utils::{files::get_bytes_from_os_str, shell_quote};
use std::ffi::OsString;

const ONE_MEBIBYTE: u64 = 1 << 20;

// TODO: somehow keep defaults in sync with `configitem` in `hgext/blackbox.py`
const DEFAULT_MAX_SIZE: u64 = ONE_MEBIBYTE;
const DEFAULT_MAX_FILES: u32 = 7;

// Python does not support %.3f, only %f
const DEFAULT_DATE_FORMAT: &str = "%Y-%m-%d %H:%M:%S%.3f";

type DateTime = chrono::DateTime<chrono::Local>;

pub struct ProcessStartTime {
    /// For measuring duration
    monotonic_clock: std::time::Instant,
    /// For formatting with year, month, day, etc.
    calendar_based: DateTime,
}

impl ProcessStartTime {
    pub fn now() -> Self {
        Self {
            monotonic_clock: std::time::Instant::now(),
            calendar_based: chrono::Local::now(),
        }
    }
}

pub struct Blackbox<'a> {
    process_start_time: &'a ProcessStartTime,
    /// Do nothing if this is `None`
    configured: Option<ConfiguredBlackbox<'a>>,
}

struct ConfiguredBlackbox<'a> {
    repo: &'a Repo,
    max_size: u64,
    max_files: u32,
    date_format: &'a str,
}

impl<'a> Blackbox<'a> {
    pub fn new(
        invocation: &'a CliInvocation<'a>,
        process_start_time: &'a ProcessStartTime,
    ) -> Result<Self, HgError> {
        let configured = if let Ok(repo) = invocation.repo {
            if invocation.config.get(b"extensions", b"blackbox").is_none() {
                // The extension is not enabled
                None
            } else {
                Some(ConfiguredBlackbox {
                    repo,
                    max_size: invocation
                        .config
                        .get_byte_size(b"blackbox", b"maxsize")?
                        .unwrap_or(DEFAULT_MAX_SIZE),
                    max_files: invocation
                        .config
                        .get_u32(b"blackbox", b"maxfiles")?
                        .unwrap_or(DEFAULT_MAX_FILES),
                    date_format: invocation
                        .config
                        .get_str(b"blackbox", b"date-format")?
                        .unwrap_or(DEFAULT_DATE_FORMAT),
                })
            }
        } else {
            // Without a local repository there’s no `.hg/blackbox.log` to
            // write to.
            None
        };
        Ok(Self {
            process_start_time,
            configured,
        })
    }

    pub fn log_command_start<'arg>(
        &self,
        argv: impl Iterator<Item = &'arg OsString>,
    ) {
        if let Some(configured) = &self.configured {
            let message = format_bytes!(b"(rust) {}", format_cli_args(argv));
            configured.log(&self.process_start_time.calendar_based, &message);
        }
    }

    pub fn log_command_end<'arg>(
        &self,
        argv: impl Iterator<Item = &'arg OsString>,
        exit_code: i32,
    ) {
        if let Some(configured) = &self.configured {
            let now = chrono::Local::now();
            let duration = self
                .process_start_time
                .monotonic_clock
                .elapsed()
                .as_secs_f64();
            let message = format_bytes!(
                b"(rust) {} exited {} after {} seconds",
                format_cli_args(argv),
                exit_code,
                format_bytes::Utf8(format_args!("{:.03}", duration))
            );
            configured.log(&now, &message);
        }
    }
}

impl ConfiguredBlackbox<'_> {
    fn log(&self, date_time: &DateTime, message: &[u8]) {
        let date = format_bytes::Utf8(date_time.format(self.date_format));
        let user = users::get_current_username().map(get_bytes_from_os_str);
        let user = user.as_deref().unwrap_or(b"???");
        let rev = format_bytes::Utf8(match self.repo.dirstate_parents() {
            Ok(parents) if parents.p2 == hg::revlog::node::NULL_NODE => {
                format!("{:x}", parents.p1)
            }
            Ok(parents) => format!("{:x}+{:x}", parents.p1, parents.p2),
            Err(_dirstate_corruption_error) => {
                // TODO: log a non-fatal warning to stderr
                "???".to_owned()
            }
        });
        let pid = std::process::id();
        let line = format_bytes!(
            b"{} {} @{} ({})> {}\n",
            date,
            user,
            rev,
            pid,
            message
        );
        let result =
            hg::logging::LogFile::new(self.repo.hg_vfs(), "blackbox.log")
                .max_size(Some(self.max_size))
                .max_files(self.max_files)
                .write(&line);
        match result {
            Ok(()) => {}
            Err(_io_error) => {
                // TODO: log a non-fatal warning to stderr
            }
        }
    }
}

fn format_cli_args<'a>(
    mut args: impl Iterator<Item = &'a OsString>,
) -> Vec<u8> {
    let _ = args.next(); // Skip the first (or zeroth) arg, the name of the `rhg` executable
    let mut args = args.map(|arg| shell_quote(&get_bytes_from_os_str(arg)));
    let mut formatted = Vec::new();
    if let Some(arg) = args.next() {
        formatted.extend(arg)
    }
    for arg in args {
        formatted.push(b' ');
        formatted.extend(arg)
    }
    formatted
}

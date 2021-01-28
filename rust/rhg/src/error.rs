use crate::ui::utf8_to_local;
use crate::ui::UiError;
use format_bytes::format_bytes;
use hg::errors::HgError;
use hg::repo::RepoFindError;
use hg::revlog::revlog::RevlogError;
use hg::utils::files::get_bytes_from_path;
use std::convert::From;

/// The kind of command error
#[derive(Debug)]
pub enum CommandError {
    /// Exit with an error message and "standard" failure exit code.
    Abort { message: Vec<u8> },

    /// A mercurial capability as not been implemented.
    ///
    /// There is no error message printed in this case.
    /// Instead, we exit with a specic status code and a wrapper script may
    /// fallback to Python-based Mercurial.
    Unimplemented,
}

impl CommandError {
    pub fn abort(message: impl AsRef<str>) -> Self {
        CommandError::Abort {
            // TODO: bytes-based (instead of Unicode-based) formatting
            // of error messages to handle non-UTF-8 filenames etc:
            // https://www.mercurial-scm.org/wiki/EncodingStrategy#Mixing_output
            message: utf8_to_local(message.as_ref()).into(),
        }
    }
}

impl From<HgError> for CommandError {
    fn from(error: HgError) -> Self {
        match error {
            HgError::UnsupportedFeature(_) => CommandError::Unimplemented,
            _ => CommandError::abort(error.to_string()),
        }
    }
}

impl From<UiError> for CommandError {
    fn from(_error: UiError) -> Self {
        // If we already failed writing to stdout or stderr,
        // writing an error message to stderr about it would be likely to fail
        // too.
        CommandError::abort("")
    }
}

impl From<RepoFindError> for CommandError {
    fn from(error: RepoFindError) -> Self {
        match error {
            RepoFindError::NotFoundInCurrentDirectoryOrAncestors {
                current_directory,
            } => CommandError::Abort {
                message: format_bytes!(
                    b"no repository found in '{}' (.hg not found)!",
                    get_bytes_from_path(current_directory)
                ),
            },
            RepoFindError::Other(error) => error.into(),
        }
    }
}

impl From<(RevlogError, &str)> for CommandError {
    fn from((err, rev): (RevlogError, &str)) -> CommandError {
        match err {
            RevlogError::InvalidRevision => CommandError::abort(format!(
                "invalid revision identifier {}",
                rev
            )),
            RevlogError::AmbiguousPrefix => CommandError::abort(format!(
                "ambiguous revision identifier {}",
                rev
            )),
            RevlogError::Other(error) => error.into(),
        }
    }
}

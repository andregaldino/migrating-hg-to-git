use crate::exitcode;
use crate::ui::utf8_to_local;
use crate::ui::UiError;
use format_bytes::format_bytes;
use hg::operations::{FindRootError, ListDirstateTrackedFilesError};
use hg::requirements::RequirementsError;
use hg::revlog::revlog::RevlogError;
use hg::utils::files::get_bytes_from_path;
use std::convert::From;
use std::path::PathBuf;

/// The kind of command error
#[derive(Debug, derive_more::From)]
pub enum CommandError {
    /// The root of the repository cannot be found
    RootNotFound(PathBuf),
    /// The current directory cannot be found
    CurrentDirNotFound(std::io::Error),
    /// `.hg/requires`
    #[from]
    RequirementsError(RequirementsError),
    /// The standard output stream cannot be written to
    StdoutError,
    /// The standard error stream cannot be written to
    StderrError,
    /// The command aborted
    Abort(Option<Vec<u8>>),
    /// A mercurial capability as not been implemented.
    Unimplemented,
}

impl CommandError {
    pub fn get_exit_code(&self) -> exitcode::ExitCode {
        match self {
            CommandError::RootNotFound(_) => exitcode::ABORT,
            CommandError::CurrentDirNotFound(_) => exitcode::ABORT,
            CommandError::RequirementsError(
                RequirementsError::Unsupported { .. },
            ) => exitcode::UNIMPLEMENTED_COMMAND,
            CommandError::RequirementsError(_) => exitcode::ABORT,
            CommandError::StdoutError => exitcode::ABORT,
            CommandError::StderrError => exitcode::ABORT,
            CommandError::Abort(_) => exitcode::ABORT,
            CommandError::Unimplemented => exitcode::UNIMPLEMENTED_COMMAND,
        }
    }

    /// Return the message corresponding to the error if any
    pub fn get_error_message_bytes(&self) -> Option<Vec<u8>> {
        match self {
            CommandError::RootNotFound(path) => {
                let bytes = get_bytes_from_path(path);
                Some(format_bytes!(
                    b"abort: no repository found in '{}' (.hg not found)!\n",
                    bytes.as_slice()
                ))
            }
            CommandError::CurrentDirNotFound(e) => Some(format_bytes!(
                b"abort: error getting current working directory: {}\n",
                e.to_string().as_bytes(),
            )),
            CommandError::RequirementsError(RequirementsError::Corrupted) => {
                Some(
                    "abort: .hg/requires is corrupted\n".as_bytes().to_owned(),
                )
            }
            CommandError::Abort(message) => message.to_owned(),
            _ => None,
        }
    }

    /// Exist the process with the corresponding exit code.
    pub fn exit(&self) {
        std::process::exit(self.get_exit_code())
    }
}

impl From<UiError> for CommandError {
    fn from(error: UiError) -> Self {
        match error {
            UiError::StdoutError(_) => CommandError::StdoutError,
            UiError::StderrError(_) => CommandError::StderrError,
        }
    }
}

impl From<FindRootError> for CommandError {
    fn from(err: FindRootError) -> Self {
        match err {
            FindRootError::RootNotFound(path) => {
                CommandError::RootNotFound(path)
            }
            FindRootError::GetCurrentDirError(e) => {
                CommandError::CurrentDirNotFound(e)
            }
        }
    }
}

impl From<(RevlogError, &str)> for CommandError {
    fn from((err, rev): (RevlogError, &str)) -> CommandError {
        match err {
            RevlogError::IoError(err) => CommandError::Abort(Some(
                utf8_to_local(&format!("abort: {}\n", err)).into(),
            )),
            RevlogError::InvalidRevision => CommandError::Abort(Some(
                utf8_to_local(&format!(
                    "abort: invalid revision identifier {}\n",
                    rev
                ))
                .into(),
            )),
            RevlogError::AmbiguousPrefix => CommandError::Abort(Some(
                utf8_to_local(&format!(
                    "abort: ambiguous revision identifier {}\n",
                    rev
                ))
                .into(),
            )),
            RevlogError::UnsuportedVersion(version) => {
                CommandError::Abort(Some(
                    utf8_to_local(&format!(
                        "abort: unsupported revlog version {}\n",
                        version
                    ))
                    .into(),
                ))
            }
            RevlogError::Corrupted => {
                CommandError::Abort(Some("abort: corrupted revlog\n".into()))
            }
            RevlogError::UnknowDataFormat(format) => {
                CommandError::Abort(Some(
                    utf8_to_local(&format!(
                        "abort: unknow revlog dataformat {:?}\n",
                        format
                    ))
                    .into(),
                ))
            }
        }
    }
}

impl From<ListDirstateTrackedFilesError> for CommandError {
    fn from(err: ListDirstateTrackedFilesError) -> Self {
        match err {
            ListDirstateTrackedFilesError::IoError(err) => {
                CommandError::Abort(Some(
                    utf8_to_local(&format!("abort: {}\n", err)).into(),
                ))
            }
            ListDirstateTrackedFilesError::ParseError(_) => {
                CommandError::Abort(Some(
                    // TODO find a better error message
                    b"abort: parse error\n".to_vec(),
                ))
            }
        }
    }
}

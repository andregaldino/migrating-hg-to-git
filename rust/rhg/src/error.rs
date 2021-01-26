use crate::exitcode;
use crate::ui::UiError;
use format_bytes::format_bytes;
use hg::operations::FindRootError;
use hg::requirements::RequirementsError;
use hg::utils::files::get_bytes_from_path;
use std::convert::From;
use std::path::PathBuf;

/// The kind of command error
#[derive(Debug)]
pub enum CommandError {
    /// The root of the repository cannot be found
    RootNotFound(PathBuf),
    /// The current directory cannot be found
    CurrentDirNotFound(std::io::Error),
    /// `.hg/requires`
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

impl From<RequirementsError> for CommandError {
    fn from(err: RequirementsError) -> Self {
        CommandError::RequirementsError(err)
    }
}

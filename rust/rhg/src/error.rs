use crate::exitcode;
use crate::ui::UiError;
use hg::operations::{FindRootError, FindRootErrorKind};
use hg::utils::files::get_bytes_from_path;
use std::convert::From;
use std::path::PathBuf;

/// The kind of command error
#[derive(Debug)]
pub enum CommandErrorKind {
    /// The root of the repository cannot be found
    RootNotFound(PathBuf),
    /// The current directory cannot be found
    CurrentDirNotFound(std::io::Error),
    /// The standard output stream cannot be written to
    StdoutError,
    /// The standard error stream cannot be written to
    StderrError,
    /// The command aborted
    Abort(Option<Vec<u8>>),
    /// A mercurial capability as not been implemented.
    Unimplemented,
}

impl CommandErrorKind {
    pub fn get_exit_code(&self) -> exitcode::ExitCode {
        match self {
            CommandErrorKind::RootNotFound(_) => exitcode::ABORT,
            CommandErrorKind::CurrentDirNotFound(_) => exitcode::ABORT,
            CommandErrorKind::StdoutError => exitcode::ABORT,
            CommandErrorKind::StderrError => exitcode::ABORT,
            CommandErrorKind::Abort(_) => exitcode::ABORT,
            CommandErrorKind::Unimplemented => exitcode::UNIMPLEMENTED_COMMAND,
        }
    }

    /// Return the message corresponding to the error kind if any
    pub fn get_error_message_bytes(&self) -> Option<Vec<u8>> {
        match self {
            // TODO use formating macro
            CommandErrorKind::RootNotFound(path) => {
                let bytes = get_bytes_from_path(path);
                Some(
                    [
                        b"abort: no repository found in '",
                        bytes.as_slice(),
                        b"' (.hg not found)!\n",
                    ]
                    .concat(),
                )
            }
            // TODO use formating macro
            CommandErrorKind::CurrentDirNotFound(e) => Some(
                [
                    b"abort: error getting current working directory: ",
                    e.to_string().as_bytes(),
                    b"\n",
                ]
                .concat(),
            ),
            CommandErrorKind::Abort(message) => message.to_owned(),
            _ => None,
        }
    }
}

/// The error type for the Command trait
#[derive(Debug)]
pub struct CommandError {
    pub kind: CommandErrorKind,
}

impl CommandError {
    /// Exist the process with the corresponding exit code.
    pub fn exit(&self) {
        std::process::exit(self.kind.get_exit_code())
    }

    /// Return the message corresponding to the command error if any
    pub fn get_error_message_bytes(&self) -> Option<Vec<u8>> {
        self.kind.get_error_message_bytes()
    }
}

impl From<CommandErrorKind> for CommandError {
    fn from(kind: CommandErrorKind) -> Self {
        CommandError { kind }
    }
}

impl From<UiError> for CommandError {
    fn from(error: UiError) -> Self {
        CommandError {
            kind: match error {
                UiError::StdoutError(_) => CommandErrorKind::StdoutError,
                UiError::StderrError(_) => CommandErrorKind::StderrError,
            },
        }
    }
}

impl From<FindRootError> for CommandError {
    fn from(err: FindRootError) -> Self {
        match err.kind {
            FindRootErrorKind::RootNotFound(path) => CommandError {
                kind: CommandErrorKind::RootNotFound(path),
            },
            FindRootErrorKind::GetCurrentDirError(e) => CommandError {
                kind: CommandErrorKind::CurrentDirNotFound(e),
            },
        }
    }
}

use crate::exitcode;
use crate::ui::UiError;
use std::convert::From;

/// The kind of command error
#[derive(Debug, PartialEq)]
pub enum CommandErrorKind {
    /// The command finished without error
    Ok,
    /// The root of the repository cannot be found
    RootNotFound,
    /// The current directory cannot be found
    CurrentDirNotFound,
    /// The standard output stream cannot be written to
    StdoutError,
    /// The standard error stream cannot be written to
    StderrError,
}

impl CommandErrorKind {
    pub fn get_exit_code(&self) -> exitcode::ExitCode {
        match self {
            CommandErrorKind::Ok => exitcode::OK,
            CommandErrorKind::RootNotFound => exitcode::ABORT,
            CommandErrorKind::CurrentDirNotFound => exitcode::ABORT,
            CommandErrorKind::StdoutError => exitcode::ABORT,
            CommandErrorKind::StderrError => exitcode::ABORT,
        }
    }
}

/// The error type for the Command trait
#[derive(Debug, PartialEq)]
pub struct CommandError {
    pub kind: CommandErrorKind,
}

impl CommandError {
    /// Exist the process with the corresponding exit code.
    pub fn exit(&self) -> () {
        std::process::exit(self.kind.get_exit_code())
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

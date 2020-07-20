pub type ExitCode = i32;

/// Successful exit
pub const OK: ExitCode = 0;

/// Generic abort
pub const ABORT: ExitCode = 255;

/// Command not implemented by rhg
pub const UNIMPLEMENTED_COMMAND: ExitCode = 252;

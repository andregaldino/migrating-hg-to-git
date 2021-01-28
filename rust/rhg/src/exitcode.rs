pub type ExitCode = i32;

/// Successful exit
pub const OK: ExitCode = 0;

/// Generic abort
pub const ABORT: ExitCode = 255;

/// Command or feature not implemented by rhg
pub const UNIMPLEMENTED: ExitCode = 252;

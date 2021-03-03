pub type ExitCode = i32;

/// Successful exit
pub const OK: ExitCode = 0;

/// Generic abort
pub const ABORT: ExitCode = 255;

/// Generic something completed but did not succeed
pub const UNSUCCESSFUL: ExitCode = 1;

/// Command or feature not implemented by rhg
pub const UNIMPLEMENTED: ExitCode = 252;

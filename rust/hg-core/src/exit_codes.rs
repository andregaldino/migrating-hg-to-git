pub type ExitCode = i32;

/// Successful exit
pub const OK: ExitCode = 0;

/// Generic abort
pub const ABORT: ExitCode = 255;

// Abort when there is a config related error
pub const CONFIG_ERROR_ABORT: ExitCode = 30;

// Abort when there is an error while parsing config
pub const CONFIG_PARSE_ERROR_ABORT: ExitCode = 10;

/// Generic something completed but did not succeed
pub const UNSUCCESSFUL: ExitCode = 1;

/// Command or feature not implemented by rhg
pub const UNIMPLEMENTED: ExitCode = 252;

use std::fmt;

/// Common error cases that can happen in many different APIs
#[derive(Debug)]
pub enum HgError {
    IoError {
        error: std::io::Error,
        context: IoErrorContext,
    },

    /// A file under `.hg/` normally only written by Mercurial
    ///
    /// The given string is a short explanation for users, not intended to be
    /// machine-readable.
    CorruptedRepository(String),

    /// The respository or requested operation involves a feature not
    /// supported by the Rust implementation. Falling back to the Python
    /// implementation may or may not work.
    ///
    /// The given string is a short explanation for users, not intended to be
    /// machine-readable.
    UnsupportedFeature(String),
}

/// Details about where an I/O error happened
#[derive(Debug, derive_more::From)]
pub enum IoErrorContext {
    /// A filesystem operation returned `std::io::Error`
    #[from]
    File(std::path::PathBuf),
    /// `std::env::current_dir` returned `std::io::Error`
    CurrentDir,
}

impl HgError {
    pub fn corrupted(explanation: impl Into<String>) -> Self {
        HgError::CorruptedRepository(explanation.into())
    }
}

// TODO: use `DisplayBytes` instead to show non-Unicode filenames losslessly?
impl fmt::Display for HgError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            HgError::IoError { error, context } => {
                write!(f, "{}: {}", error, context)
            }
            HgError::CorruptedRepository(explanation) => {
                write!(f, "corrupted repository: {}", explanation)
            }
            HgError::UnsupportedFeature(explanation) => {
                write!(f, "unsupported feature: {}", explanation)
            }
        }
    }
}

// TODO: use `DisplayBytes` instead to show non-Unicode filenames losslessly?
impl fmt::Display for IoErrorContext {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            IoErrorContext::File(path) => path.display().fmt(f),
            IoErrorContext::CurrentDir => f.write_str("current directory"),
        }
    }
}

pub trait IoResultExt<T> {
    /// Annotate a possible I/O error as related to a file at the given path.
    ///
    /// This allows printing something like “File not found: example.txt”
    /// instead of just “File not found”.
    ///
    /// Converts a `Result` with `std::io::Error` into one with `HgError`.
    fn for_file(self, path: &std::path::Path) -> Result<T, HgError>;
}

impl<T> IoResultExt<T> for std::io::Result<T> {
    fn for_file(self, path: &std::path::Path) -> Result<T, HgError> {
        self.map_err(|error| HgError::IoError {
            error,
            context: IoErrorContext::File(path.to_owned()),
        })
    }
}

pub trait HgResultExt<T> {
    /// Handle missing files separately from other I/O error cases.
    ///
    /// Wraps the `Ok` type in an `Option`:
    ///
    /// * `Ok(x)` becomes `Ok(Some(x))`
    /// * An I/O "not found" error becomes `Ok(None)`
    /// * Other errors are unchanged
    fn io_not_found_as_none(self) -> Result<Option<T>, HgError>;
}

impl<T> HgResultExt<T> for Result<T, HgError> {
    fn io_not_found_as_none(self) -> Result<Option<T>, HgError> {
        match self {
            Ok(x) => Ok(Some(x)),
            Err(HgError::IoError { error, .. })
                if error.kind() == std::io::ErrorKind::NotFound =>
            {
                Ok(None)
            }
            Err(other_error) => Err(other_error),
        }
    }
}

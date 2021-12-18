use format_bytes::format_bytes;
use std::borrow::Cow;
use std::env;
use std::io;
use std::io::{ErrorKind, Write};

#[derive(Debug)]
pub struct Ui {
    stdout: std::io::Stdout,
    stderr: std::io::Stderr,
}

/// The kind of user interface error
pub enum UiError {
    /// The standard output stream cannot be written to
    StdoutError(io::Error),
    /// The standard error stream cannot be written to
    StderrError(io::Error),
}

/// The commandline user interface
impl Ui {
    pub fn new() -> Self {
        Ui {
            stdout: std::io::stdout(),
            stderr: std::io::stderr(),
        }
    }

    /// Returns a buffered handle on stdout for faster batch printing
    /// operations.
    pub fn stdout_buffer(&self) -> StdoutBuffer<std::io::StdoutLock> {
        StdoutBuffer::new(self.stdout.lock())
    }

    /// Write bytes to stdout
    pub fn write_stdout(&self, bytes: &[u8]) -> Result<(), UiError> {
        let mut stdout = self.stdout.lock();

        stdout.write_all(bytes).or_else(handle_stdout_error)?;

        stdout.flush().or_else(handle_stdout_error)
    }

    /// Write bytes to stderr
    pub fn write_stderr(&self, bytes: &[u8]) -> Result<(), UiError> {
        let mut stderr = self.stderr.lock();

        stderr.write_all(bytes).or_else(handle_stderr_error)?;

        stderr.flush().or_else(handle_stderr_error)
    }

    /// Return whether plain mode is active.
    ///
    /// Plain mode means that all configuration variables which affect
    /// the behavior and output of Mercurial should be
    /// ignored. Additionally, the output should be stable,
    /// reproducible and suitable for use in scripts or applications.
    ///
    /// The only way to trigger plain mode is by setting either the
    /// `HGPLAIN' or `HGPLAINEXCEPT' environment variables.
    ///
    /// The return value can either be
    /// - False if HGPLAIN is not set, or feature is in HGPLAINEXCEPT
    /// - False if feature is disabled by default and not included in HGPLAIN
    /// - True otherwise
    pub fn plain(&self) -> bool {
        // TODO: add support for HGPLAINEXCEPT
        env::var_os("HGPLAIN").is_some()
    }
}

/// A buffered stdout writer for faster batch printing operations.
pub struct StdoutBuffer<W: Write> {
    buf: io::BufWriter<W>,
}

impl<W: Write> StdoutBuffer<W> {
    pub fn new(writer: W) -> Self {
        let buf = io::BufWriter::new(writer);
        Self { buf }
    }

    /// Write bytes to stdout buffer
    pub fn write_all(&mut self, bytes: &[u8]) -> Result<(), UiError> {
        self.buf.write_all(bytes).or_else(handle_stdout_error)
    }

    /// Flush bytes to stdout
    pub fn flush(&mut self) -> Result<(), UiError> {
        self.buf.flush().or_else(handle_stdout_error)
    }
}

/// Sometimes writing to stdout is not possible, try writing to stderr to
/// signal that failure, otherwise just bail.
fn handle_stdout_error(error: io::Error) -> Result<(), UiError> {
    if let ErrorKind::BrokenPipe = error.kind() {
        // This makes `| head` work for example
        return Ok(());
    }
    let mut stderr = io::stderr();

    stderr
        .write_all(&format_bytes!(
            b"abort: {}\n",
            error.to_string().as_bytes()
        ))
        .map_err(UiError::StderrError)?;

    stderr.flush().map_err(UiError::StderrError)?;

    Err(UiError::StdoutError(error))
}

/// Sometimes writing to stderr is not possible.
fn handle_stderr_error(error: io::Error) -> Result<(), UiError> {
    // A broken pipe should not result in a error
    // like with `| head` for example
    if let ErrorKind::BrokenPipe = error.kind() {
        return Ok(());
    }
    Err(UiError::StdoutError(error))
}

/// Encode rust strings according to the user system.
pub fn utf8_to_local(s: &str) -> Cow<[u8]> {
    // TODO encode for the user's system //
    let bytes = s.as_bytes();
    Cow::Borrowed(bytes)
}

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

        self.write_stream(&mut stdout, bytes)
            .or_else(|e| self.handle_stdout_error(e))?;

        stdout.flush().or_else(|e| self.handle_stdout_error(e))
    }

    /// Sometimes writing to stdout is not possible, try writing to stderr to
    /// signal that failure, otherwise just bail.
    fn handle_stdout_error(&self, error: io::Error) -> Result<(), UiError> {
        self.write_stderr(
            &[b"abort: ", error.to_string().as_bytes(), b"\n"].concat(),
        )?;
        Err(UiError::StdoutError(error))
    }

    /// Write bytes to stderr
    pub fn write_stderr(&self, bytes: &[u8]) -> Result<(), UiError> {
        let mut stderr = self.stderr.lock();

        self.write_stream(&mut stderr, bytes)
            .or_else(|e| Err(UiError::StderrError(e)))?;

        stderr.flush().or_else(|e| Err(UiError::StderrError(e)))
    }

    fn write_stream(
        &self,
        stream: &mut impl Write,
        bytes: &[u8],
    ) -> Result<(), io::Error> {
        stream.write_all(bytes)
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
        self.buf.write_all(bytes).or_else(|e| self.io_err(e))
    }

    /// Flush bytes to stdout
    pub fn flush(&mut self) -> Result<(), UiError> {
        self.buf.flush().or_else(|e| self.io_err(e))
    }

    fn io_err(&self, error: io::Error) -> Result<(), UiError> {
        if let ErrorKind::BrokenPipe = error.kind() {
            // This makes `| head` work for example
            return Ok(());
        }
        let mut stderr = io::stderr();

        stderr
            .write_all(
                &[b"abort: ", error.to_string().as_bytes(), b"\n"].concat(),
            )
            .map_err(|e| UiError::StderrError(e))?;

        stderr.flush().map_err(|e| UiError::StderrError(e))?;

        Err(UiError::StdoutError(error))
    }
}

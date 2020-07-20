use std::io;
use std::io::Write;

pub struct Ui {}

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
        Ui {}
    }

    /// Write bytes to stdout
    pub fn write_stdout(&self, bytes: &[u8]) -> Result<(), UiError> {
        let mut stdout = io::stdout();

        self.write_stream(&mut stdout, bytes)
            .or_else(|e| self.into_stdout_error(e))?;

        stdout.flush().or_else(|e| self.into_stdout_error(e))
    }

    fn into_stdout_error(&self, error: io::Error) -> Result<(), UiError> {
        self.write_stderr(
            &[b"abort: ", error.to_string().as_bytes(), b"\n"].concat(),
        )?;
        Err(UiError::StdoutError(error))
    }

    /// Write bytes to stderr
    pub fn write_stderr(&self, bytes: &[u8]) -> Result<(), UiError> {
        let mut stderr = io::stderr();

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

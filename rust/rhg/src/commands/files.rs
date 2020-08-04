use crate::commands::Command;
use crate::error::{CommandError, CommandErrorKind};
use crate::ui::Ui;
use hg::operations::{ListTrackedFiles, ListTrackedFilesErrorKind};
use hg::utils::files::{get_bytes_from_path, relativize_path};
use hg::utils::hg_path::HgPathBuf;

pub const HELP_TEXT: &str = "
List tracked files.

Returns 0 on success.
";

pub struct FilesCommand {}

impl FilesCommand {
    pub fn new() -> Self {
        FilesCommand {}
    }
}

impl Command for FilesCommand {
    fn run(&self, ui: &Ui) -> Result<(), CommandError> {
        let operation_builder = ListTrackedFiles::new()?;
        let operation = operation_builder.load().map_err(|err| {
            CommandErrorKind::Abort(Some(
                [b"abort: ", err.to_string().as_bytes(), b"\n"]
                    .concat()
                    .to_vec(),
            ))
        })?;
        let files = operation.run().map_err(|err| match err.kind {
            ListTrackedFilesErrorKind::ParseError(_) => {
                CommandErrorKind::Abort(Some(
                    // TODO find a better error message
                    b"abort: parse error\n".to_vec(),
                ))
            }
        })?;

        let cwd = std::env::current_dir()
            .or_else(|e| Err(CommandErrorKind::CurrentDirNotFound(e)))?;
        let rooted_cwd = cwd
            .strip_prefix(operation_builder.get_root())
            .expect("cwd was already checked within the repository");
        let rooted_cwd = HgPathBuf::from(get_bytes_from_path(rooted_cwd));

        let mut stdout = ui.stdout_buffer();

        for file in files {
            stdout.write_all(relativize_path(file, &rooted_cwd).as_ref())?;
            stdout.write_all(b"\n")?;
        }
        stdout.flush()?;

        Ok(())
    }
}

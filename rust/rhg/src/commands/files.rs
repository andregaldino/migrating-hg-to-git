use crate::commands::Command;
use crate::error::{CommandError, CommandErrorKind};
use crate::ui::utf8_to_local;
use crate::ui::Ui;
use hg::operations::FindRoot;
use hg::operations::{
    ListDirstateTrackedFiles, ListDirstateTrackedFilesError,
    ListDirstateTrackedFilesErrorKind,
};
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
        let root = FindRoot::new().run()?;
        let mut operation = ListDirstateTrackedFiles::new(&root)
            .map_err(map_dirstate_error)?;
        let files = operation.run().map_err(map_dirstate_error)?;

        let cwd = std::env::current_dir()
            .or_else(|e| Err(CommandErrorKind::CurrentDirNotFound(e)))?;
        let rooted_cwd = cwd
            .strip_prefix(&root)
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

/// Convert operation errors to command errors
fn map_dirstate_error(err: ListDirstateTrackedFilesError) -> CommandError {
    CommandError {
        kind: match err.kind {
            ListDirstateTrackedFilesErrorKind::IoError(err) => {
                CommandErrorKind::Abort(Some(
                    utf8_to_local(&format!("abort: {}\n", err)).into(),
                ))
            }
            ListDirstateTrackedFilesErrorKind::ParseError(_) => {
                CommandErrorKind::Abort(Some(
                    // TODO find a better error message
                    b"abort: parse error\n".to_vec(),
                ))
            }
        },
    }
}

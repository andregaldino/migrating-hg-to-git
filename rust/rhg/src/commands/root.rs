use crate::commands::Command;
use crate::error::{CommandError, CommandErrorKind};
use crate::ui::Ui;
use hg::operations::{FindRoot, FindRootError, FindRootErrorKind, Operation};
use hg::utils::files::get_bytes_from_path;
use std::path::PathBuf;

pub const HELP_TEXT: &str = "
Print the root directory of the current repository.

Returns 0 on success.
";

pub struct RootCommand {
    ui: Ui,
}

impl RootCommand {
    pub fn new() -> Self {
        RootCommand { ui: Ui::new() }
    }

    fn display_found_path(
        &self,
        path_buf: PathBuf,
    ) -> Result<(), CommandError> {
        let bytes = get_bytes_from_path(path_buf);

        // TODO use formating macro
        self.ui.write_stdout(&[bytes.as_slice(), b"\n"].concat())?;

        Err(CommandErrorKind::Ok.into())
    }

    fn display_error(&self, error: FindRootError) -> Result<(), CommandError> {
        match error.kind {
            FindRootErrorKind::RootNotFound(path) => {
                let bytes = get_bytes_from_path(path);

                // TODO use formating macro
                self.ui.write_stderr(
                    &[
                        b"abort: no repository found in '",
                        bytes.as_slice(),
                        b"' (.hg not found)!\n",
                    ]
                    .concat(),
                )?;

                Err(CommandErrorKind::RootNotFound.into())
            }
            FindRootErrorKind::GetCurrentDirError(e) => {
                // TODO use formating macro
                self.ui.write_stderr(
                    &[
                        b"abort: error getting current working directory: ",
                        e.to_string().as_bytes(),
                        b"\n",
                    ]
                    .concat(),
                )?;

                Err(CommandErrorKind::CurrentDirNotFound.into())
            }
        }
    }
}

impl Command for RootCommand {
    fn run(&self) -> Result<(), CommandError> {
        match FindRoot::new().run() {
            Ok(path_buf) => self.display_found_path(path_buf),
            Err(e) => self.display_error(e),
        }
    }
}

use crate::commands::Command;
use crate::error::CommandError;
use crate::ui::Ui;
use hg::operations::FindRoot;
use hg::utils::files::get_bytes_from_path;

pub const HELP_TEXT: &str = "
Print the root directory of the current repository.

Returns 0 on success.
";

pub struct RootCommand {}

impl RootCommand {
    pub fn new() -> Self {
        RootCommand {}
    }
}

impl Command for RootCommand {
    fn run(&self, ui: &Ui) -> Result<(), CommandError> {
        let path_buf = FindRoot::new().run()?;

        let bytes = get_bytes_from_path(path_buf);

        // TODO use formating macro
        ui.write_stdout(&[bytes.as_slice(), b"\n"].concat())?;

        Ok(())
    }
}

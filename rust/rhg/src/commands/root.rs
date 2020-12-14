use crate::commands::Command;
use crate::error::CommandError;
use crate::ui::Ui;
use format_bytes::format_bytes;
use hg::operations::find_root;
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
        let path_buf = find_root()?;

        let bytes = get_bytes_from_path(path_buf);

        ui.write_stdout(&format_bytes!(b"{}\n", bytes.as_slice()))?;

        Ok(())
    }
}

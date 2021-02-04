use crate::commands::Command;
use crate::error::CommandError;
use crate::ui::Ui;
use format_bytes::format_bytes;
use hg::config::Config;
use hg::repo::Repo;
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
    fn run(&self, ui: &Ui, config: &Config) -> Result<(), CommandError> {
        let repo = Repo::find(config)?;
        let bytes = get_bytes_from_path(repo.working_directory_path());
        ui.write_stdout(&format_bytes!(b"{}\n", bytes.as_slice()))?;
        Ok(())
    }
}

use crate::commands::Command;
use crate::error::CommandError;
use crate::ui::Ui;
use hg::repo::Repo;
use hg::requirements;

pub const HELP_TEXT: &str = "
Print the current repo requirements.
";

pub struct DebugRequirementsCommand {}

impl DebugRequirementsCommand {
    pub fn new() -> Self {
        DebugRequirementsCommand {}
    }
}

impl Command for DebugRequirementsCommand {
    fn run(&self, ui: &Ui) -> Result<(), CommandError> {
        let repo = Repo::find()?;
        let mut output = String::new();
        for req in requirements::load(&repo)? {
            output.push_str(&req);
            output.push('\n');
        }
        ui.write_stdout(output.as_bytes())?;
        Ok(())
    }
}

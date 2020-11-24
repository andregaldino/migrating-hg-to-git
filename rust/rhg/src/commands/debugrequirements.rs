use crate::commands::Command;
use crate::error::{CommandError, CommandErrorKind};
use crate::ui::Ui;
use hg::operations::FindRoot;

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
        let root = FindRoot::new().run()?;
        let requires = root.join(".hg").join("requires");
        let requirements = match std::fs::read(requires) {
            Ok(bytes) => bytes,

            // Treat a missing file the same as an empty file.
            // From `mercurial/localrepo.py`:
            // > requires file contains a newline-delimited list of
            // > features/capabilities the opener (us) must have in order to use
            // > the repository. This file was introduced in Mercurial 0.9.2,
            // > which means very old repositories may not have one. We assume
            // > a missing file translates to no requirements.
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Vec::new(),

            Err(error) => Err(CommandErrorKind::FileError(error))?,
        };

        ui.write_stdout(&requirements)?;
        Ok(())
    }
}

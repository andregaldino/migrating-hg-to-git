use crate::commands::Command;
use crate::error::CommandError;
use crate::ui::Ui;
use hg::operations::{debug_data, DebugDataKind};
use hg::repo::Repo;
use micro_timer::timed;

pub const HELP_TEXT: &str = "
Dump the contents of a data file revision
";

pub struct DebugDataCommand<'a> {
    rev: &'a str,
    kind: DebugDataKind,
}

impl<'a> DebugDataCommand<'a> {
    pub fn new(rev: &'a str, kind: DebugDataKind) -> Self {
        DebugDataCommand { rev, kind }
    }
}

impl<'a> Command for DebugDataCommand<'a> {
    #[timed]
    fn run(&self, ui: &Ui) -> Result<(), CommandError> {
        let repo = Repo::find()?;
        let data = debug_data(&repo, self.rev, self.kind)
            .map_err(|e| (e, self.rev))?;

        let mut stdout = ui.stdout_buffer();
        stdout.write_all(&data)?;
        stdout.flush()?;

        Ok(())
    }
}

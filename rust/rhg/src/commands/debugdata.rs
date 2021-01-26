use crate::commands::Command;
use crate::error::CommandError;
use crate::ui::utf8_to_local;
use crate::ui::Ui;
use hg::operations::{debug_data, DebugDataError, DebugDataKind};
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
            .map_err(|e| to_command_error(self.rev, e))?;

        let mut stdout = ui.stdout_buffer();
        stdout.write_all(&data)?;
        stdout.flush()?;

        Ok(())
    }
}

/// Convert operation errors to command errors
fn to_command_error(rev: &str, err: DebugDataError) -> CommandError {
    match err {
        DebugDataError::IoError(err) => CommandError::Abort(Some(
            utf8_to_local(&format!("abort: {}\n", err)).into(),
        )),
        DebugDataError::InvalidRevision => CommandError::Abort(Some(
            utf8_to_local(&format!(
                "abort: invalid revision identifier{}\n",
                rev
            ))
            .into(),
        )),
        DebugDataError::AmbiguousPrefix => CommandError::Abort(Some(
            utf8_to_local(&format!(
                "abort: ambiguous revision identifier{}\n",
                rev
            ))
            .into(),
        )),
        DebugDataError::UnsuportedRevlogVersion(version) => {
            CommandError::Abort(Some(
                utf8_to_local(&format!(
                    "abort: unsupported revlog version {}\n",
                    version
                ))
                .into(),
            ))
        }
        DebugDataError::CorruptedRevlog => {
            CommandError::Abort(Some("abort: corrupted revlog\n".into()))
        }
        DebugDataError::UnknowRevlogDataFormat(format) => {
            CommandError::Abort(Some(
                utf8_to_local(&format!(
                    "abort: unknow revlog dataformat {:?}\n",
                    format
                ))
                .into(),
            ))
        }
    }
}

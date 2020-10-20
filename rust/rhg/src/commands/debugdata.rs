use crate::commands::Command;
use crate::error::{CommandError, CommandErrorKind};
use crate::ui::utf8_to_local;
use crate::ui::Ui;
use hg::operations::{
    DebugData, DebugDataError, DebugDataErrorKind, DebugDataKind,
};
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
        let mut operation = DebugData::new(self.rev, self.kind);
        let data =
            operation.run().map_err(|e| to_command_error(self.rev, e))?;

        let mut stdout = ui.stdout_buffer();
        stdout.write_all(&data)?;
        stdout.flush()?;

        Ok(())
    }
}

/// Convert operation errors to command errors
fn to_command_error(rev: &str, err: DebugDataError) -> CommandError {
    match err.kind {
        DebugDataErrorKind::FindRootError(err) => CommandError::from(err),
        DebugDataErrorKind::IoError(err) => CommandError {
            kind: CommandErrorKind::Abort(Some(
                utf8_to_local(&format!("abort: {}\n", err)).into(),
            )),
        },
        DebugDataErrorKind::InvalidRevision => CommandError {
            kind: CommandErrorKind::Abort(Some(
                utf8_to_local(&format!(
                    "abort: invalid revision identifier{}\n",
                    rev
                ))
                .into(),
            )),
        },
        DebugDataErrorKind::UnsuportedRevlogVersion(version) => CommandError {
            kind: CommandErrorKind::Abort(Some(
                utf8_to_local(&format!(
                    "abort: unsupported revlog version {}\n",
                    version
                ))
                .into(),
            )),
        },
        DebugDataErrorKind::CorruptedRevlog => CommandError {
            kind: CommandErrorKind::Abort(Some(
                "abort: corrupted revlog\n".into(),
            )),
        },
        DebugDataErrorKind::UnknowRevlogDataFormat(format) => CommandError {
            kind: CommandErrorKind::Abort(Some(
                utf8_to_local(&format!(
                    "abort: unknow revlog dataformat {:?}\n",
                    format
                ))
                .into(),
            )),
        },
    }
}

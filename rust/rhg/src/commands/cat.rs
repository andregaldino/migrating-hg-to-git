use crate::commands::Command;
use crate::error::{CommandError, CommandErrorKind};
use crate::ui::utf8_to_local;
use crate::ui::Ui;
use hg::operations::FindRoot;
use hg::operations::{CatRev, CatRevError, CatRevErrorKind};
use hg::requirements;
use hg::utils::hg_path::HgPathBuf;
use micro_timer::timed;
use std::convert::TryFrom;

pub const HELP_TEXT: &str = "
Output the current or given revision of files
";

pub struct CatCommand<'a> {
    rev: Option<&'a str>,
    files: Vec<&'a str>,
}

impl<'a> CatCommand<'a> {
    pub fn new(rev: Option<&'a str>, files: Vec<&'a str>) -> Self {
        Self { rev, files }
    }

    fn display(&self, ui: &Ui, data: &[u8]) -> Result<(), CommandError> {
        ui.write_stdout(data)?;
        Ok(())
    }
}

impl<'a> Command for CatCommand<'a> {
    #[timed]
    fn run(&self, ui: &Ui) -> Result<(), CommandError> {
        let root = FindRoot::new().run()?;
        requirements::check(&root)?;
        let cwd = std::env::current_dir()
            .or_else(|e| Err(CommandErrorKind::CurrentDirNotFound(e)))?;

        let mut files = vec![];
        for file in self.files.iter() {
            let normalized = cwd.join(&file);
            let stripped = normalized
                .strip_prefix(&root)
                .or(Err(CommandErrorKind::Abort(None)))?;
            let hg_file = HgPathBuf::try_from(stripped.to_path_buf())
                .or(Err(CommandErrorKind::Abort(None)))?;
            files.push(hg_file);
        }

        match self.rev {
            Some(rev) => {
                let mut operation = CatRev::new(&root, rev, &files)
                    .map_err(|e| map_rev_error(rev, e))?;
                let data =
                    operation.run().map_err(|e| map_rev_error(rev, e))?;
                self.display(ui, &data)
            }
            None => Err(CommandErrorKind::Unimplemented.into()),
        }
    }
}

/// Convert `CatRevErrorKind` to `CommandError`
fn map_rev_error(rev: &str, err: CatRevError) -> CommandError {
    CommandError {
        kind: match err.kind {
            CatRevErrorKind::IoError(err) => CommandErrorKind::Abort(Some(
                utf8_to_local(&format!("abort: {}\n", err)).into(),
            )),
            CatRevErrorKind::InvalidRevision => CommandErrorKind::Abort(Some(
                utf8_to_local(&format!(
                    "abort: invalid revision identifier{}\n",
                    rev
                ))
                .into(),
            )),
            CatRevErrorKind::UnsuportedRevlogVersion(version) => {
                CommandErrorKind::Abort(Some(
                    utf8_to_local(&format!(
                        "abort: unsupported revlog version {}\n",
                        version
                    ))
                    .into(),
                ))
            }
            CatRevErrorKind::CorruptedRevlog => CommandErrorKind::Abort(Some(
                "abort: corrupted revlog\n".into(),
            )),
            CatRevErrorKind::UnknowRevlogDataFormat(format) => {
                CommandErrorKind::Abort(Some(
                    utf8_to_local(&format!(
                        "abort: unknow revlog dataformat {:?}\n",
                        format
                    ))
                    .into(),
                ))
            }
        },
    }
}

use crate::commands::Command;
use crate::error::CommandError;
use crate::ui::utf8_to_local;
use crate::ui::Ui;
use hg::operations::{cat, CatRevError};
use hg::repo::Repo;
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
        let repo = Repo::find()?;
        repo.check_requirements()?;
        let cwd = std::env::current_dir()
            .or_else(|e| Err(CommandError::CurrentDirNotFound(e)))?;

        let mut files = vec![];
        for file in self.files.iter() {
            let normalized = cwd.join(&file);
            let stripped = normalized
                .strip_prefix(&repo.working_directory_path())
                .or(Err(CommandError::Abort(None)))?;
            let hg_file = HgPathBuf::try_from(stripped.to_path_buf())
                .or(Err(CommandError::Abort(None)))?;
            files.push(hg_file);
        }

        match self.rev {
            Some(rev) => {
                let data = cat(&repo, rev, &files)
                    .map_err(|e| map_rev_error(rev, e))?;
                self.display(ui, &data)
            }
            None => Err(CommandError::Unimplemented.into()),
        }
    }
}

/// Convert `CatRevError` to `CommandError`
fn map_rev_error(rev: &str, err: CatRevError) -> CommandError {
    match err {
        CatRevError::IoError(err) => CommandError::Abort(Some(
            utf8_to_local(&format!("abort: {}\n", err)).into(),
        )),
        CatRevError::InvalidRevision => CommandError::Abort(Some(
            utf8_to_local(&format!(
                "abort: invalid revision identifier {}\n",
                rev
            ))
            .into(),
        )),
        CatRevError::AmbiguousPrefix => CommandError::Abort(Some(
            utf8_to_local(&format!(
                "abort: ambiguous revision identifier {}\n",
                rev
            ))
            .into(),
        )),
        CatRevError::UnsuportedRevlogVersion(version) => {
            CommandError::Abort(Some(
                utf8_to_local(&format!(
                    "abort: unsupported revlog version {}\n",
                    version
                ))
                .into(),
            ))
        }
        CatRevError::CorruptedRevlog => {
            CommandError::Abort(Some("abort: corrupted revlog\n".into()))
        }
        CatRevError::UnknowRevlogDataFormat(format) => {
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

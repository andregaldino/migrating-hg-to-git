use crate::commands::Command;
use crate::error::CommandError;
use crate::ui::Ui;
use hg::config::Config;
use hg::operations::cat;
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
    fn run(&self, ui: &Ui, config: &Config) -> Result<(), CommandError> {
        let repo = Repo::find(config)?;
        let cwd = hg::utils::current_dir()?;

        let mut files = vec![];
        for file in self.files.iter() {
            // TODO: actually normalize `..` path segments etc?
            let normalized = cwd.join(&file);
            let stripped = normalized
                .strip_prefix(&repo.working_directory_path())
                // TODO: error message for path arguments outside of the repo
                .map_err(|_| CommandError::abort(""))?;
            let hg_file = HgPathBuf::try_from(stripped.to_path_buf())
                .map_err(|e| CommandError::abort(e.to_string()))?;
            files.push(hg_file);
        }

        match self.rev {
            Some(rev) => {
                let data = cat(&repo, rev, &files).map_err(|e| (e, rev))?;
                self.display(ui, &data)
            }
            None => Err(CommandError::Unimplemented.into()),
        }
    }
}

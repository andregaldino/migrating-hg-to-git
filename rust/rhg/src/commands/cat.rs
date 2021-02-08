use crate::error::CommandError;
use crate::ui::Ui;
use clap::ArgMatches;
use hg::config::Config;
use hg::operations::cat;
use hg::repo::Repo;
use hg::utils::hg_path::HgPathBuf;
use micro_timer::timed;
use std::convert::TryFrom;

pub const HELP_TEXT: &str = "
Output the current or given revision of files
";

#[timed]
pub fn run(
    ui: &Ui,
    config: &Config,
    args: &ArgMatches,
) -> Result<(), CommandError> {
    let rev = args.value_of("rev");
    let file_args = match args.values_of("files") {
        Some(files) => files.collect(),
        None => vec![],
    };

    let repo = Repo::find(config)?;
    let cwd = hg::utils::current_dir()?;

    let mut files = vec![];
    for file in file_args.iter() {
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

    match rev {
        Some(rev) => {
            let data = cat(&repo, rev, &files).map_err(|e| (e, rev))?;
            ui.write_stdout(&data)?;
            Ok(())
        }
        None => Err(CommandError::Unimplemented.into()),
    }
}

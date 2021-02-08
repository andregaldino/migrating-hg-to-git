use crate::error::CommandError;
use crate::ui::Ui;
use clap::Arg;
use clap::ArgMatches;
use hg::config::Config;
use hg::operations::list_rev_tracked_files;
use hg::operations::Dirstate;
use hg::repo::Repo;
use hg::utils::files::{get_bytes_from_path, relativize_path};
use hg::utils::hg_path::{HgPath, HgPathBuf};
use std::path::Path;

pub const HELP_TEXT: &str = "
List tracked files.

Returns 0 on success.
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("files")
        .arg(
            Arg::with_name("rev")
                .help("search the repository as it is in REV")
                .short("-r")
                .long("--revision")
                .value_name("REV")
                .takes_value(true),
        )
        .about(HELP_TEXT)
}

pub fn run(
    ui: &Ui,
    config: &Config,
    repo_path: Option<&Path>,
    args: &ArgMatches,
) -> Result<(), CommandError> {
    let rev = args.value_of("rev");

    let repo = Repo::find(config, repo_path)?;
    if let Some(rev) = rev {
        let files =
            list_rev_tracked_files(&repo, rev).map_err(|e| (e, rev))?;
        display_files(ui, &repo, files.iter())
    } else {
        let distate = Dirstate::new(&repo)?;
        let files = distate.tracked_files()?;
        display_files(ui, &repo, files)
    }
}

fn display_files<'a>(
    ui: &Ui,
    repo: &Repo,
    files: impl IntoIterator<Item = &'a HgPath>,
) -> Result<(), CommandError> {
    let cwd = HgPathBuf::from(get_bytes_from_path(hg::utils::current_dir()?));
    let working_directory =
        HgPathBuf::from(get_bytes_from_path(repo.working_directory_path()));

    let mut stdout = ui.stdout_buffer();

    for file in files {
        let file = working_directory.join(file);
        stdout.write_all(relativize_path(&file, &cwd).as_ref())?;
        stdout.write_all(b"\n")?;
    }
    stdout.flush()?;
    Ok(())
}

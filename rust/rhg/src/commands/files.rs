use crate::error::CommandError;
use crate::ui::Ui;
use clap::ArgMatches;
use hg::config::Config;
use hg::operations::list_rev_tracked_files;
use hg::operations::Dirstate;
use hg::repo::Repo;
use hg::utils::files::{get_bytes_from_path, relativize_path};
use hg::utils::hg_path::{HgPath, HgPathBuf};

pub const HELP_TEXT: &str = "
List tracked files.

Returns 0 on success.
";

pub fn run(
    ui: &Ui,
    config: &Config,
    args: &ArgMatches,
) -> Result<(), CommandError> {
    let rev = args.value_of("rev");

    let repo = Repo::find(config)?;
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
    let cwd = hg::utils::current_dir()?;
    let rooted_cwd = cwd
        .strip_prefix(repo.working_directory_path())
        .expect("cwd was already checked within the repository");
    let rooted_cwd = HgPathBuf::from(get_bytes_from_path(rooted_cwd));

    let mut stdout = ui.stdout_buffer();

    for file in files {
        stdout.write_all(relativize_path(file, &rooted_cwd).as_ref())?;
        stdout.write_all(b"\n")?;
    }
    stdout.flush()?;
    Ok(())
}

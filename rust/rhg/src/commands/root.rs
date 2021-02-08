use crate::error::CommandError;
use crate::ui::Ui;
use clap::ArgMatches;
use format_bytes::format_bytes;
use hg::config::Config;
use hg::repo::Repo;
use hg::utils::files::get_bytes_from_path;
use std::path::Path;

pub const HELP_TEXT: &str = "
Print the root directory of the current repository.

Returns 0 on success.
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("root").about(HELP_TEXT)
}

pub fn run(
    ui: &Ui,
    config: &Config,
    repo_path: Option<&Path>,
    _args: &ArgMatches,
) -> Result<(), CommandError> {
    let repo = Repo::find(config, repo_path)?;
    let bytes = get_bytes_from_path(repo.working_directory_path());
    ui.write_stdout(&format_bytes!(b"{}\n", bytes.as_slice()))?;
    Ok(())
}

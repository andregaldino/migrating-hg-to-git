use crate::error::CommandError;
use crate::ui::Ui;
use clap::ArgMatches;
use hg::config::Config;
use hg::repo::Repo;
use std::path::Path;

pub const HELP_TEXT: &str = "
Print the current repo requirements.
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("debugrequirements").about(HELP_TEXT)
}

pub fn run(
    ui: &Ui,
    config: &Config,
    repo_path: Option<&Path>,
    _args: &ArgMatches,
) -> Result<(), CommandError> {
    let repo = Repo::find(config, repo_path)?;
    let mut output = String::new();
    let mut requirements: Vec<_> = repo.requirements().iter().collect();
    requirements.sort();
    for req in requirements {
        output.push_str(req);
        output.push('\n');
    }
    ui.write_stdout(output.as_bytes())?;
    Ok(())
}

use crate::error::CommandError;
use crate::ui::Ui;
use clap::ArgMatches;
use hg::config::Config;
use hg::repo::Repo;

pub const HELP_TEXT: &str = "
Print the current repo requirements.
";

pub fn run(
    ui: &Ui,
    config: &Config,
    _args: &ArgMatches,
) -> Result<(), CommandError> {
    let repo = Repo::find(config)?;
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

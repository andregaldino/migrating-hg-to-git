use crate::error::CommandError;
use clap::Arg;
use format_bytes::format_bytes;
use hg::errors::HgError;
use hg::repo::Repo;
use hg::utils::SliceExt;

pub const HELP_TEXT: &str = "
With one argument of the form section.name, print just the value of that config item.
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("config")
        .arg(
            Arg::with_name("name")
                .help("the section.name to print")
                .value_name("NAME")
                .required(true)
                .takes_value(true),
        )
        .about(HELP_TEXT)
}

pub fn run(invocation: &crate::CliInvocation) -> Result<(), CommandError> {
    let opt_repo =
        Repo::find_optional(invocation.non_repo_config, invocation.repo_path)?;
    let config = if let Some(repo) = &opt_repo {
        repo.config()
    } else {
        invocation.non_repo_config
    };
    let (section, name) = invocation
        .subcommand_args
        .value_of("name")
        .expect("missing required CLI argument")
        .as_bytes()
        .split_2(b'.')
        .ok_or_else(|| HgError::abort(""))?;

    let value = config.get(section, name).unwrap_or(b"");

    invocation.ui.write_stdout(&format_bytes!(b"{}\n", value))?;
    Ok(())
}

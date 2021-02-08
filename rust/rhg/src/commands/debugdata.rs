use crate::error::CommandError;
use crate::ui::Ui;
use clap::Arg;
use clap::ArgGroup;
use clap::ArgMatches;
use hg::config::Config;
use hg::operations::{debug_data, DebugDataKind};
use hg::repo::Repo;
use micro_timer::timed;
use std::path::Path;

pub const HELP_TEXT: &str = "
Dump the contents of a data file revision
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("debugdata")
        .arg(
            Arg::with_name("changelog")
                .help("open changelog")
                .short("-c")
                .long("--changelog"),
        )
        .arg(
            Arg::with_name("manifest")
                .help("open manifest")
                .short("-m")
                .long("--manifest"),
        )
        .group(
            ArgGroup::with_name("")
                .args(&["changelog", "manifest"])
                .required(true),
        )
        .arg(
            Arg::with_name("rev")
                .help("revision")
                .required(true)
                .value_name("REV"),
        )
        .about(HELP_TEXT)
}

#[timed]
pub fn run(
    ui: &Ui,
    config: &Config,
    repo_path: Option<&Path>,
    args: &ArgMatches,
) -> Result<(), CommandError> {
    let rev = args
        .value_of("rev")
        .expect("rev should be a required argument");
    let kind =
        match (args.is_present("changelog"), args.is_present("manifest")) {
            (true, false) => DebugDataKind::Changelog,
            (false, true) => DebugDataKind::Manifest,
            (true, true) => {
                unreachable!("Should not happen since options are exclusive")
            }
            (false, false) => {
                unreachable!("Should not happen since options are required")
            }
        };

    let repo = Repo::find(config, repo_path)?;
    let data = debug_data(&repo, rev, kind).map_err(|e| (e, rev))?;

    let mut stdout = ui.stdout_buffer();
    stdout.write_all(&data)?;
    stdout.flush()?;

    Ok(())
}

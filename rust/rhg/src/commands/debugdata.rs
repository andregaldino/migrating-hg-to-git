use crate::error::CommandError;
use crate::ui::Ui;
use clap::ArgMatches;
use hg::config::Config;
use hg::operations::{debug_data, DebugDataKind};
use hg::repo::Repo;
use micro_timer::timed;

pub const HELP_TEXT: &str = "
Dump the contents of a data file revision
";

#[timed]
pub fn run(
    ui: &Ui,
    config: &Config,
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

    let repo = Repo::find(config)?;
    let data = debug_data(&repo, rev, kind).map_err(|e| (e, rev))?;

    let mut stdout = ui.stdout_buffer();
    stdout.write_all(&data)?;
    stdout.flush()?;

    Ok(())
}

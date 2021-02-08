extern crate log;
use clap::App;
use clap::AppSettings;
use clap::ArgMatches;
use format_bytes::format_bytes;

mod commands;
mod error;
mod exitcode;
mod ui;
use error::CommandError;

fn main() {
    env_logger::init();
    let app = App::new("rhg")
        .setting(AppSettings::AllowInvalidUtf8)
        .setting(AppSettings::SubcommandRequired)
        .setting(AppSettings::VersionlessSubcommands)
        .version("0.0.1")
        .subcommand(commands::root::args())
        .subcommand(commands::files::args())
        .subcommand(commands::cat::args())
        .subcommand(commands::debugdata::args())
        .subcommand(commands::debugrequirements::args());

    let matches = app.clone().get_matches_safe().unwrap_or_else(|err| {
        let _ = ui::Ui::new().writeln_stderr_str(&err.message);
        std::process::exit(exitcode::UNIMPLEMENTED)
    });

    let ui = ui::Ui::new();

    let command_result = match_subcommand(matches, &ui);

    let exit_code = match command_result {
        Ok(_) => exitcode::OK,

        // Exit with a specific code and no error message to let a potential
        // wrapper script fallback to Python-based Mercurial.
        Err(CommandError::Unimplemented) => exitcode::UNIMPLEMENTED,

        Err(CommandError::Abort { message }) => {
            if !message.is_empty() {
                // Ignore errors when writing to stderr, we’re already exiting
                // with failure code so there’s not much more we can do.
                let _ =
                    ui.write_stderr(&format_bytes!(b"abort: {}\n", message));
            }
            exitcode::ABORT
        }
    };
    std::process::exit(exit_code)
}

fn match_subcommand(
    matches: ArgMatches,
    ui: &ui::Ui,
) -> Result<(), CommandError> {
    let config = hg::config::Config::load()?;

    match matches.subcommand() {
        ("root", Some(matches)) => commands::root::run(ui, &config, matches),
        ("files", Some(matches)) => commands::files::run(ui, &config, matches),
        ("cat", Some(matches)) => commands::cat::run(ui, &config, matches),
        ("debugdata", Some(matches)) => {
            commands::debugdata::run(ui, &config, matches)
        }
        ("debugrequirements", Some(matches)) => {
            commands::debugrequirements::run(ui, &config, matches)
        }
        _ => unreachable!(), // Because of AppSettings::SubcommandRequired,
    }
}

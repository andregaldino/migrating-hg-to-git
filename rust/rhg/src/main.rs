extern crate log;
use clap::App;
use clap::AppSettings;
use clap::Arg;
use clap::ArgGroup;
use clap::ArgMatches;
use clap::SubCommand;
use format_bytes::format_bytes;
use hg::operations::DebugDataKind;
use std::convert::TryFrom;

mod commands;
mod error;
mod exitcode;
mod ui;
use commands::Command;
use error::CommandError;

fn main() {
    env_logger::init();
    let app = App::new("rhg")
        .setting(AppSettings::AllowInvalidUtf8)
        .setting(AppSettings::SubcommandRequired)
        .setting(AppSettings::VersionlessSubcommands)
        .version("0.0.1")
        .subcommand(
            SubCommand::with_name("root").about(commands::root::HELP_TEXT),
        )
        .subcommand(
            SubCommand::with_name("files")
                .arg(
                    Arg::with_name("rev")
                        .help("search the repository as it is in REV")
                        .short("-r")
                        .long("--revision")
                        .value_name("REV")
                        .takes_value(true),
                )
                .about(commands::files::HELP_TEXT),
        )
        .subcommand(
            SubCommand::with_name("cat")
                .arg(
                    Arg::with_name("rev")
                        .help("search the repository as it is in REV")
                        .short("-r")
                        .long("--revision")
                        .value_name("REV")
                        .takes_value(true),
                )
                .arg(
                    clap::Arg::with_name("files")
                        .required(true)
                        .multiple(true)
                        .empty_values(false)
                        .value_name("FILE")
                        .help("Activity to start: activity@category"),
                )
                .about(commands::cat::HELP_TEXT),
        )
        .subcommand(
            SubCommand::with_name("debugdata")
                .about(commands::debugdata::HELP_TEXT)
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
                ),
        )
        .subcommand(
            SubCommand::with_name("debugrequirements")
                .about(commands::debugrequirements::HELP_TEXT),
        );

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
    match matches.subcommand() {
        ("root", _) => commands::root::RootCommand::new().run(&ui),
        ("files", Some(matches)) => {
            commands::files::FilesCommand::try_from(matches)?.run(&ui)
        }
        ("cat", Some(matches)) => {
            commands::cat::CatCommand::try_from(matches)?.run(&ui)
        }
        ("debugdata", Some(matches)) => {
            commands::debugdata::DebugDataCommand::try_from(matches)?.run(&ui)
        }
        ("debugrequirements", _) => {
            commands::debugrequirements::DebugRequirementsCommand::new()
                .run(&ui)
        }
        _ => unreachable!(), // Because of AppSettings::SubcommandRequired,
    }
}

impl<'a> TryFrom<&'a ArgMatches<'_>> for commands::files::FilesCommand<'a> {
    type Error = CommandError;

    fn try_from(args: &'a ArgMatches) -> Result<Self, Self::Error> {
        let rev = args.value_of("rev");
        Ok(commands::files::FilesCommand::new(rev))
    }
}

impl<'a> TryFrom<&'a ArgMatches<'_>> for commands::cat::CatCommand<'a> {
    type Error = CommandError;

    fn try_from(args: &'a ArgMatches) -> Result<Self, Self::Error> {
        let rev = args.value_of("rev");
        let files = match args.values_of("files") {
            Some(files) => files.collect(),
            None => vec![],
        };
        Ok(commands::cat::CatCommand::new(rev, files))
    }
}

impl<'a> TryFrom<&'a ArgMatches<'_>>
    for commands::debugdata::DebugDataCommand<'a>
{
    type Error = CommandError;

    fn try_from(args: &'a ArgMatches) -> Result<Self, Self::Error> {
        let rev = args
            .value_of("rev")
            .expect("rev should be a required argument");
        let kind = match (
            args.is_present("changelog"),
            args.is_present("manifest"),
        ) {
            (true, false) => DebugDataKind::Changelog,
            (false, true) => DebugDataKind::Manifest,
            (true, true) => {
                unreachable!("Should not happen since options are exclusive")
            }
            (false, false) => {
                unreachable!("Should not happen since options are required")
            }
        };
        Ok(commands::debugdata::DebugDataCommand::new(rev, kind))
    }
}

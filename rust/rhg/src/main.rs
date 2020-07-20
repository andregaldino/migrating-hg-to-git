use clap::App;
use clap::AppSettings;
use clap::SubCommand;

mod commands;
mod error;
mod exitcode;
mod ui;
use commands::Command;

fn main() {
    let mut app = App::new("rhg")
        .setting(AppSettings::AllowInvalidUtf8)
        .setting(AppSettings::SubcommandRequired)
        .setting(AppSettings::VersionlessSubcommands)
        .version("0.0.1")
        .subcommand(
            SubCommand::with_name("root").about(commands::root::HELP_TEXT),
        );

    let matches = app.clone().get_matches_safe().unwrap_or_else(|_| {
        std::process::exit(exitcode::UNIMPLEMENTED_COMMAND)
    });

    let command_result = match matches.subcommand_name() {
        Some(name) => match name {
            "root" => commands::root::RootCommand::new().run(),
            _ => std::process::exit(exitcode::UNIMPLEMENTED_COMMAND),
        },
        _ => {
            match app.print_help() {
                Ok(_) => std::process::exit(exitcode::OK),
                Err(_) => std::process::exit(exitcode::ABORT),
            };
        }
    };

    match command_result {
        Ok(_) => std::process::exit(exitcode::OK),
        Err(e) => e.exit(),
    }
}

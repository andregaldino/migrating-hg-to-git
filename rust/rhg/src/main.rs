extern crate log;
use clap::App;
use clap::AppSettings;
use clap::ArgMatches;
use format_bytes::format_bytes;

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
        .version("0.0.1");
    let app = add_subcommand_args(app);

    let ui = ui::Ui::new();

    let matches = app.clone().get_matches_safe().unwrap_or_else(|err| {
        let _ = ui.writeln_stderr_str(&err.message);
        std::process::exit(exitcode::UNIMPLEMENTED)
    });
    let (subcommand_name, subcommand_matches) = matches.subcommand();
    let run = subcommand_run_fn(subcommand_name)
        .expect("unknown subcommand name from clap despite AppSettings::SubcommandRequired");
    let args = subcommand_matches
        .expect("no subcommand arguments from clap despite AppSettings::SubcommandRequired");

    let result = (|| -> Result<(), CommandError> {
        let config = hg::config::Config::load()?;
        run(&ui, &config, args)
    })();

    let exit_code = match result {
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

macro_rules! subcommands {
    ($( $command: ident )+) => {
        mod commands {
            $(
                pub mod $command;
            )+
        }

        fn add_subcommand_args<'a, 'b>(app: App<'a, 'b>) -> App<'a, 'b> {
            app
            $(
                .subcommand(commands::$command::args())
            )+
        }

        fn subcommand_run_fn(name: &str) -> Option<fn(
            &ui::Ui,
            &hg::config::Config,
            &ArgMatches,
        ) -> Result<(), CommandError>> {
            match name {
                $(
                    stringify!($command) => Some(commands::$command::run),
                )+
                _ => None,
            }
        }
    };
}

subcommands! {
    cat
    debugdata
    debugrequirements
    files
    root
}

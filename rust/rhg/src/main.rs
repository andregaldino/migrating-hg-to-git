extern crate log;
use crate::ui::Ui;
use clap::App;
use clap::AppSettings;
use clap::Arg;
use clap::ArgMatches;
use format_bytes::format_bytes;
use hg::config::Config;
use hg::repo::{Repo, RepoError};
use hg::utils::files::{get_bytes_from_os_str, get_path_from_bytes};
use hg::utils::SliceExt;
use std::ffi::OsString;
use std::path::PathBuf;

mod blackbox;
mod error;
mod exitcode;
mod ui;
use error::CommandError;

fn main_with_result(
    process_start_time: &blackbox::ProcessStartTime,
    ui: &ui::Ui,
    repo: Result<&Repo, &NoRepoInCwdError>,
    config: &Config,
) -> Result<(), CommandError> {
    let app = App::new("rhg")
        .global_setting(AppSettings::AllowInvalidUtf8)
        .setting(AppSettings::SubcommandRequired)
        .setting(AppSettings::VersionlessSubcommands)
        .arg(
            Arg::with_name("repository")
                .help("repository root directory")
                .short("-R")
                .long("--repository")
                .value_name("REPO")
                .takes_value(true)
                // Both ok: `hg -R ./foo log` or `hg log -R ./foo`
                .global(true),
        )
        .arg(
            Arg::with_name("config")
                .help("set/override config option (use 'section.name=value')")
                .long("--config")
                .value_name("CONFIG")
                .takes_value(true)
                .global(true)
                // Ok: `--config section.key1=val --config section.key2=val2`
                .multiple(true)
                // Not ok: `--config section.key1=val section.key2=val2`
                .number_of_values(1),
        )
        .version("0.0.1");
    let app = add_subcommand_args(app);

    let matches = app.clone().get_matches_safe()?;

    let (subcommand_name, subcommand_matches) = matches.subcommand();
    let run = subcommand_run_fn(subcommand_name)
        .expect("unknown subcommand name from clap despite AppSettings::SubcommandRequired");
    let subcommand_args = subcommand_matches
        .expect("no subcommand arguments from clap despite AppSettings::SubcommandRequired");

    let invocation = CliInvocation {
        ui,
        subcommand_args,
        config,
        repo,
    };
    let blackbox = blackbox::Blackbox::new(&invocation, process_start_time)?;
    blackbox.log_command_start();
    let result = run(&invocation);
    blackbox.log_command_end(exit_code(&result));
    result
}

fn main() {
    // Run this first, before we find out if the blackbox extension is even
    // enabled, in order to include everything in-between in the duration
    // measurements. Reading config files can be slow if they’re on NFS.
    let process_start_time = blackbox::ProcessStartTime::now();

    env_logger::init();
    let ui = ui::Ui::new();

    let early_args = EarlyArgs::parse(std::env::args_os());
    let non_repo_config =
        Config::load(early_args.config).unwrap_or_else(|error| {
            // Normally this is decided based on config, but we don’t have that
            // available. As of this writing config loading never returns an
            // "unsupported" error but that is not enforced by the type system.
            let on_unsupported = OnUnsupported::Abort;

            exit(&ui, on_unsupported, Err(error.into()))
        });

    let repo_path = early_args.repo.as_deref().map(get_path_from_bytes);
    let repo_result = match Repo::find(&non_repo_config, repo_path) {
        Ok(repo) => Ok(repo),
        Err(RepoError::NotFound { at }) if repo_path.is_none() => {
            // Not finding a repo is not fatal yet, if `-R` was not given
            Err(NoRepoInCwdError { cwd: at })
        }
        Err(error) => exit(
            &ui,
            OnUnsupported::from_config(&non_repo_config),
            Err(error.into()),
        ),
    };

    let config = if let Ok(repo) = &repo_result {
        repo.config()
    } else {
        &non_repo_config
    };

    let result = main_with_result(
        &process_start_time,
        &ui,
        repo_result.as_ref(),
        config,
    );
    exit(&ui, OnUnsupported::from_config(config), result)
}

fn exit_code(result: &Result<(), CommandError>) -> i32 {
    match result {
        Ok(()) => exitcode::OK,
        Err(CommandError::Abort { .. }) => exitcode::ABORT,

        // Exit with a specific code and no error message to let a potential
        // wrapper script fallback to Python-based Mercurial.
        Err(CommandError::UnsupportedFeature { .. }) => {
            exitcode::UNIMPLEMENTED
        }
    }
}

fn exit(
    ui: &Ui,
    on_unsupported: OnUnsupported,
    result: Result<(), CommandError>,
) -> ! {
    match &result {
        Ok(_) => {}
        Err(CommandError::Abort { message }) => {
            if !message.is_empty() {
                // Ignore errors when writing to stderr, we’re already exiting
                // with failure code so there’s not much more we can do.
                let _ =
                    ui.write_stderr(&format_bytes!(b"abort: {}\n", message));
            }
        }
        Err(CommandError::UnsupportedFeature { message }) => {
            match on_unsupported {
                OnUnsupported::Abort => {
                    let _ = ui.write_stderr(&format_bytes!(
                        b"unsupported feature: {}\n",
                        message
                    ));
                }
                OnUnsupported::AbortSilent => {}
            }
        }
    }
    std::process::exit(exit_code(&result))
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

        pub type RunFn = fn(&CliInvocation) -> Result<(), CommandError>;

        fn subcommand_run_fn(name: &str) -> Option<RunFn> {
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
    config
}
pub struct CliInvocation<'a> {
    ui: &'a Ui,
    subcommand_args: &'a ArgMatches<'a>,
    config: &'a Config,
    /// References inside `Result` is a bit peculiar but allow
    /// `invocation.repo?` to work out with `&CliInvocation` since this
    /// `Result` type is `Copy`.
    repo: Result<&'a Repo, &'a NoRepoInCwdError>,
}

struct NoRepoInCwdError {
    cwd: PathBuf,
}

/// CLI arguments to be parsed "early" in order to be able to read
/// configuration before using Clap. Ideally we would also use Clap for this,
/// see <https://github.com/clap-rs/clap/discussions/2366>.
///
/// These arguments are still declared when we do use Clap later, so that Clap
/// does not return an error for their presence.
struct EarlyArgs {
    /// Values of all `--config` arguments. (Possibly none)
    config: Vec<Vec<u8>>,
    /// Value of the `-R` or `--repository` argument, if any.
    repo: Option<Vec<u8>>,
}

impl EarlyArgs {
    fn parse(args: impl IntoIterator<Item = OsString>) -> Self {
        let mut args = args.into_iter().map(get_bytes_from_os_str);
        let mut config = Vec::new();
        let mut repo = None;
        // Use `while let` instead of `for` so that we can also call
        // `args.next()` inside the loop.
        while let Some(arg) = args.next() {
            if arg == b"--config" {
                if let Some(value) = args.next() {
                    config.push(value)
                }
            } else if let Some(value) = arg.drop_prefix(b"--config=") {
                config.push(value.to_owned())
            }

            if arg == b"--repository" || arg == b"-R" {
                if let Some(value) = args.next() {
                    repo = Some(value)
                }
            } else if let Some(value) = arg.drop_prefix(b"--repository=") {
                repo = Some(value.to_owned())
            } else if let Some(value) = arg.drop_prefix(b"-R") {
                repo = Some(value.to_owned())
            }
        }
        Self { config, repo }
    }
}

/// What to do when encountering some unsupported feature.
///
/// See `HgError::UnsupportedFeature` and `CommandError::UnsupportedFeature`.
enum OnUnsupported {
    /// Print an error message describing what feature is not supported,
    /// and exit with code 252.
    Abort,
    /// Silently exit with code 252.
    AbortSilent,
}

impl OnUnsupported {
    fn from_config(config: &Config) -> Self {
        let default = OnUnsupported::Abort;
        match config.get(b"rhg", b"on-unsupported") {
            Some(b"abort") => OnUnsupported::Abort,
            Some(b"abort-silent") => OnUnsupported::AbortSilent,
            None => default,
            Some(_) => {
                // TODO: warn about unknown config value
                default
            }
        }
    }
}

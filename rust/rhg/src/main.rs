extern crate log;
use crate::ui::Ui;
use clap::App;
use clap::AppSettings;
use clap::Arg;
use clap::ArgMatches;
use format_bytes::{format_bytes, join};
use hg::config::Config;
use hg::repo::{Repo, RepoError};
use hg::utils::files::{get_bytes_from_os_str, get_path_from_bytes};
use hg::utils::SliceExt;
use std::ffi::OsString;
use std::path::PathBuf;
use std::process::Command;

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
    check_extensions(config)?;

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
        .arg(
            Arg::with_name("cwd")
                .help("change working directory")
                .long("--cwd")
                .value_name("DIR")
                .takes_value(true)
                .global(true),
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

    let initial_current_dir = early_args.cwd.map(|cwd| {
        let cwd = get_path_from_bytes(&cwd);
        std::env::current_dir()
            .and_then(|initial| {
                std::env::set_current_dir(cwd)?;
                Ok(initial)
            })
            .unwrap_or_else(|error| {
                exit(
                    &None,
                    &ui,
                    OnUnsupported::Abort,
                    Err(CommandError::abort(format!(
                        "abort: {}: '{}'",
                        error,
                        cwd.display()
                    ))),
                )
            })
    });

    let non_repo_config =
        Config::load(early_args.config).unwrap_or_else(|error| {
            // Normally this is decided based on config, but we don’t have that
            // available. As of this writing config loading never returns an
            // "unsupported" error but that is not enforced by the type system.
            let on_unsupported = OnUnsupported::Abort;

            exit(&initial_current_dir, &ui, on_unsupported, Err(error.into()))
        });

    if let Some(repo_path_bytes) = &early_args.repo {
        lazy_static::lazy_static! {
            static ref SCHEME_RE: regex::bytes::Regex =
                // Same as `_matchscheme` in `mercurial/util.py`
                regex::bytes::Regex::new("^[a-zA-Z0-9+.\\-]+:").unwrap();
        }
        if SCHEME_RE.is_match(&repo_path_bytes) {
            exit(
                &initial_current_dir,
                &ui,
                OnUnsupported::from_config(&non_repo_config),
                Err(CommandError::UnsupportedFeature {
                    message: format_bytes!(
                        b"URL-like --repository {}",
                        repo_path_bytes
                    ),
                }),
            )
        }
    }
    let repo_path = early_args.repo.as_deref().map(get_path_from_bytes);
    let repo_result = match Repo::find(&non_repo_config, repo_path) {
        Ok(repo) => Ok(repo),
        Err(RepoError::NotFound { at }) if repo_path.is_none() => {
            // Not finding a repo is not fatal yet, if `-R` was not given
            Err(NoRepoInCwdError { cwd: at })
        }
        Err(error) => exit(
            &initial_current_dir,
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
    exit(
        &initial_current_dir,
        &ui,
        OnUnsupported::from_config(config),
        result,
    )
}

fn exit_code(result: &Result<(), CommandError>) -> i32 {
    match result {
        Ok(()) => exitcode::OK,
        Err(CommandError::Abort { .. }) => exitcode::ABORT,
        Err(CommandError::Unsuccessful) => exitcode::UNSUCCESSFUL,

        // Exit with a specific code and no error message to let a potential
        // wrapper script fallback to Python-based Mercurial.
        Err(CommandError::UnsupportedFeature { .. }) => {
            exitcode::UNIMPLEMENTED
        }
    }
}

fn exit(
    initial_current_dir: &Option<PathBuf>,
    ui: &Ui,
    mut on_unsupported: OnUnsupported,
    result: Result<(), CommandError>,
) -> ! {
    if let (
        OnUnsupported::Fallback { executable },
        Err(CommandError::UnsupportedFeature { .. }),
    ) = (&on_unsupported, &result)
    {
        let mut args = std::env::args_os();
        let executable_path = get_path_from_bytes(&executable);
        let this_executable = args.next().expect("exepcted argv[0] to exist");
        if executable_path == &PathBuf::from(this_executable) {
            // Avoid spawning infinitely many processes until resource
            // exhaustion.
            let _ = ui.write_stderr(&format_bytes!(
                b"Blocking recursive fallback. The 'rhg.fallback-executable = {}' config \
                points to `rhg` itself.\n",
                executable
            ));
            on_unsupported = OnUnsupported::Abort
        } else {
            // `args` is now `argv[1..]` since we’ve already consumed `argv[0]`
            let mut command = Command::new(executable_path);
            command.args(args);
            if let Some(initial) = initial_current_dir {
                command.current_dir(initial);
            }
            let result = command.status();
            match result {
                Ok(status) => std::process::exit(
                    status.code().unwrap_or(exitcode::ABORT),
                ),
                Err(error) => {
                    let _ = ui.write_stderr(&format_bytes!(
                        b"tried to fall back to a '{}' sub-process but got error {}\n",
                        executable, format_bytes::Utf8(error)
                    ));
                    on_unsupported = OnUnsupported::Abort
                }
            }
        }
    }
    match &result {
        Ok(_) => {}
        Err(CommandError::Unsuccessful) => {}
        Err(CommandError::Abort { message }) => {
            if !message.is_empty() {
                // Ignore errors when writing to stderr, we’re already exiting
                // with failure code so there’s not much more we can do.
                let _ = ui.write_stderr(&format_bytes!(b"{}\n", message));
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
                OnUnsupported::Fallback { .. } => unreachable!(),
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
    /// Value of the `--cwd` argument, if any.
    cwd: Option<Vec<u8>>,
}

impl EarlyArgs {
    fn parse(args: impl IntoIterator<Item = OsString>) -> Self {
        let mut args = args.into_iter().map(get_bytes_from_os_str);
        let mut config = Vec::new();
        let mut repo = None;
        let mut cwd = None;
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

            if arg == b"--cwd" {
                if let Some(value) = args.next() {
                    cwd = Some(value)
                }
            } else if let Some(value) = arg.drop_prefix(b"--cwd=") {
                cwd = Some(value.to_owned())
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
        Self { config, repo, cwd }
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
    /// Try running a Python implementation
    Fallback { executable: Vec<u8> },
}

impl OnUnsupported {
    const DEFAULT: Self = OnUnsupported::Abort;
    const DEFAULT_FALLBACK_EXECUTABLE: &'static [u8] = b"hg";

    fn from_config(config: &Config) -> Self {
        match config
            .get(b"rhg", b"on-unsupported")
            .map(|value| value.to_ascii_lowercase())
            .as_deref()
        {
            Some(b"abort") => OnUnsupported::Abort,
            Some(b"abort-silent") => OnUnsupported::AbortSilent,
            Some(b"fallback") => OnUnsupported::Fallback {
                executable: config
                    .get(b"rhg", b"fallback-executable")
                    .unwrap_or(Self::DEFAULT_FALLBACK_EXECUTABLE)
                    .to_owned(),
            },
            None => Self::DEFAULT,
            Some(_) => {
                // TODO: warn about unknown config value
                Self::DEFAULT
            }
        }
    }
}

const SUPPORTED_EXTENSIONS: &[&[u8]] = &[b"blackbox", b"share"];

fn check_extensions(config: &Config) -> Result<(), CommandError> {
    let enabled = config.get_section_keys(b"extensions");

    let mut unsupported = enabled;
    for supported in SUPPORTED_EXTENSIONS {
        unsupported.remove(supported);
    }

    if let Some(ignored_list) =
        config.get_simple_list(b"rhg", b"ignored-extensions")
    {
        for ignored in ignored_list {
            unsupported.remove(ignored);
        }
    }

    if unsupported.is_empty() {
        Ok(())
    } else {
        Err(CommandError::UnsupportedFeature {
            message: format_bytes!(
                b"extensions: {} (consider adding them to 'rhg.ignored-extensions' config)",
                join(unsupported, b", ")
            ),
        })
    }
}

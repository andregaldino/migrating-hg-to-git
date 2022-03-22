extern crate log;
use crate::error::CommandError;
use crate::ui::{local_to_utf8, Ui};
use clap::App;
use clap::AppSettings;
use clap::Arg;
use clap::ArgMatches;
use format_bytes::{format_bytes, join};
use hg::config::{Config, ConfigSource};
use hg::repo::{Repo, RepoError};
use hg::utils::files::{get_bytes_from_os_str, get_path_from_bytes};
use hg::utils::SliceExt;
use hg::{exit_codes, requirements};
use std::collections::HashSet;
use std::ffi::OsString;
use std::os::unix::prelude::CommandExt;
use std::path::PathBuf;
use std::process::Command;

mod blackbox;
mod color;
mod error;
mod ui;
pub mod utils {
    pub mod path_utils;
}

fn main_with_result(
    argv: Vec<OsString>,
    process_start_time: &blackbox::ProcessStartTime,
    ui: &ui::Ui,
    repo: Result<&Repo, &NoRepoInCwdError>,
    config: &Config,
) -> Result<(), CommandError> {
    check_unsupported(config, repo)?;

    let app = App::new("rhg")
        .global_setting(AppSettings::AllowInvalidUtf8)
        .global_setting(AppSettings::DisableVersion)
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
        .arg(
            Arg::with_name("color")
                .help("when to colorize (boolean, always, auto, never, or debug)")
                .long("--color")
                .value_name("TYPE")
                .takes_value(true)
                .global(true),
        )
        .version("0.0.1");
    let app = add_subcommand_args(app);

    let matches = app.clone().get_matches_from_safe(argv.iter())?;

    let (subcommand_name, subcommand_matches) = matches.subcommand();

    // Mercurial allows users to define "defaults" for commands, fallback
    // if a default is detected for the current command
    let defaults = config.get_str(b"defaults", subcommand_name.as_bytes());
    if defaults?.is_some() {
        let msg = "`defaults` config set";
        return Err(CommandError::unsupported(msg));
    }

    for prefix in ["pre", "post", "fail"].iter() {
        // Mercurial allows users to define generic hooks for commands,
        // fallback if any are detected
        let item = format!("{}-{}", prefix, subcommand_name);
        let hook_for_command = config.get_str(b"hooks", item.as_bytes())?;
        if hook_for_command.is_some() {
            let msg = format!("{}-{} hook defined", prefix, subcommand_name);
            return Err(CommandError::unsupported(msg));
        }
    }
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

    if let Ok(repo) = repo {
        // We don't support subrepos, fallback if the subrepos file is present
        if repo.working_directory_vfs().join(".hgsub").exists() {
            let msg = "subrepos (.hgsub is present)";
            return Err(CommandError::unsupported(msg));
        }
    }

    if config.is_extension_enabled(b"blackbox") {
        let blackbox =
            blackbox::Blackbox::new(&invocation, process_start_time)?;
        blackbox.log_command_start(argv.iter());
        let result = run(&invocation);
        blackbox.log_command_end(
            argv.iter(),
            exit_code(
                &result,
                // TODO: show a warning or combine with original error if
                // `get_bool` returns an error
                config
                    .get_bool(b"ui", b"detailed-exit-code")
                    .unwrap_or(false),
            ),
        );
        result
    } else {
        run(&invocation)
    }
}

fn rhg_main(argv: Vec<OsString>) -> ! {
    // Run this first, before we find out if the blackbox extension is even
    // enabled, in order to include everything in-between in the duration
    // measurements. Reading config files can be slow if they’re on NFS.
    let process_start_time = blackbox::ProcessStartTime::now();

    env_logger::init();

    let early_args = EarlyArgs::parse(&argv);

    let initial_current_dir = early_args.cwd.map(|cwd| {
        let cwd = get_path_from_bytes(&cwd);
        std::env::current_dir()
            .and_then(|initial| {
                std::env::set_current_dir(cwd)?;
                Ok(initial)
            })
            .unwrap_or_else(|error| {
                exit(
                    &argv,
                    &None,
                    &Ui::new_infallible(&Config::empty()),
                    OnUnsupported::Abort,
                    Err(CommandError::abort(format!(
                        "abort: {}: '{}'",
                        error,
                        cwd.display()
                    ))),
                    false,
                )
            })
    });

    let mut non_repo_config =
        Config::load_non_repo().unwrap_or_else(|error| {
            // Normally this is decided based on config, but we don’t have that
            // available. As of this writing config loading never returns an
            // "unsupported" error but that is not enforced by the type system.
            let on_unsupported = OnUnsupported::Abort;

            exit(
                &argv,
                &initial_current_dir,
                &Ui::new_infallible(&Config::empty()),
                on_unsupported,
                Err(error.into()),
                false,
            )
        });

    non_repo_config
        .load_cli_args(early_args.config, early_args.color)
        .unwrap_or_else(|error| {
            exit(
                &argv,
                &initial_current_dir,
                &Ui::new_infallible(&non_repo_config),
                OnUnsupported::from_config(&non_repo_config),
                Err(error.into()),
                non_repo_config
                    .get_bool(b"ui", b"detailed-exit-code")
                    .unwrap_or(false),
            )
        });

    if let Some(repo_path_bytes) = &early_args.repo {
        lazy_static::lazy_static! {
            static ref SCHEME_RE: regex::bytes::Regex =
                // Same as `_matchscheme` in `mercurial/util.py`
                regex::bytes::Regex::new("^[a-zA-Z0-9+.\\-]+:").unwrap();
        }
        if SCHEME_RE.is_match(&repo_path_bytes) {
            exit(
                &argv,
                &initial_current_dir,
                &Ui::new_infallible(&non_repo_config),
                OnUnsupported::from_config(&non_repo_config),
                Err(CommandError::UnsupportedFeature {
                    message: format_bytes!(
                        b"URL-like --repository {}",
                        repo_path_bytes
                    ),
                }),
                // TODO: show a warning or combine with original error if
                // `get_bool` returns an error
                non_repo_config
                    .get_bool(b"ui", b"detailed-exit-code")
                    .unwrap_or(false),
            )
        }
    }
    let repo_arg = early_args.repo.unwrap_or(Vec::new());
    let repo_path: Option<PathBuf> = {
        if repo_arg.is_empty() {
            None
        } else {
            let local_config = {
                if std::env::var_os("HGRCSKIPREPO").is_none() {
                    // TODO: handle errors from find_repo_root
                    if let Ok(current_dir_path) = Repo::find_repo_root() {
                        let config_files = vec![
                            ConfigSource::AbsPath(
                                current_dir_path.join(".hg/hgrc"),
                            ),
                            ConfigSource::AbsPath(
                                current_dir_path.join(".hg/hgrc-not-shared"),
                            ),
                        ];
                        // TODO: handle errors from
                        // `load_from_explicit_sources`
                        Config::load_from_explicit_sources(config_files).ok()
                    } else {
                        None
                    }
                } else {
                    None
                }
            };

            let non_repo_config_val = {
                let non_repo_val = non_repo_config.get(b"paths", &repo_arg);
                match &non_repo_val {
                    Some(val) if val.len() > 0 => home::home_dir()
                        .unwrap_or_else(|| PathBuf::from("~"))
                        .join(get_path_from_bytes(val))
                        .canonicalize()
                        // TODO: handle error and make it similar to python
                        // implementation maybe?
                        .ok(),
                    _ => None,
                }
            };

            let config_val = match &local_config {
                None => non_repo_config_val,
                Some(val) => {
                    let local_config_val = val.get(b"paths", &repo_arg);
                    match &local_config_val {
                        Some(val) if val.len() > 0 => {
                            // presence of a local_config assures that
                            // current_dir
                            // wont result in an Error
                            let canpath = hg::utils::current_dir()
                                .unwrap()
                                .join(get_path_from_bytes(val))
                                .canonicalize();
                            canpath.ok().or(non_repo_config_val)
                        }
                        _ => non_repo_config_val,
                    }
                }
            };
            config_val.or(Some(get_path_from_bytes(&repo_arg).to_path_buf()))
        }
    };

    let repo_result = match Repo::find(&non_repo_config, repo_path.to_owned())
    {
        Ok(repo) => Ok(repo),
        Err(RepoError::NotFound { at }) if repo_path.is_none() => {
            // Not finding a repo is not fatal yet, if `-R` was not given
            Err(NoRepoInCwdError { cwd: at })
        }
        Err(error) => exit(
            &argv,
            &initial_current_dir,
            &Ui::new_infallible(&non_repo_config),
            OnUnsupported::from_config(&non_repo_config),
            Err(error.into()),
            // TODO: show a warning or combine with original error if
            // `get_bool` returns an error
            non_repo_config
                .get_bool(b"ui", b"detailed-exit-code")
                .unwrap_or(false),
        ),
    };

    let config = if let Ok(repo) = &repo_result {
        repo.config()
    } else {
        &non_repo_config
    };
    let ui = Ui::new(&config).unwrap_or_else(|error| {
        exit(
            &argv,
            &initial_current_dir,
            &Ui::new_infallible(&config),
            OnUnsupported::from_config(&config),
            Err(error.into()),
            config
                .get_bool(b"ui", b"detailed-exit-code")
                .unwrap_or(false),
        )
    });
    let on_unsupported = OnUnsupported::from_config(config);

    let result = main_with_result(
        argv.iter().map(|s| s.to_owned()).collect(),
        &process_start_time,
        &ui,
        repo_result.as_ref(),
        config,
    );
    exit(
        &argv,
        &initial_current_dir,
        &ui,
        on_unsupported,
        result,
        // TODO: show a warning or combine with original error if `get_bool`
        // returns an error
        config
            .get_bool(b"ui", b"detailed-exit-code")
            .unwrap_or(false),
    )
}

fn main() -> ! {
    rhg_main(std::env::args_os().collect())
}

fn exit_code(
    result: &Result<(), CommandError>,
    use_detailed_exit_code: bool,
) -> i32 {
    match result {
        Ok(()) => exit_codes::OK,
        Err(CommandError::Abort {
            message: _,
            detailed_exit_code,
        }) => {
            if use_detailed_exit_code {
                *detailed_exit_code
            } else {
                exit_codes::ABORT
            }
        }
        Err(CommandError::Unsuccessful) => exit_codes::UNSUCCESSFUL,
        // Exit with a specific code and no error message to let a potential
        // wrapper script fallback to Python-based Mercurial.
        Err(CommandError::UnsupportedFeature { .. }) => {
            exit_codes::UNIMPLEMENTED
        }
        Err(CommandError::InvalidFallback { .. }) => {
            exit_codes::INVALID_FALLBACK
        }
    }
}

fn exit<'a>(
    original_args: &'a [OsString],
    initial_current_dir: &Option<PathBuf>,
    ui: &Ui,
    mut on_unsupported: OnUnsupported,
    result: Result<(), CommandError>,
    use_detailed_exit_code: bool,
) -> ! {
    if let (
        OnUnsupported::Fallback { executable },
        Err(CommandError::UnsupportedFeature { message }),
    ) = (&on_unsupported, &result)
    {
        let mut args = original_args.iter();
        let executable = match executable {
            None => {
                exit_no_fallback(
                    ui,
                    OnUnsupported::Abort,
                    Err(CommandError::abort(
                        "abort: 'rhg.on-unsupported=fallback' without \
                                'rhg.fallback-executable' set.",
                    )),
                    false,
                );
            }
            Some(executable) => executable,
        };
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
            log::debug!("falling back (see trace-level log)");
            log::trace!("{}", local_to_utf8(message));
            if let Err(err) = which::which(executable_path) {
                exit_no_fallback(
                    ui,
                    OnUnsupported::Abort,
                    Err(CommandError::InvalidFallback {
                        path: executable.to_owned(),
                        err: err.to_string(),
                    }),
                    use_detailed_exit_code,
                )
            }
            // `args` is now `argv[1..]` since we’ve already consumed
            // `argv[0]`
            let mut command = Command::new(executable_path);
            command.args(args);
            if let Some(initial) = initial_current_dir {
                command.current_dir(initial);
            }
            // We don't use subprocess because proper signal handling is harder
            // and we don't want to keep `rhg` around after a fallback anyway.
            // For example, if `rhg` is run in the background and falls back to
            // `hg` which, in turn, waits for a signal, we'll get stuck if
            // we're doing plain subprocess.
            //
            // If `exec` returns, we can only assume our process is very broken
            // (see its documentation), so only try to forward the error code
            // when exiting.
            let err = command.exec();
            std::process::exit(
                err.raw_os_error().unwrap_or(exit_codes::ABORT),
            );
        }
    }
    exit_no_fallback(ui, on_unsupported, result, use_detailed_exit_code)
}

fn exit_no_fallback(
    ui: &Ui,
    on_unsupported: OnUnsupported,
    result: Result<(), CommandError>,
    use_detailed_exit_code: bool,
) -> ! {
    match &result {
        Ok(_) => {}
        Err(CommandError::Unsuccessful) => {}
        Err(CommandError::Abort {
            message,
            detailed_exit_code: _,
        }) => {
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
        Err(CommandError::InvalidFallback { path, err }) => {
            let _ = ui.write_stderr(&format_bytes!(
                b"abort: invalid fallback '{}': {}\n",
                path,
                err.as_bytes(),
            ));
        }
    }
    std::process::exit(exit_code(&result, use_detailed_exit_code))
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
    debugignorerhg
    files
    root
    config
    status
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
    /// Value of all the `--color` argument, if any.
    color: Option<Vec<u8>>,
    /// Value of the `-R` or `--repository` argument, if any.
    repo: Option<Vec<u8>>,
    /// Value of the `--cwd` argument, if any.
    cwd: Option<Vec<u8>>,
}

impl EarlyArgs {
    fn parse<'a>(args: impl IntoIterator<Item = &'a OsString>) -> Self {
        let mut args = args.into_iter().map(get_bytes_from_os_str);
        let mut config = Vec::new();
        let mut color = None;
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

            if arg == b"--color" {
                if let Some(value) = args.next() {
                    color = Some(value)
                }
            } else if let Some(value) = arg.drop_prefix(b"--color=") {
                color = Some(value.to_owned())
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
        Self {
            config,
            color,
            repo,
            cwd,
        }
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
    Fallback { executable: Option<Vec<u8>> },
}

impl OnUnsupported {
    const DEFAULT: Self = OnUnsupported::Abort;

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
                    .map(|x| x.to_owned()),
            },
            None => Self::DEFAULT,
            Some(_) => {
                // TODO: warn about unknown config value
                Self::DEFAULT
            }
        }
    }
}

/// The `*` extension is an edge-case for config sub-options that apply to all
/// extensions. For now, only `:required` exists, but that may change in the
/// future.
const SUPPORTED_EXTENSIONS: &[&[u8]] =
    &[b"blackbox", b"share", b"sparse", b"narrow", b"*"];

fn check_extensions(config: &Config) -> Result<(), CommandError> {
    if let Some(b"*") = config.get(b"rhg", b"ignored-extensions") {
        // All extensions are to be ignored, nothing to do here
        return Ok(());
    }

    let enabled: HashSet<&[u8]> = config
        .get_section_keys(b"extensions")
        .into_iter()
        .map(|extension| {
            // Ignore extension suboptions. Only `required` exists for now.
            // `rhg` either supports an extension or doesn't, so it doesn't
            // make sense to consider the loading of an extension.
            extension.split_2(b':').unwrap_or((extension, b"")).0
        })
        .collect();

    let mut unsupported = enabled;
    for supported in SUPPORTED_EXTENSIONS {
        unsupported.remove(supported);
    }

    if let Some(ignored_list) = config.get_list(b"rhg", b"ignored-extensions")
    {
        for ignored in ignored_list {
            unsupported.remove(ignored.as_slice());
        }
    }

    if unsupported.is_empty() {
        Ok(())
    } else {
        let mut unsupported: Vec<_> = unsupported.into_iter().collect();
        // Sort the extensions to get a stable output
        unsupported.sort();
        Err(CommandError::UnsupportedFeature {
            message: format_bytes!(
                b"extensions: {} (consider adding them to 'rhg.ignored-extensions' config)",
                join(unsupported, b", ")
            ),
        })
    }
}

/// Array of tuples of (auto upgrade conf, feature conf, local requirement)
const AUTO_UPGRADES: &[((&str, &str), (&str, &str), &str)] = &[
    (
        ("format", "use-share-safe.automatic-upgrade-of-mismatching-repositories"),
        ("format", "use-share-safe"),
        requirements::SHARESAFE_REQUIREMENT,
    ),
    (
        ("format", "use-dirstate-tracked-hint.automatic-upgrade-of-mismatching-repositories"),
        ("format", "use-dirstate-tracked-hint"),
        requirements::DIRSTATE_TRACKED_HINT_V1,
    ),
    (
        ("use-dirstate-v2", "automatic-upgrade-of-mismatching-repositories"),
        ("format", "use-dirstate-v2"),
        requirements::DIRSTATE_V2_REQUIREMENT,
    ),
];

/// Mercurial allows users to automatically upgrade their repository.
/// `rhg` does not have the ability to upgrade yet, so fallback if an upgrade
/// is needed.
fn check_auto_upgrade(
    config: &Config,
    reqs: &HashSet<String>,
) -> Result<(), CommandError> {
    for (upgrade_conf, feature_conf, local_req) in AUTO_UPGRADES.iter() {
        let auto_upgrade = config
            .get_bool(upgrade_conf.0.as_bytes(), upgrade_conf.1.as_bytes())?;

        if auto_upgrade {
            let want_it = config.get_bool(
                feature_conf.0.as_bytes(),
                feature_conf.1.as_bytes(),
            )?;
            let have_it = reqs.contains(*local_req);

            let action = match (want_it, have_it) {
                (true, false) => Some("upgrade"),
                (false, true) => Some("downgrade"),
                _ => None,
            };
            if let Some(action) = action {
                let message = format!(
                    "automatic {} {}.{}",
                    action, upgrade_conf.0, upgrade_conf.1
                );
                return Err(CommandError::unsupported(message));
            }
        }
    }
    Ok(())
}

fn check_unsupported(
    config: &Config,
    repo: Result<&Repo, &NoRepoInCwdError>,
) -> Result<(), CommandError> {
    check_extensions(config)?;

    if std::env::var_os("HG_PENDING").is_some() {
        // TODO: only if the value is `== repo.working_directory`?
        // What about relative v.s. absolute paths?
        Err(CommandError::unsupported("$HG_PENDING"))?
    }

    if let Ok(repo) = repo {
        if repo.has_subrepos()? {
            Err(CommandError::unsupported("sub-repositories"))?
        }
        check_auto_upgrade(config, repo.requirements())?;
    }

    if config.has_non_empty_section(b"encode") {
        Err(CommandError::unsupported("[encode] config"))?
    }

    if config.has_non_empty_section(b"decode") {
        Err(CommandError::unsupported("[decode] config"))?
    }

    Ok(())
}

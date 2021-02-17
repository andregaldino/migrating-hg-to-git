extern crate log;
use crate::ui::Ui;
use clap::App;
use clap::AppSettings;
use clap::Arg;
use clap::ArgMatches;
use format_bytes::format_bytes;
use hg::config::Config;
use hg::repo::{Repo, RepoError};
use std::path::{Path, PathBuf};

mod error;
mod exitcode;
mod ui;
use error::CommandError;

fn add_global_args<'a, 'b>(app: App<'a, 'b>) -> App<'a, 'b> {
    app.arg(
        Arg::with_name("repository")
            .help("repository root directory")
            .short("-R")
            .long("--repository")
            .value_name("REPO")
            .takes_value(true),
    )
    .arg(
        Arg::with_name("config")
            .help("set/override config option (use 'section.name=value')")
            .long("--config")
            .value_name("CONFIG")
            .takes_value(true)
            // Ok: `--config section.key1=val --config section.key2=val2`
            .multiple(true)
            // Not ok: `--config section.key1=val section.key2=val2`
            .number_of_values(1),
    )
}

fn main_with_result(ui: &ui::Ui) -> Result<(), CommandError> {
    env_logger::init();
    let app = App::new("rhg")
        .setting(AppSettings::AllowInvalidUtf8)
        .setting(AppSettings::SubcommandRequired)
        .setting(AppSettings::VersionlessSubcommands)
        .version("0.0.1");
    let app = add_global_args(app);
    let app = add_subcommand_args(app);

    let matches = app.clone().get_matches_safe()?;

    let (subcommand_name, subcommand_matches) = matches.subcommand();
    let run = subcommand_run_fn(subcommand_name)
        .expect("unknown subcommand name from clap despite AppSettings::SubcommandRequired");
    let subcommand_args = subcommand_matches
        .expect("no subcommand arguments from clap despite AppSettings::SubcommandRequired");

    // Global arguments can be in either based on e.g. `hg -R ./foo log` v.s.
    // `hg log -R ./foo`
    let value_of_global_arg = |name| {
        subcommand_args
            .value_of_os(name)
            .or_else(|| matches.value_of_os(name))
    };
    // For arguments where multiple occurences are allowed, return a
    // possibly-iterator of all values.
    let values_of_global_arg = |name: &str| {
        let a = matches.values_of_os(name).into_iter().flatten();
        let b = subcommand_args.values_of_os(name).into_iter().flatten();
        a.chain(b)
    };

    let config_args = values_of_global_arg("config")
        .map(hg::utils::files::get_bytes_from_os_str);
    let non_repo_config = &hg::config::Config::load(config_args)?;

    let repo_path = value_of_global_arg("repository").map(Path::new);
    let repo = match Repo::find(non_repo_config, repo_path) {
        Ok(repo) => Ok(repo),
        Err(RepoError::NotFound { at }) if repo_path.is_none() => {
            // Not finding a repo is not fatal yet, if `-R` was not given
            Err(NoRepoInCwdError { cwd: at })
        }
        Err(error) => return Err(error.into()),
    };

    run(&CliInvocation {
        ui,
        subcommand_args,
        non_repo_config,
        repo: repo.as_ref(),
    })
}

fn main() {
    let ui = ui::Ui::new();

    let exit_code = match main_with_result(&ui) {
        Ok(()) => exitcode::OK,

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
                .subcommand(add_global_args(commands::$command::args()))
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
    non_repo_config: &'a Config,
    /// References inside `Result` is a bit peculiar but allow
    /// `invocation.repo?` to work out with `&CliInvocation` since this
    /// `Result` type is `Copy`.
    repo: Result<&'a Repo, &'a NoRepoInCwdError>,
}

struct NoRepoInCwdError {
    cwd: PathBuf,
}

impl CliInvocation<'_> {
    fn config(&self) -> &Config {
        if let Ok(repo) = self.repo {
            repo.config()
        } else {
            self.non_repo_config
        }
    }
}

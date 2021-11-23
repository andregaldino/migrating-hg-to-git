use crate::error::CommandError;
use crate::ui::Ui;
use crate::ui::UiError;
use crate::utils::path_utils::relativize_paths;
use clap::Arg;
use hg::errors::HgError;
use hg::operations::list_rev_tracked_files;
use hg::operations::Dirstate;
use hg::repo::Repo;
use hg::utils::hg_path::HgPath;
use std::borrow::Cow;

pub const HELP_TEXT: &str = "
List tracked files.

Returns 0 on success.
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("files")
        .arg(
            Arg::with_name("rev")
                .help("search the repository as it is in REV")
                .short("-r")
                .long("--revision")
                .value_name("REV")
                .takes_value(true),
        )
        .about(HELP_TEXT)
}

pub fn run(invocation: &crate::CliInvocation) -> Result<(), CommandError> {
    let relative = invocation.config.get(b"ui", b"relative-paths");
    if relative.is_some() {
        return Err(CommandError::unsupported(
            "non-default ui.relative-paths",
        ));
    }

    let rev = invocation.subcommand_args.value_of("rev");

    let repo = invocation.repo?;
    if let Some(rev) = rev {
        let files = list_rev_tracked_files(repo, rev).map_err(|e| (e, rev))?;
        display_files(invocation.ui, repo, files.iter())
    } else {
        let distate = Dirstate::new(repo)?;
        let files = distate.tracked_files()?;
        display_files(invocation.ui, repo, files.into_iter().map(Ok))
    }
}

fn display_files<'a>(
    ui: &Ui,
    repo: &Repo,
    files: impl IntoIterator<Item = Result<&'a HgPath, HgError>>,
) -> Result<(), CommandError> {
    let mut stdout = ui.stdout_buffer();
    let mut any = false;

    relativize_paths(repo, files, |path: Cow<[u8]>| -> Result<(), UiError> {
        any = true;
        stdout.write_all(path.as_ref())?;
        stdout.write_all(b"\n")
    })?;
    stdout.flush()?;
    if any {
        Ok(())
    } else {
        Err(CommandError::Unsuccessful)
    }
}

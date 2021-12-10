use crate::error::CommandError;
use crate::ui::Ui;
use crate::utils::path_utils::RelativizePaths;
use clap::Arg;
use hg::errors::HgError;
use hg::operations::list_rev_tracked_files;
use hg::operations::Dirstate;
use hg::repo::Repo;
use hg::utils::hg_path::HgPath;

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

    // It seems better if this check is removed: this would correspond to
    // automatically enabling the extension if the repo requires it.
    // However we need this check to be in sync with vanilla hg so hg tests
    // pass.
    if repo.has_sparse()
        && invocation.config.get(b"extensions", b"sparse").is_none()
    {
        return Err(CommandError::unsupported(
            "repo is using sparse, but sparse extension is not enabled",
        ));
    }

    if let Some(rev) = rev {
        if repo.has_narrow() {
            return Err(CommandError::unsupported(
                "rhg files -r <rev> is not supported in narrow clones",
            ));
        }
        let files = list_rev_tracked_files(repo, rev).map_err(|e| (e, rev))?;
        display_files(invocation.ui, repo, files.iter())
    } else {
        // The dirstate always reflects the sparse narrowspec, so if
        // we only have sparse without narrow all is fine.
        // If we have narrow, then [hg files] needs to check if
        // the store narrowspec is in sync with the one of the dirstate,
        // so we can't support that without explicit code.
        if repo.has_narrow() {
            return Err(CommandError::unsupported(
                "rhg files is not supported in narrow clones",
            ));
        }
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

    let relativize = RelativizePaths::new(repo)?;
    for result in files {
        let path = result?;
        stdout.write_all(&relativize.relativize(path))?;
        stdout.write_all(b"\n")?;
        any = true;
    }

    stdout.flush()?;
    if any {
        Ok(())
    } else {
        Err(CommandError::Unsuccessful)
    }
}

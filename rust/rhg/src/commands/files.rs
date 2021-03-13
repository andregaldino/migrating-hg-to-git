use crate::error::CommandError;
use crate::ui::Ui;
use clap::Arg;
use hg::operations::list_rev_tracked_files;
use hg::operations::Dirstate;
use hg::repo::Repo;
use hg::utils::current_dir;
use hg::utils::files::{get_bytes_from_path, relativize_path};
use hg::utils::hg_path::{HgPath, HgPathBuf};

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
        display_files(invocation.ui, repo, files)
    }
}

fn display_files<'a>(
    ui: &Ui,
    repo: &Repo,
    files: impl IntoIterator<Item = &'a HgPath>,
) -> Result<(), CommandError> {
    let mut stdout = ui.stdout_buffer();

    let cwd = current_dir()?;
    let working_directory = repo.working_directory_path();
    let working_directory = cwd.join(working_directory); // Make it absolute

    let mut any = false;
    if let Ok(cwd_relative_to_repo) = cwd.strip_prefix(&working_directory) {
        // The current directory is inside the repo, so we can work with
        // relative paths
        let cwd = HgPathBuf::from(get_bytes_from_path(cwd_relative_to_repo));
        for file in files {
            any = true;
            stdout.write_all(relativize_path(&file, &cwd).as_ref())?;
            stdout.write_all(b"\n")?;
        }
    } else {
        let working_directory =
            HgPathBuf::from(get_bytes_from_path(working_directory));
        let cwd = HgPathBuf::from(get_bytes_from_path(cwd));
        for file in files {
            any = true;
            // Absolute path in the filesystem
            let file = working_directory.join(file);
            stdout.write_all(relativize_path(&file, &cwd).as_ref())?;
            stdout.write_all(b"\n")?;
        }
    }

    stdout.flush()?;
    if any {
        Ok(())
    } else {
        Err(CommandError::Unsuccessful)
    }
}

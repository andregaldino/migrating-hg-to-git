use crate::error::CommandError;
use clap::Arg;
use hg::operations::cat;
use hg::repo::Repo;
use hg::utils::hg_path::HgPathBuf;
use micro_timer::timed;
use std::convert::TryFrom;

pub const HELP_TEXT: &str = "
Output the current or given revision of files
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("cat")
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
        .about(HELP_TEXT)
}

#[timed]
pub fn run(invocation: &crate::CliInvocation) -> Result<(), CommandError> {
    let rev = invocation.subcommand_args.value_of("rev");
    let file_args = match invocation.subcommand_args.values_of("files") {
        Some(files) => files.collect(),
        None => vec![],
    };

    let repo = Repo::find(invocation.non_repo_config, invocation.repo_path)?;
    let cwd = hg::utils::current_dir()?;

    let mut files = vec![];
    for file in file_args.iter() {
        // TODO: actually normalize `..` path segments etc?
        let normalized = cwd.join(&file);
        let stripped = normalized
            .strip_prefix(&repo.working_directory_path())
            // TODO: error message for path arguments outside of the repo
            .map_err(|_| CommandError::abort(""))?;
        let hg_file = HgPathBuf::try_from(stripped.to_path_buf())
            .map_err(|e| CommandError::abort(e.to_string()))?;
        files.push(hg_file);
    }

    match rev {
        Some(rev) => {
            let data = cat(&repo, rev, &files).map_err(|e| (e, rev))?;
            invocation.ui.write_stdout(&data)?;
            Ok(())
        }
        None => Err(CommandError::Unimplemented.into()),
    }
}

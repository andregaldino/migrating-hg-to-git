use crate::error::CommandError;
use clap::Arg;
use format_bytes::format_bytes;
use hg::operations::cat;
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
                .long("--rev")
                .value_name("REV")
                .takes_value(true),
        )
        .arg(
            clap::Arg::with_name("files")
                .required(true)
                .multiple(true)
                .empty_values(false)
                .value_name("FILE")
                .help("Files to output"),
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

    let repo = invocation.repo?;
    let cwd = hg::utils::current_dir()?;
    let working_directory = repo.working_directory_path();
    let working_directory = cwd.join(working_directory); // Make it absolute

    let mut files = vec![];
    for file in file_args.iter() {
        if file.starts_with("set:") {
            let message = "fileset";
            return Err(CommandError::unsupported(message));
        }

        let normalized = cwd.join(&file);
        // TODO: actually normalize `..` path segments etc?
        let dotted = normalized.components().any(|c| c.as_os_str() == "..");
        if file == &"." || dotted {
            let message = "`..` or `.` path segment";
            return Err(CommandError::unsupported(message));
        }
        let stripped = normalized
            .strip_prefix(&working_directory)
            // TODO: error message for path arguments outside of the repo
            .map_err(|_| CommandError::abort(""))?;
        let hg_file = HgPathBuf::try_from(stripped.to_path_buf())
            .map_err(|e| CommandError::abort(e.to_string()))?;
        files.push(hg_file);
    }
    // TODO probably move this to a util function like `repo.default_rev` or
    // something when it's used somewhere else
    let rev = match rev {
        Some(r) => r.to_string(),
        None => format!("{:x}", repo.dirstate_parents()?.p1),
    };

    let output = cat(&repo, &rev, &files).map_err(|e| (e, rev.as_str()))?;
    invocation.ui.write_stdout(&output.concatenated)?;
    if !output.missing.is_empty() {
        let short = format!("{:x}", output.node.short()).into_bytes();
        for path in &output.missing {
            invocation.ui.write_stderr(&format_bytes!(
                b"{}: no such file in rev {}\n",
                path.as_bytes(),
                short
            ))?;
        }
    }
    if output.found_any {
        Ok(())
    } else {
        Err(CommandError::Unsuccessful)
    }
}

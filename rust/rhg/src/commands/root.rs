use crate::error::CommandError;
use format_bytes::format_bytes;
use hg::repo::Repo;
use hg::utils::files::get_bytes_from_path;

pub const HELP_TEXT: &str = "
Print the root directory of the current repository.

Returns 0 on success.
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("root").about(HELP_TEXT)
}

pub fn run(invocation: &crate::CliInvocation) -> Result<(), CommandError> {
    let repo = Repo::find(invocation.non_repo_config, invocation.repo_path)?;
    let bytes = get_bytes_from_path(repo.working_directory_path());
    invocation
        .ui
        .write_stdout(&format_bytes!(b"{}\n", bytes.as_slice()))?;
    Ok(())
}

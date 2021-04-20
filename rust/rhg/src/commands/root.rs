use crate::error::CommandError;
use format_bytes::format_bytes;
use hg::errors::{IoErrorContext, IoResultExt};
use hg::utils::files::get_bytes_from_path;

pub const HELP_TEXT: &str = "
Print the root directory of the current repository.

Returns 0 on success.
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("root").about(HELP_TEXT)
}

pub fn run(invocation: &crate::CliInvocation) -> Result<(), CommandError> {
    let repo = invocation.repo?;
    let working_directory = repo.working_directory_path();
    let working_directory = std::fs::canonicalize(working_directory)
        .with_context(|| {
            IoErrorContext::CanonicalizingPath(working_directory.to_owned())
        })?;
    let bytes = get_bytes_from_path(&working_directory);
    invocation
        .ui
        .write_stdout(&format_bytes!(b"{}\n", bytes.as_slice()))?;
    Ok(())
}

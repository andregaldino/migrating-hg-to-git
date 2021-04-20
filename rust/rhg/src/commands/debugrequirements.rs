use crate::error::CommandError;

pub const HELP_TEXT: &str = "
Print the current repo requirements.
";

pub fn args() -> clap::App<'static, 'static> {
    clap::SubCommand::with_name("debugrequirements").about(HELP_TEXT)
}

pub fn run(invocation: &crate::CliInvocation) -> Result<(), CommandError> {
    let repo = invocation.repo?;
    let mut output = String::new();
    let mut requirements: Vec<_> = repo.requirements().iter().collect();
    requirements.sort();
    for req in requirements {
        output.push_str(req);
        output.push('\n');
    }
    invocation.ui.write_stdout(output.as_bytes())?;
    Ok(())
}

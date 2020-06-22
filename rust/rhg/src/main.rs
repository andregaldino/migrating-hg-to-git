mod commands;
mod error;
mod exitcode;

fn main() {
    std::process::exit(exitcode::UNIMPLEMENTED_COMMAND)
}

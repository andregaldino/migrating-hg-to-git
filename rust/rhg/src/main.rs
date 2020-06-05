mod commands;
mod error;
mod exitcode;
mod ui;

fn main() {
    std::process::exit(exitcode::UNIMPLEMENTED_COMMAND)
}

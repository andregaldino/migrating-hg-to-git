pub mod root;
use crate::error::CommandError;

/// The common trait for rhg commands
///
/// Normalize the interface of the commands provided by rhg
pub trait Command {
    fn run(&self) -> Result<(), CommandError>;
}

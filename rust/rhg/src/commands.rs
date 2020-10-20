pub mod cat;
pub mod debugdata;
pub mod files;
pub mod root;
use crate::error::CommandError;
use crate::ui::Ui;

/// The common trait for rhg commands
///
/// Normalize the interface of the commands provided by rhg
pub trait Command {
    fn run(&self, ui: &Ui) -> Result<(), CommandError>;
}

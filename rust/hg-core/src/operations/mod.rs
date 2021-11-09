//! A distinction is made between operations and commands.
//! An operation is what can be done whereas a command is what is exposed by
//! the cli. A single command can use several operations to achieve its goal.

mod cat;
mod debugdata;
mod list_tracked_files;
pub use cat::{cat, CatOutput};
pub use debugdata::{debug_data, DebugDataKind};
pub use list_tracked_files::Dirstate;
pub use list_tracked_files::{list_rev_tracked_files, FilesForRev};

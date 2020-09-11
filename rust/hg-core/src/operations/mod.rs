//! A distinction is made between operations and commands.
//! An operation is what can be done whereas a command is what is exposed by
//! the cli. A single command can use several operations to achieve its goal.

mod cat;
mod debugdata;
mod dirstate_status;
mod find_root;
mod list_tracked_files;
pub use cat::{CatRev, CatRevError, CatRevErrorKind};
pub use debugdata::{
    DebugData, DebugDataError, DebugDataErrorKind, DebugDataKind,
};
pub use find_root::{FindRoot, FindRootError, FindRootErrorKind};
pub use list_tracked_files::{
    ListDirstateTrackedFiles, ListDirstateTrackedFilesError,
    ListDirstateTrackedFilesErrorKind,
};
pub use list_tracked_files::{
    ListRevTrackedFiles, ListRevTrackedFilesError,
    ListRevTrackedFilesErrorKind,
};

// TODO add an `Operation` trait when GAT have landed (rust #44265):
// there is no way to currently define a trait which can both return
// references to `self` and to passed data, which is what we would need.
// Generic Associated Types may fix this and allow us to have a unified
// interface.

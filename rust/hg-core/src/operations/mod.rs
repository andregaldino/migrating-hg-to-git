mod dirstate_status;
mod find_root;
pub use find_root::{FindRoot, FindRootError, FindRootErrorKind};

/// An interface for high-level hg operations.
///
/// A distinction is made between operation and commands.
/// An operation is what can be done whereas a command is what is exposed by
/// the cli. A single command can use several operations to achieve its goal.
pub trait Operation<T> {
    type Error;
    fn run(&self) -> Result<T, Self::Error>;
}

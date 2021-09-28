//! The revset query language
//!
//! <https://www.mercurial-scm.org/repo/hg/help/revsets>

use crate::errors::HgError;
use crate::repo::Repo;
use crate::revlog::revlog::{Revlog, RevlogError};
use crate::revlog::NodePrefix;
use crate::revlog::{Revision, NULL_REVISION, WORKING_DIRECTORY_HEX};
use crate::Node;

/// Resolve a query string into a single revision.
///
/// Only some of the revset language is implemented yet.
pub fn resolve_single(
    input: &str,
    repo: &Repo,
) -> Result<Revision, RevlogError> {
    let changelog = repo.changelog()?;

    match resolve_rev_number_or_hex_prefix(input, &changelog.revlog) {
        Err(RevlogError::InvalidRevision) => {} // Try other syntax
        result => return result,
    }

    if input == "null" {
        return Ok(NULL_REVISION);
    }

    // TODO: support for the rest of the language here.

    Err(
        HgError::unsupported(format!("cannot parse revset '{}'", input))
            .into(),
    )
}

/// Resolve the small subset of the language suitable for revlogs other than
/// the changelog, such as in `hg debugdata --manifest` CLI argument.
///
/// * A non-negative decimal integer for a revision number, or
/// * An hexadecimal string, for the unique node ID that starts with this
///   prefix
pub fn resolve_rev_number_or_hex_prefix(
    input: &str,
    revlog: &Revlog,
) -> Result<Revision, RevlogError> {
    // The Python equivalent of this is part of `revsymbol` in
    // `mercurial/scmutil.py`

    if let Ok(integer) = input.parse::<i32>() {
        if integer.to_string() == input
            && integer >= 0
            && revlog.has_rev(integer)
        {
            return Ok(integer);
        }
    }
    if let Ok(prefix) = NodePrefix::from_hex(input) {
        if prefix.is_prefix_of(&Node::from_hex(WORKING_DIRECTORY_HEX).unwrap())
        {
            return Err(RevlogError::WDirUnsupported);
        }
        return revlog.rev_from_node(prefix);
    }
    Err(RevlogError::InvalidRevision)
}

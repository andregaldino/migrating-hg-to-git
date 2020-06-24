// dirstate_status.rs
//
// Copyright 2019, Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::dirstate::status::{build_response, Dispatch, HgPathCow, Status};
use crate::matchers::Matcher;
use crate::operations::Operation;
use crate::{DirstateStatus, StatusError};

/// A tuple of the paths that need to be checked in the filelog because it's
/// ambiguous whether they've changed, and the rest of the already dispatched
/// files.
pub type LookupAndStatus<'a> = (Vec<HgPathCow<'a>>, DirstateStatus<'a>);

impl<'a, M: Matcher + Sync> Operation<LookupAndStatus<'a>> for Status<'a, M> {
    type Error = StatusError;

    fn run(&self) -> Result<LookupAndStatus<'a>, Self::Error> {
        let (traversed_sender, traversed_receiver) =
            crossbeam::channel::unbounded();

        // Step 1: check the files explicitly mentioned by the user
        let (work, mut results) = self.walk_explicit(traversed_sender.clone());

        if !work.is_empty() {
            // Hashmaps are quite a bit slower to build than vecs, so only
            // build it if needed.
            let old_results = results.iter().cloned().collect();

            // Step 2: recursively check the working directory for changes if
            // needed
            for (dir, dispatch) in work {
                match dispatch {
                    Dispatch::Directory { was_file } => {
                        if was_file {
                            results.push((dir.to_owned(), Dispatch::Removed));
                        }
                        if self.options.list_ignored
                            || self.options.list_unknown
                                && !self.dir_ignore(&dir)
                        {
                            self.traverse(
                                &dir,
                                &old_results,
                                &mut results,
                                traversed_sender.clone(),
                            )?;
                        }
                    }
                    _ => {
                        unreachable!("There can only be directories in `work`")
                    }
                }
            }
        }

        if !self.matcher.is_exact() {
            if self.options.list_unknown {
                self.handle_unknowns(&mut results)?;
            } else {
                // TODO this is incorrect, see issue6335
                // This requires a fix in both Python and Rust that can happen
                // with other pending changes to `status`.
                self.extend_from_dmap(&mut results);
            }
        }

        drop(traversed_sender);
        let traversed = traversed_receiver.into_iter().collect();

        Ok(build_response(results, traversed))
    }
}

// dirstate_tree.rs
//
// Copyright 2020, Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Special-case radix tree that matches a filesystem hierarchy for use in the
//! dirstate.
//! It has not been optimized at all yet.

pub mod iter;
pub mod node;
pub mod tree;

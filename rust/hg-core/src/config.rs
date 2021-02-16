// config.rs
//
// Copyright 2020
//      Valentin Gatien-Baron,
//      Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Mercurial config parsing and interfaces.

mod config;
mod layer;
pub use config::{Config, ConfigValueParseError};
pub use layer::{ConfigError, ConfigParseError};

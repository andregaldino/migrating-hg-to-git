// config.rs
//
// Copyright 2020
//      Valentin Gatien-Baron,
//      Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use super::layer;
use crate::config::layer::{
    ConfigError, ConfigLayer, ConfigParseError, ConfigValue,
};
use std::path::PathBuf;

use crate::repo::Repo;

/// Holds the config values for the current repository
/// TODO update this docstring once we support more sources
pub struct Config {
    layers: Vec<layer::ConfigLayer>,
}

impl std::fmt::Debug for Config {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        for (index, layer) in self.layers.iter().rev().enumerate() {
            write!(
                f,
                "==== Layer {} (trusted: {}) ====\n{:?}",
                index, layer.trusted, layer
            )?;
        }
        Ok(())
    }
}

pub enum ConfigSource {
    /// Absolute path to a config file
    AbsPath(PathBuf),
    /// Already parsed (from the CLI, env, Python resources, etc.)
    Parsed(layer::ConfigLayer),
}

pub fn parse_bool(v: &[u8]) -> Option<bool> {
    match v.to_ascii_lowercase().as_slice() {
        b"1" | b"yes" | b"true" | b"on" | b"always" => Some(true),
        b"0" | b"no" | b"false" | b"off" | b"never" => Some(false),
        _ => None,
    }
}

impl Config {
    /// Loads in order, which means that the precedence is the same
    /// as the order of `sources`.
    pub fn load_from_explicit_sources(
        sources: Vec<ConfigSource>,
    ) -> Result<Self, ConfigError> {
        let mut layers = vec![];

        for source in sources.into_iter() {
            match source {
                ConfigSource::Parsed(c) => layers.push(c),
                ConfigSource::AbsPath(c) => {
                    // TODO check if it should be trusted
                    // mercurial/ui.py:427
                    let data = match std::fs::read(&c) {
                        Err(_) => continue, // same as the python code
                        Ok(data) => data,
                    };
                    layers.extend(ConfigLayer::parse(&c, &data)?)
                }
            }
        }

        Ok(Config { layers })
    }

    /// Loads the local config. In a future version, this will also load the
    /// `$HOME/.hgrc` and more to mirror the Python implementation.
    pub fn load_for_repo(repo: &Repo) -> Result<Self, ConfigError> {
        Ok(Self::load_from_explicit_sources(vec![
            ConfigSource::AbsPath(repo.hg_vfs().join("hgrc")),
        ])?)
    }

    /// Returns an `Err` if the first value found is not a valid boolean.
    /// Otherwise, returns an `Ok(option)`, where `option` is the boolean if
    /// found, or `None`.
    pub fn get_option(
        &self,
        section: &[u8],
        item: &[u8],
    ) -> Result<Option<bool>, ConfigParseError> {
        match self.get_inner(&section, &item) {
            Some((layer, v)) => match parse_bool(&v.bytes) {
                Some(b) => Ok(Some(b)),
                None => Err(ConfigParseError {
                    origin: layer.origin.to_owned(),
                    line: v.line,
                    bytes: v.bytes.to_owned(),
                }),
            },
            None => Ok(None),
        }
    }

    /// Returns the corresponding boolean in the config. Returns `Ok(false)`
    /// if the value is not found, an `Err` if it's not a valid boolean.
    pub fn get_bool(
        &self,
        section: &[u8],
        item: &[u8],
    ) -> Result<bool, ConfigError> {
        Ok(self.get_option(section, item)?.unwrap_or(false))
    }

    /// Returns the raw value bytes of the first one found, or `None`.
    pub fn get(&self, section: &[u8], item: &[u8]) -> Option<&[u8]> {
        self.get_inner(section, item)
            .map(|(_, value)| value.bytes.as_ref())
    }

    /// Returns the layer and the value of the first one found, or `None`.
    fn get_inner(
        &self,
        section: &[u8],
        item: &[u8],
    ) -> Option<(&ConfigLayer, &ConfigValue)> {
        for layer in self.layers.iter().rev() {
            if !layer.trusted {
                continue;
            }
            if let Some(v) = layer.get(&section, &item) {
                return Some((&layer, v));
            }
        }
        None
    }

    /// Get raw values bytes from all layers (even untrusted ones) in order
    /// of precedence.
    #[cfg(test)]
    fn get_all(&self, section: &[u8], item: &[u8]) -> Vec<&[u8]> {
        let mut res = vec![];
        for layer in self.layers.iter().rev() {
            if let Some(v) = layer.get(&section, &item) {
                res.push(v.bytes.as_ref());
            }
        }
        res
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use std::fs::File;
    use std::io::Write;

    #[test]
    fn test_include_layer_ordering() {
        let tmpdir = tempfile::tempdir().unwrap();
        let tmpdir_path = tmpdir.path();
        let mut included_file =
            File::create(&tmpdir_path.join("included.rc")).unwrap();

        included_file.write_all(b"[section]\nitem=value1").unwrap();
        let base_config_path = tmpdir_path.join("base.rc");
        let mut config_file = File::create(&base_config_path).unwrap();
        let data =
            b"[section]\nitem=value0\n%include included.rc\nitem=value2";
        config_file.write_all(data).unwrap();

        let sources = vec![ConfigSource::AbsPath(base_config_path)];
        let config = Config::load_from_explicit_sources(sources)
            .expect("expected valid config");

        dbg!(&config);

        let (_, value) = config.get_inner(b"section", b"item").unwrap();
        assert_eq!(
            value,
            &ConfigValue {
                bytes: b"value2".to_vec(),
                line: Some(4)
            }
        );

        let value = config.get(b"section", b"item").unwrap();
        assert_eq!(value, b"value2",);
        assert_eq!(
            config.get_all(b"section", b"item"),
            [b"value2", b"value1", b"value0"]
        );
    }
}

// layer.rs
//
// Copyright 2020
//      Valentin Gatien-Baron,
//      Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::errors::{HgError, IoResultExt};
use crate::utils::files::{get_bytes_from_path, get_path_from_bytes};
use format_bytes::{write_bytes, DisplayBytes};
use lazy_static::lazy_static;
use regex::bytes::Regex;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

lazy_static! {
    static ref SECTION_RE: Regex = make_regex(r"^\[([^\[]+)\]");
    static ref ITEM_RE: Regex = make_regex(r"^([^=\s][^=]*?)\s*=\s*((.*\S)?)");
    /// Continuation whitespace
    static ref CONT_RE: Regex = make_regex(r"^\s+(\S|\S.*\S)\s*$");
    static ref EMPTY_RE: Regex = make_regex(r"^(;|#|\s*$)");
    static ref COMMENT_RE: Regex = make_regex(r"^(;|#)");
    /// A directive that allows for removing previous entries
    static ref UNSET_RE: Regex = make_regex(r"^%unset\s+(\S+)");
    /// A directive that allows for including other config files
    static ref INCLUDE_RE: Regex = make_regex(r"^%include\s+(\S|\S.*\S)\s*$");
}

/// All config values separated by layers of precedence.
/// Each config source may be split in multiple layers if `%include` directives
/// are used.
/// TODO detail the general precedence
#[derive(Clone)]
pub struct ConfigLayer {
    /// Mapping of the sections to their items
    sections: HashMap<Vec<u8>, ConfigItem>,
    /// All sections (and their items/values) in a layer share the same origin
    pub origin: ConfigOrigin,
    /// Whether this layer comes from a trusted user or group
    pub trusted: bool,
}

impl ConfigLayer {
    pub fn new(origin: ConfigOrigin) -> Self {
        ConfigLayer {
            sections: HashMap::new(),
            trusted: true, // TODO check
            origin,
        }
    }

    /// Parse `--config` CLI arguments and return a layer if there’s any
    pub(crate) fn parse_cli_args(
        cli_config_args: impl IntoIterator<Item = impl AsRef<[u8]>>,
    ) -> Result<Option<Self>, ConfigError> {
        fn parse_one(arg: &[u8]) -> Option<(Vec<u8>, Vec<u8>, Vec<u8>)> {
            use crate::utils::SliceExt;

            let (section_and_item, value) = arg.split_2(b'=')?;
            let (section, item) = section_and_item.trim().split_2(b'.')?;
            Some((
                section.to_owned(),
                item.to_owned(),
                value.trim().to_owned(),
            ))
        }

        let mut layer = Self::new(ConfigOrigin::CommandLine);
        for arg in cli_config_args {
            let arg = arg.as_ref();
            if let Some((section, item, value)) = parse_one(arg) {
                layer.add(section, item, value, None);
            } else {
                Err(HgError::abort(format!(
                    "malformed --config option: '{}' \
                    (use --config section.name=value)",
                    String::from_utf8_lossy(arg),
                )))?
            }
        }
        if layer.sections.is_empty() {
            Ok(None)
        } else {
            Ok(Some(layer))
        }
    }

    /// Returns whether this layer comes from `--config` CLI arguments
    pub(crate) fn is_from_command_line(&self) -> bool {
        if let ConfigOrigin::CommandLine = self.origin {
            true
        } else {
            false
        }
    }

    /// Add an entry to the config, overwriting the old one if already present.
    pub fn add(
        &mut self,
        section: Vec<u8>,
        item: Vec<u8>,
        value: Vec<u8>,
        line: Option<usize>,
    ) {
        self.sections
            .entry(section)
            .or_insert_with(|| HashMap::new())
            .insert(item, ConfigValue { bytes: value, line });
    }

    /// Returns the config value in `<section>.<item>` if it exists
    pub fn get(&self, section: &[u8], item: &[u8]) -> Option<&ConfigValue> {
        Some(self.sections.get(section)?.get(item)?)
    }

    pub fn is_empty(&self) -> bool {
        self.sections.is_empty()
    }

    /// Returns a `Vec` of layers in order of precedence (so, in read order),
    /// recursively parsing the `%include` directives if any.
    pub fn parse(src: &Path, data: &[u8]) -> Result<Vec<Self>, ConfigError> {
        let mut layers = vec![];

        // Discard byte order mark if any
        let data = if data.starts_with(b"\xef\xbb\xbf") {
            &data[3..]
        } else {
            data
        };

        // TODO check if it's trusted
        let mut current_layer = Self::new(ConfigOrigin::File(src.to_owned()));

        let mut lines_iter =
            data.split(|b| *b == b'\n').enumerate().peekable();
        let mut section = b"".to_vec();

        while let Some((index, bytes)) = lines_iter.next() {
            if let Some(m) = INCLUDE_RE.captures(&bytes) {
                let filename_bytes = &m[1];
                // `Path::parent` only fails for the root directory,
                // which `src` can’t be since we’ve managed to open it as a
                // file.
                let dir = src
                    .parent()
                    .expect("Path::parent fail on a file we’ve read");
                // `Path::join` with an absolute argument correctly ignores the
                // base path
                let filename = dir.join(&get_path_from_bytes(&filename_bytes));
                let data =
                    std::fs::read(&filename).when_reading_file(&filename)?;
                layers.push(current_layer);
                layers.extend(Self::parse(&filename, &data)?);
                current_layer = Self::new(ConfigOrigin::File(src.to_owned()));
            } else if let Some(_) = EMPTY_RE.captures(&bytes) {
            } else if let Some(m) = SECTION_RE.captures(&bytes) {
                section = m[1].to_vec();
            } else if let Some(m) = ITEM_RE.captures(&bytes) {
                let item = m[1].to_vec();
                let mut value = m[2].to_vec();
                loop {
                    match lines_iter.peek() {
                        None => break,
                        Some((_, v)) => {
                            if let Some(_) = COMMENT_RE.captures(&v) {
                            } else if let Some(_) = CONT_RE.captures(&v) {
                                value.extend(b"\n");
                                value.extend(&m[1]);
                            } else {
                                break;
                            }
                        }
                    };
                    lines_iter.next();
                }
                current_layer.add(
                    section.clone(),
                    item,
                    value,
                    Some(index + 1),
                );
            } else if let Some(m) = UNSET_RE.captures(&bytes) {
                if let Some(map) = current_layer.sections.get_mut(&section) {
                    map.remove(&m[1]);
                }
            } else {
                return Err(ConfigParseError {
                    origin: ConfigOrigin::File(src.to_owned()),
                    line: Some(index + 1),
                    bytes: bytes.to_owned(),
                }
                .into());
            }
        }
        if !current_layer.is_empty() {
            layers.push(current_layer);
        }
        Ok(layers)
    }
}

impl DisplayBytes for ConfigLayer {
    fn display_bytes(
        &self,
        out: &mut dyn std::io::Write,
    ) -> std::io::Result<()> {
        let mut sections: Vec<_> = self.sections.iter().collect();
        sections.sort_by(|e0, e1| e0.0.cmp(e1.0));

        for (section, items) in sections.into_iter() {
            let mut items: Vec<_> = items.into_iter().collect();
            items.sort_by(|e0, e1| e0.0.cmp(e1.0));

            for (item, config_entry) in items {
                write_bytes!(
                    out,
                    b"{}.{}={} # {}\n",
                    section,
                    item,
                    &config_entry.bytes,
                    &self.origin,
                )?
            }
        }
        Ok(())
    }
}

/// Mapping of section item to value.
/// In the following:
/// ```text
/// [ui]
/// paginate=no
/// ```
/// "paginate" is the section item and "no" the value.
pub type ConfigItem = HashMap<Vec<u8>, ConfigValue>;

#[derive(Clone, Debug, PartialEq)]
pub struct ConfigValue {
    /// The raw bytes of the value (be it from the CLI, env or from a file)
    pub bytes: Vec<u8>,
    /// Only present if the value comes from a file, 1-indexed.
    pub line: Option<usize>,
}

#[derive(Clone, Debug)]
pub enum ConfigOrigin {
    /// From a configuration file
    File(PathBuf),
    /// From a `--config` CLI argument
    CommandLine,
    /// From environment variables like `$PAGER` or `$EDITOR`
    Environment(Vec<u8>),
    /* TODO cli
     * TODO defaults (configitems.py)
     * TODO extensions
     * TODO Python resources?
     * Others? */
}

impl DisplayBytes for ConfigOrigin {
    fn display_bytes(
        &self,
        out: &mut dyn std::io::Write,
    ) -> std::io::Result<()> {
        match self {
            ConfigOrigin::File(p) => out.write_all(&get_bytes_from_path(p)),
            ConfigOrigin::CommandLine => out.write_all(b"--config"),
            ConfigOrigin::Environment(e) => write_bytes!(out, b"${}", e),
        }
    }
}

#[derive(Debug)]
pub struct ConfigParseError {
    pub origin: ConfigOrigin,
    pub line: Option<usize>,
    pub bytes: Vec<u8>,
}

#[derive(Debug, derive_more::From)]
pub enum ConfigError {
    Parse(ConfigParseError),
    Other(HgError),
}

fn make_regex(pattern: &'static str) -> Regex {
    Regex::new(pattern).expect("expected a valid regex")
}

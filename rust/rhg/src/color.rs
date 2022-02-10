use crate::ui::formatted;
use crate::ui::plain;
use format_bytes::write_bytes;
use hg::config::Config;
use hg::config::ConfigOrigin;
use hg::errors::HgError;
use std::collections::HashMap;

pub type Effect = u32;

pub type EffectsMap = HashMap<Vec<u8>, Vec<Effect>>;

macro_rules! effects {
    ($( $name: ident: $value: expr ,)+) => {

        #[allow(non_upper_case_globals)]
        mod effects {
            $(
                pub const $name: super::Effect = $value;
            )+
        }

        fn effect(name: &[u8]) -> Option<Effect> {
            $(
                if name == stringify!($name).as_bytes() {
                    Some(effects::$name)
                } else
            )+
            {
                None
            }
        }
    };
}

effects! {
    none: 0,
    black: 30,
    red: 31,
    green: 32,
    yellow: 33,
    blue: 34,
    magenta: 35,
    cyan: 36,
    white: 37,
    bold: 1,
    italic: 3,
    underline: 4,
    inverse: 7,
    dim: 2,
    black_background: 40,
    red_background: 41,
    green_background: 42,
    yellow_background: 43,
    blue_background: 44,
    purple_background: 45,
    cyan_background: 46,
    white_background: 47,
}

macro_rules! default_styles {
    ($( $key: expr => [$($value: expr),*],)+) => {
        fn default_styles() -> EffectsMap {
            use effects::*;
            let mut map = HashMap::new();
            $(
                map.insert($key[..].to_owned(), vec![$( $value ),*]);
            )+
            map
        }
    };
}

default_styles! {
    b"grep.match" => [red, bold],
    b"grep.linenumber" => [green],
    b"grep.rev" => [blue],
    b"grep.sep" => [cyan],
    b"grep.filename" => [magenta],
    b"grep.user" => [magenta],
    b"grep.date" => [magenta],
    b"grep.inserted" => [green, bold],
    b"grep.deleted" => [red, bold],
    b"bookmarks.active" => [green],
    b"branches.active" => [none],
    b"branches.closed" => [black, bold],
    b"branches.current" => [green],
    b"branches.inactive" => [none],
    b"diff.changed" => [white],
    b"diff.deleted" => [red],
    b"diff.deleted.changed" => [red, bold, underline],
    b"diff.deleted.unchanged" => [red],
    b"diff.diffline" => [bold],
    b"diff.extended" => [cyan, bold],
    b"diff.file_a" => [red, bold],
    b"diff.file_b" => [green, bold],
    b"diff.hunk" => [magenta],
    b"diff.inserted" => [green],
    b"diff.inserted.changed" => [green, bold, underline],
    b"diff.inserted.unchanged" => [green],
    b"diff.tab" => [],
    b"diff.trailingwhitespace" => [bold, red_background],
    b"changeset.public" => [],
    b"changeset.draft" => [],
    b"changeset.secret" => [],
    b"diffstat.deleted" => [red],
    b"diffstat.inserted" => [green],
    b"formatvariant.name.mismatchconfig" => [red],
    b"formatvariant.name.mismatchdefault" => [yellow],
    b"formatvariant.name.uptodate" => [green],
    b"formatvariant.repo.mismatchconfig" => [red],
    b"formatvariant.repo.mismatchdefault" => [yellow],
    b"formatvariant.repo.uptodate" => [green],
    b"formatvariant.config.special" => [yellow],
    b"formatvariant.config.default" => [green],
    b"formatvariant.default" => [],
    b"histedit.remaining" => [red, bold],
    b"ui.addremove.added" => [green],
    b"ui.addremove.removed" => [red],
    b"ui.error" => [red],
    b"ui.prompt" => [yellow],
    b"log.changeset" => [yellow],
    b"patchbomb.finalsummary" => [],
    b"patchbomb.from" => [magenta],
    b"patchbomb.to" => [cyan],
    b"patchbomb.subject" => [green],
    b"patchbomb.diffstats" => [],
    b"rebase.rebased" => [blue],
    b"rebase.remaining" => [red, bold],
    b"resolve.resolved" => [green, bold],
    b"resolve.unresolved" => [red, bold],
    b"shelve.age" => [cyan],
    b"shelve.newest" => [green, bold],
    b"shelve.name" => [blue, bold],
    b"status.added" => [green, bold],
    b"status.clean" => [none],
    b"status.copied" => [none],
    b"status.deleted" => [cyan, bold, underline],
    b"status.ignored" => [black, bold],
    b"status.modified" => [blue, bold],
    b"status.removed" => [red, bold],
    b"status.unknown" => [magenta, bold, underline],
    b"tags.normal" => [green],
    b"tags.local" => [black, bold],
    b"upgrade-repo.requirement.preserved" => [cyan],
    b"upgrade-repo.requirement.added" => [green],
    b"upgrade-repo.requirement.removed" => [red],
}

fn parse_effect(config_key: &[u8], effect_name: &[u8]) -> Option<Effect> {
    let found = effect(effect_name);
    if found.is_none() {
        // TODO: have some API for warnings
        // TODO: handle IO errors during warnings
        let stderr = std::io::stderr();
        let _ = write_bytes!(
            &mut stderr.lock(),
            b"ignoring unknown color/effect '{}' \
              (configured in color.{})\n",
            effect_name,
            config_key,
        );
    }
    found
}

fn effects_from_config(config: &Config) -> EffectsMap {
    let mut styles = default_styles();
    for (key, _value) in config.iter_section(b"color") {
        if !key.contains(&b'.')
            || key.starts_with(b"color.")
            || key.starts_with(b"terminfo.")
        {
            continue;
        }
        // `unwrap` shouldn’t panic since we just got this key from
        // iteration
        let list = config.get_list(b"color", key).unwrap();
        let parsed = list
            .iter()
            .filter_map(|name| parse_effect(key, name))
            .collect();
        styles.insert(key.to_owned(), parsed);
    }
    styles
}

enum ColorMode {
    // TODO: support other modes
    Ansi,
}

impl ColorMode {
    // Similar to _modesetup in mercurial/color.py
    fn get(config: &Config) -> Result<Option<Self>, HgError> {
        if plain(Some("color")) {
            return Ok(None);
        }
        let enabled_default = b"auto";
        // `origin` is only used when `!auto`, so its default doesn’t matter
        let (enabled, origin) = config
            .get_with_origin(b"ui", b"color")
            .unwrap_or((enabled_default, &ConfigOrigin::CommandLineColor));
        if enabled == b"debug" {
            return Err(HgError::unsupported("debug color mode"));
        }
        let auto = enabled == b"auto";
        let always;
        if !auto {
            let enabled_bool = config.get_bool(b"ui", b"color")?;
            if !enabled_bool {
                return Ok(None);
            }
            always = enabled == b"always"
                || *origin == ConfigOrigin::CommandLineColor
        } else {
            always = false
        };
        let formatted = always
            || (std::env::var_os("TERM").unwrap_or_default() != "dumb"
                && formatted(config)?);

        let mode_default = b"auto";
        let mode = config.get(b"color", b"mode").unwrap_or(mode_default);

        if formatted {
            match mode {
                b"ansi" | b"auto" => Ok(Some(ColorMode::Ansi)),
                // TODO: support other modes
                _ => Err(HgError::UnsupportedFeature(format!(
                    "color mode {}",
                    String::from_utf8_lossy(mode)
                ))),
            }
        } else {
            Ok(None)
        }
    }
}

pub struct ColorConfig {
    pub styles: EffectsMap,
}

impl ColorConfig {
    // Similar to _modesetup in mercurial/color.py
    pub fn new(config: &Config) -> Result<Option<Self>, HgError> {
        Ok(match ColorMode::get(config)? {
            None => None,
            Some(ColorMode::Ansi) => Some(ColorConfig {
                styles: effects_from_config(config),
            }),
        })
    }
}

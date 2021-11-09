// status.rs
//
// Copyright 2020, Georges Racinet <georges.racinets@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::error::CommandError;
use crate::ui::{Ui, UiError};
use crate::utils::path_utils::relativize_paths;
use clap::{Arg, SubCommand};
use hg;
use hg::config::Config;
use hg::dirstate::TruncatedTimestamp;
use hg::errors::HgError;
use hg::manifest::Manifest;
use hg::matchers::AlwaysMatcher;
use hg::repo::Repo;
use hg::utils::hg_path::{hg_path_to_os_string, HgPath};
use hg::{HgPathCow, StatusOptions};
use log::{info, warn};
use std::borrow::Cow;

pub const HELP_TEXT: &str = "
Show changed files in the working directory

This is a pure Rust version of `hg status`.

Some options might be missing, check the list below.
";

pub fn args() -> clap::App<'static, 'static> {
    SubCommand::with_name("status")
        .alias("st")
        .about(HELP_TEXT)
        .arg(
            Arg::with_name("all")
                .help("show status of all files")
                .short("-A")
                .long("--all"),
        )
        .arg(
            Arg::with_name("modified")
                .help("show only modified files")
                .short("-m")
                .long("--modified"),
        )
        .arg(
            Arg::with_name("added")
                .help("show only added files")
                .short("-a")
                .long("--added"),
        )
        .arg(
            Arg::with_name("removed")
                .help("show only removed files")
                .short("-r")
                .long("--removed"),
        )
        .arg(
            Arg::with_name("clean")
                .help("show only clean files")
                .short("-c")
                .long("--clean"),
        )
        .arg(
            Arg::with_name("deleted")
                .help("show only deleted files")
                .short("-d")
                .long("--deleted"),
        )
        .arg(
            Arg::with_name("unknown")
                .help("show only unknown (not tracked) files")
                .short("-u")
                .long("--unknown"),
        )
        .arg(
            Arg::with_name("ignored")
                .help("show only ignored files")
                .short("-i")
                .long("--ignored"),
        )
}

/// Pure data type allowing the caller to specify file states to display
#[derive(Copy, Clone, Debug)]
pub struct DisplayStates {
    pub modified: bool,
    pub added: bool,
    pub removed: bool,
    pub clean: bool,
    pub deleted: bool,
    pub unknown: bool,
    pub ignored: bool,
}

pub const DEFAULT_DISPLAY_STATES: DisplayStates = DisplayStates {
    modified: true,
    added: true,
    removed: true,
    clean: false,
    deleted: true,
    unknown: true,
    ignored: false,
};

pub const ALL_DISPLAY_STATES: DisplayStates = DisplayStates {
    modified: true,
    added: true,
    removed: true,
    clean: true,
    deleted: true,
    unknown: true,
    ignored: true,
};

impl DisplayStates {
    pub fn is_empty(&self) -> bool {
        !(self.modified
            || self.added
            || self.removed
            || self.clean
            || self.deleted
            || self.unknown
            || self.ignored)
    }
}

pub fn run(invocation: &crate::CliInvocation) -> Result<(), CommandError> {
    let status_enabled_default = false;
    let status_enabled = invocation.config.get_option(b"rhg", b"status")?;
    if !status_enabled.unwrap_or(status_enabled_default) {
        return Err(CommandError::unsupported(
            "status is experimental in rhg (enable it with 'rhg.status = true' \
            or enable fallback with 'rhg.on-unsupported = fallback')"
        ));
    }

    // TODO: lift these limitations
    if invocation.config.get_bool(b"ui", b"tweakdefaults")? {
        return Err(CommandError::unsupported(
            "ui.tweakdefaults is not yet supported with rhg status",
        ));
    }
    if invocation.config.get_bool(b"ui", b"statuscopies")? {
        return Err(CommandError::unsupported(
            "ui.statuscopies is not yet supported with rhg status",
        ));
    }
    if invocation
        .config
        .get(b"commands", b"status.terse")
        .is_some()
    {
        return Err(CommandError::unsupported(
            "status.terse is not yet supported with rhg status",
        ));
    }

    let ui = invocation.ui;
    let config = invocation.config;
    let args = invocation.subcommand_args;
    let display_states = if args.is_present("all") {
        // TODO when implementing `--quiet`: it excludes clean files
        // from `--all`
        ALL_DISPLAY_STATES
    } else {
        let requested = DisplayStates {
            modified: args.is_present("modified"),
            added: args.is_present("added"),
            removed: args.is_present("removed"),
            clean: args.is_present("clean"),
            deleted: args.is_present("deleted"),
            unknown: args.is_present("unknown"),
            ignored: args.is_present("ignored"),
        };
        if requested.is_empty() {
            DEFAULT_DISPLAY_STATES
        } else {
            requested
        }
    };

    let repo = invocation.repo?;
    let mut dmap = repo.dirstate_map_mut()?;

    let options = StatusOptions {
        // TODO should be provided by the dirstate parsing and
        // hence be stored on dmap. Using a value that assumes we aren't
        // below the time resolution granularity of the FS and the
        // dirstate.
        last_normal_time: TruncatedTimestamp::new_truncate(0, 0),
        // we're currently supporting file systems with exec flags only
        // anyway
        check_exec: true,
        list_clean: display_states.clean,
        list_unknown: display_states.unknown,
        list_ignored: display_states.ignored,
        collect_traversed_dirs: false,
    };
    let ignore_file = repo.working_directory_vfs().join(".hgignore"); // TODO hardcoded
    let (mut ds_status, pattern_warnings) = dmap.status(
        &AlwaysMatcher,
        repo.working_directory_path().to_owned(),
        vec![ignore_file],
        options,
    )?;
    if !pattern_warnings.is_empty() {
        warn!("Pattern warnings: {:?}", &pattern_warnings);
    }

    if !ds_status.bad.is_empty() {
        warn!("Bad matches {:?}", &(ds_status.bad))
    }
    if !ds_status.unsure.is_empty() {
        info!(
            "Files to be rechecked by retrieval from filelog: {:?}",
            &ds_status.unsure
        );
    }
    if !ds_status.unsure.is_empty()
        && (display_states.modified || display_states.clean)
    {
        let p1 = repo.dirstate_parents()?.p1;
        let manifest = repo.manifest_for_node(p1).map_err(|e| {
            CommandError::from((e, &*format!("{:x}", p1.short())))
        })?;
        for to_check in ds_status.unsure {
            if cat_file_is_modified(repo, &manifest, &to_check)? {
                if display_states.modified {
                    ds_status.modified.push(to_check);
                }
            } else {
                if display_states.clean {
                    ds_status.clean.push(to_check);
                }
            }
        }
    }
    if display_states.modified {
        display_status_paths(ui, repo, config, &mut ds_status.modified, b"M")?;
    }
    if display_states.added {
        display_status_paths(ui, repo, config, &mut ds_status.added, b"A")?;
    }
    if display_states.removed {
        display_status_paths(ui, repo, config, &mut ds_status.removed, b"R")?;
    }
    if display_states.deleted {
        display_status_paths(ui, repo, config, &mut ds_status.deleted, b"!")?;
    }
    if display_states.unknown {
        display_status_paths(ui, repo, config, &mut ds_status.unknown, b"?")?;
    }
    if display_states.ignored {
        display_status_paths(ui, repo, config, &mut ds_status.ignored, b"I")?;
    }
    if display_states.clean {
        display_status_paths(ui, repo, config, &mut ds_status.clean, b"C")?;
    }
    Ok(())
}

// Probably more elegant to use a Deref or Borrow trait rather than
// harcode HgPathBuf, but probably not really useful at this point
fn display_status_paths(
    ui: &Ui,
    repo: &Repo,
    config: &Config,
    paths: &mut [HgPathCow],
    status_prefix: &[u8],
) -> Result<(), CommandError> {
    paths.sort_unstable();
    let mut relative: bool = config.get_bool(b"ui", b"relative-paths")?;
    relative = config
        .get_option(b"commands", b"status.relative")?
        .unwrap_or(relative);
    if relative && !ui.plain() {
        relativize_paths(
            repo,
            paths,
            |path: Cow<[u8]>| -> Result<(), UiError> {
                ui.write_stdout(
                    &[status_prefix, b" ", path.as_ref(), b"\n"].concat(),
                )
            },
        )?;
    } else {
        for path in paths {
            // Same TODO as in commands::root
            let bytes: &[u8] = path.as_bytes();
            // TODO optim, probably lots of unneeded copies here, especially
            // if out stream is buffered
            ui.write_stdout(&[status_prefix, b" ", bytes, b"\n"].concat())?;
        }
    }
    Ok(())
}

/// Check if a file is modified by comparing actual repo store and file system.
///
/// This meant to be used for those that the dirstate cannot resolve, due
/// to time resolution limits.
///
/// TODO: detect permission bits and similar metadata modifications
fn cat_file_is_modified(
    repo: &Repo,
    manifest: &Manifest,
    hg_path: &HgPath,
) -> Result<bool, HgError> {
    let file_node = manifest
        .find_file(hg_path)?
        .expect("ambgious file not in p1");
    let filelog = repo.filelog(hg_path)?;
    let filelog_entry = filelog.data_for_node(file_node).map_err(|_| {
        HgError::corrupted("filelog missing node from manifest")
    })?;
    let contents_in_p1 = filelog_entry.data()?;

    let fs_path = hg_path_to_os_string(hg_path).expect("HgPath conversion");
    let fs_contents = repo.working_directory_vfs().read(fs_path)?;
    return Ok(contents_in_p1 != &*fs_contents);
}

// status.rs
//
// Copyright 2020, Georges Racinet <georges.racinets@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::error::CommandError;
use crate::ui::Ui;
use clap::{Arg, SubCommand};
use hg;
use hg::dirstate_tree::dirstate_map::DirstateMap;
use hg::dirstate_tree::on_disk;
use hg::errors::HgResultExt;
use hg::errors::IoResultExt;
use hg::matchers::AlwaysMatcher;
use hg::operations::cat;
use hg::repo::Repo;
use hg::revlog::node::Node;
use hg::utils::hg_path::{hg_path_to_os_string, HgPath};
use hg::StatusError;
use hg::{HgPathCow, StatusOptions};
use log::{info, warn};
use std::convert::TryInto;
use std::fs;
use std::io::BufReader;
use std::io::Read;

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

    let ui = invocation.ui;
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
    let dirstate_data_mmap;
    let (mut dmap, parents) = if repo.has_dirstate_v2() {
        let docket_data =
            repo.hg_vfs().read("dirstate").io_not_found_as_none()?;
        let parents;
        let dirstate_data;
        let data_size;
        let docket;
        let tree_metadata;
        if let Some(docket_data) = &docket_data {
            docket = on_disk::read_docket(docket_data)?;
            tree_metadata = docket.tree_metadata();
            parents = Some(docket.parents());
            data_size = docket.data_size();
            dirstate_data_mmap = repo
                .hg_vfs()
                .mmap_open(docket.data_filename())
                .io_not_found_as_none()?;
            dirstate_data = dirstate_data_mmap.as_deref().unwrap_or(b"");
        } else {
            parents = None;
            tree_metadata = b"";
            data_size = 0;
            dirstate_data = b"";
        }
        let dmap =
            DirstateMap::new_v2(dirstate_data, data_size, tree_metadata)?;
        (dmap, parents)
    } else {
        dirstate_data_mmap =
            repo.hg_vfs().mmap_open("dirstate").io_not_found_as_none()?;
        let dirstate_data = dirstate_data_mmap.as_deref().unwrap_or(b"");
        DirstateMap::new_v1(dirstate_data)?
    };

    let options = StatusOptions {
        // TODO should be provided by the dirstate parsing and
        // hence be stored on dmap. Using a value that assumes we aren't
        // below the time resolution granularity of the FS and the
        // dirstate.
        last_normal_time: 0,
        // we're currently supporting file systems with exec flags only
        // anyway
        check_exec: true,
        list_clean: display_states.clean,
        list_unknown: display_states.unknown,
        list_ignored: display_states.ignored,
        collect_traversed_dirs: false,
    };
    let ignore_file = repo.working_directory_vfs().join(".hgignore"); // TODO hardcoded
    let (mut ds_status, pattern_warnings) = hg::dirstate_tree::status::status(
        &mut dmap,
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
        let p1: Node = parents
            .expect(
                "Dirstate with no parents should not list any file to
            be rechecked for modifications",
            )
            .p1
            .into();
        let p1_hex = format!("{:x}", p1);
        for to_check in ds_status.unsure {
            if cat_file_is_modified(repo, &to_check, &p1_hex)? {
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
        display_status_paths(ui, &mut ds_status.modified, b"M")?;
    }
    if display_states.added {
        display_status_paths(ui, &mut ds_status.added, b"A")?;
    }
    if display_states.removed {
        display_status_paths(ui, &mut ds_status.removed, b"R")?;
    }
    if display_states.deleted {
        display_status_paths(ui, &mut ds_status.deleted, b"!")?;
    }
    if display_states.unknown {
        display_status_paths(ui, &mut ds_status.unknown, b"?")?;
    }
    if display_states.ignored {
        display_status_paths(ui, &mut ds_status.ignored, b"I")?;
    }
    if display_states.clean {
        display_status_paths(ui, &mut ds_status.clean, b"C")?;
    }
    Ok(())
}

// Probably more elegant to use a Deref or Borrow trait rather than
// harcode HgPathBuf, but probably not really useful at this point
fn display_status_paths(
    ui: &Ui,
    paths: &mut [HgPathCow],
    status_prefix: &[u8],
) -> Result<(), CommandError> {
    paths.sort_unstable();
    for path in paths {
        // Same TODO as in commands::root
        let bytes: &[u8] = path.as_bytes();
        // TODO optim, probably lots of unneeded copies here, especially
        // if out stream is buffered
        ui.write_stdout(&[status_prefix, b" ", bytes, b"\n"].concat())?;
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
    hg_path: &HgPath,
    rev: &str,
) -> Result<bool, CommandError> {
    // TODO CatRev expects &[HgPathBuf], something like
    // &[impl Deref<HgPath>] would be nicer and should avoid the copy
    let path_bufs = [hg_path.into()];
    // TODO IIUC CatRev returns a simple Vec<u8> for all files
    //      being able to tell them apart as (path, bytes) would be nicer
    //      and OPTIM would allow manifest resolution just once.
    let output = cat(repo, rev, &path_bufs).map_err(|e| (e, rev))?;

    let fs_path = repo
        .working_directory_vfs()
        .join(hg_path_to_os_string(hg_path).expect("HgPath conversion"));
    let hg_data_len: u64 = match output.concatenated.len().try_into() {
        Ok(v) => v,
        Err(_) => {
            // conversion of data length to u64 failed,
            // good luck for any file to have this content
            return Ok(true);
        }
    };
    let fobj = fs::File::open(&fs_path).when_reading_file(&fs_path)?;
    if fobj.metadata().map_err(|e| StatusError::from(e))?.len() != hg_data_len
    {
        return Ok(true);
    }
    for (fs_byte, hg_byte) in
        BufReader::new(fobj).bytes().zip(output.concatenated)
    {
        if fs_byte.map_err(|e| StatusError::from(e))? != hg_byte {
            return Ok(true);
        }
    }
    Ok(false)
}

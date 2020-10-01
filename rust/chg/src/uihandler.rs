// Copyright 2018 Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use async_trait::async_trait;
use std::io;
use std::os::unix::io::AsRawFd;
use std::os::unix::process::ExitStatusExt;
use std::process::Stdio;
use tokio;
use tokio::process::{Child, ChildStdin, Command};

use crate::message::CommandSpec;
use crate::procutil;

/// Callback to process shell command requests received from server.
#[async_trait]
pub trait SystemHandler {
    type PagerStdin: AsRawFd;

    /// Handles pager command request.
    ///
    /// Returns the pipe to be attached to the server if the pager is spawned.
    async fn spawn_pager(
        &mut self,
        spec: &CommandSpec,
    ) -> io::Result<Self::PagerStdin>;

    /// Handles system command request.
    ///
    /// Returns command exit code (positive) or signal number (negative).
    async fn run_system(&mut self, spec: &CommandSpec) -> io::Result<i32>;
}

/// Default cHg implementation to process requests received from server.
pub struct ChgUiHandler {
    pager: Option<Child>,
}

impl ChgUiHandler {
    pub fn new() -> ChgUiHandler {
        ChgUiHandler { pager: None }
    }

    /// Waits until the pager process exits.
    pub async fn wait_pager(&mut self) -> io::Result<()> {
        if let Some(p) = self.pager.take() {
            p.await?;
        }
        Ok(())
    }
}

#[async_trait]
impl SystemHandler for ChgUiHandler {
    type PagerStdin = ChildStdin;

    async fn spawn_pager(
        &mut self,
        spec: &CommandSpec,
    ) -> io::Result<Self::PagerStdin> {
        let mut pager =
            new_shell_command(&spec).stdin(Stdio::piped()).spawn()?;
        let pin = pager.stdin.take().unwrap();
        procutil::set_blocking_fd(pin.as_raw_fd())?;
        // TODO: if pager exits, notify the server with SIGPIPE immediately.
        // otherwise the server won't get SIGPIPE if it does not write
        // anything. (issue5278)
        // kill(peerpid, SIGPIPE);
        self.pager = Some(pager);
        Ok(pin)
    }

    async fn run_system(&mut self, spec: &CommandSpec) -> io::Result<i32> {
        let status = new_shell_command(&spec).spawn()?.await?;
        let code = status
            .code()
            .or_else(|| status.signal().map(|n| -n))
            .expect("either exit code or signal should be set");
        Ok(code)
    }
}

fn new_shell_command(spec: &CommandSpec) -> Command {
    let mut builder = Command::new("/bin/sh");
    builder
        .arg("-c")
        .arg(&spec.command)
        .current_dir(&spec.current_dir)
        .env_clear()
        .envs(spec.envs.iter().cloned());
    builder
}

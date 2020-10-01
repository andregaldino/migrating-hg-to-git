// Copyright 2018 Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! cHg extensions to command server client.

use bytes::{BufMut, BytesMut};
use std::ffi::OsStr;
use std::io;
use std::mem;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::io::AsRawFd;
use std::path::Path;
use tokio_hglib::UnixClient;

use crate::attachio;
use crate::message::{self, Instruction, ServerSpec};
use crate::runcommand;
use crate::uihandler::SystemHandler;

/// Command-server client that also supports cHg extensions.
pub struct ChgClient {
    client: UnixClient,
}

impl ChgClient {
    /// Connects to a command server listening at the specified socket path.
    pub async fn connect(path: impl AsRef<Path>) -> io::Result<Self> {
        let client = UnixClient::connect(path).await?;
        Ok(ChgClient { client })
    }

    /// Server capabilities, encoding, etc.
    pub fn server_spec(&self) -> &ServerSpec {
        self.client.server_spec()
    }

    /// Attaches the client file descriptors to the server.
    pub async fn attach_io(
        &mut self,
        stdin: &impl AsRawFd,
        stdout: &impl AsRawFd,
        stderr: &impl AsRawFd,
    ) -> io::Result<()> {
        attachio::attach_io(
            self.client.borrow_protocol_mut(),
            stdin,
            stdout,
            stderr,
        )
        .await
    }

    /// Changes the working directory of the server.
    pub async fn set_current_dir(
        &mut self,
        dir: impl AsRef<Path>,
    ) -> io::Result<()> {
        let dir_bytes = dir.as_ref().as_os_str().as_bytes().to_owned();
        self.client
            .borrow_protocol_mut()
            .send_command_with_args("chdir", dir_bytes)
            .await
    }

    /// Updates the environment variables of the server.
    pub async fn set_env_vars_os(
        &mut self,
        vars: impl IntoIterator<Item = (impl AsRef<OsStr>, impl AsRef<OsStr>)>,
    ) -> io::Result<()> {
        self.client
            .borrow_protocol_mut()
            .send_command_with_args("setenv", message::pack_env_vars_os(vars))
            .await
    }

    /// Changes the process title of the server.
    pub async fn set_process_name(
        &mut self,
        name: impl AsRef<OsStr>,
    ) -> io::Result<()> {
        let name_bytes = name.as_ref().as_bytes().to_owned();
        self.client
            .borrow_protocol_mut()
            .send_command_with_args("setprocname", name_bytes)
            .await
    }

    /// Changes the umask of the server process.
    pub async fn set_umask(&mut self, mask: u32) -> io::Result<()> {
        let mut mask_bytes = BytesMut::with_capacity(mem::size_of_val(&mask));
        mask_bytes.put_u32(mask);
        self.client
            .borrow_protocol_mut()
            .send_command_with_args("setumask2", mask_bytes)
            .await
    }

    /// Runs the specified Mercurial command with cHg extension.
    pub async fn run_command_chg(
        &mut self,
        handler: &mut impl SystemHandler,
        args: impl IntoIterator<Item = impl AsRef<OsStr>>,
    ) -> io::Result<i32> {
        runcommand::run_command(
            self.client.borrow_protocol_mut(),
            handler,
            message::pack_args_os(args),
        )
        .await
    }

    /// Validates if the server can run Mercurial commands with the expected
    /// configuration.
    ///
    /// The `args` should contain early command arguments such as `--config`
    /// and `-R`.
    ///
    /// Client-side environment must be sent prior to this request, by
    /// `set_current_dir()` and `set_env_vars_os()`.
    pub async fn validate(
        &mut self,
        args: impl IntoIterator<Item = impl AsRef<OsStr>>,
    ) -> io::Result<Vec<Instruction>> {
        let data = self
            .client
            .borrow_protocol_mut()
            .query_with_args("validate", message::pack_args_os(args))
            .await?;
        message::parse_instructions(data)
    }
}

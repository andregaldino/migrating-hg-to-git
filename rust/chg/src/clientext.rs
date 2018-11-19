// Copyright 2018 Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! cHg extensions to command server client.

use bytes::{BufMut, Bytes, BytesMut};
use std::ffi::OsStr;
use std::io;
use std::mem;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::io::AsRawFd;
use std::path::Path;
use tokio_hglib::protocol::{OneShotQuery, OneShotRequest};
use tokio_hglib::{Client, Connection};

use super::attachio::AttachIo;
use super::message::{self, Instruction};
use super::runcommand::ChgRunCommand;
use super::uihandler::SystemHandler;

pub trait ChgClientExt<C>
where
    C: Connection + AsRawFd,
{
    /// Attaches the client file descriptors to the server.
    fn attach_io<I, O, E>(self, stdin: I, stdout: O, stderr: E) -> AttachIo<C, I, O, E>
    where
        I: AsRawFd,
        O: AsRawFd,
        E: AsRawFd;

    /// Changes the working directory of the server.
    fn set_current_dir<P>(self, dir: P) -> OneShotRequest<C>
    where
        P: AsRef<Path>;

    /// Updates the environment variables of the server.
    fn set_env_vars_os<I, P>(self, vars: I) -> OneShotRequest<C>
    where
        I: IntoIterator<Item = (P, P)>,
        P: AsRef<OsStr>;

    /// Changes the process title of the server.
    fn set_process_name<P>(self, name: P) -> OneShotRequest<C>
    where
        P: AsRef<OsStr>;

    /// Changes the umask of the server process.
    fn set_umask(self, mask: u32) -> OneShotRequest<C>;

    /// Runs the specified Mercurial command with cHg extension.
    fn run_command_chg<I, P, H>(self, handler: H, args: I) -> ChgRunCommand<C, H>
    where
        I: IntoIterator<Item = P>,
        P: AsRef<OsStr>,
        H: SystemHandler;

    /// Validates if the server can run Mercurial commands with the expected
    /// configuration.
    ///
    /// The `args` should contain early command arguments such as `--config`
    /// and `-R`.
    ///
    /// Client-side environment must be sent prior to this request, by
    /// `set_current_dir()` and `set_env_vars_os()`.
    fn validate<I, P>(self, args: I) -> OneShotQuery<C, fn(Bytes) -> io::Result<Vec<Instruction>>>
    where
        I: IntoIterator<Item = P>,
        P: AsRef<OsStr>;
}

impl<C> ChgClientExt<C> for Client<C>
where
    C: Connection + AsRawFd,
{
    fn attach_io<I, O, E>(self, stdin: I, stdout: O, stderr: E) -> AttachIo<C, I, O, E>
    where
        I: AsRawFd,
        O: AsRawFd,
        E: AsRawFd,
    {
        AttachIo::with_client(self, stdin, stdout, Some(stderr))
    }

    fn set_current_dir<P>(self, dir: P) -> OneShotRequest<C>
    where
        P: AsRef<Path>,
    {
        OneShotRequest::start_with_args(self, b"chdir", dir.as_ref().as_os_str().as_bytes())
    }

    fn set_env_vars_os<I, P>(self, vars: I) -> OneShotRequest<C>
    where
        I: IntoIterator<Item = (P, P)>,
        P: AsRef<OsStr>,
    {
        OneShotRequest::start_with_args(self, b"setenv", message::pack_env_vars_os(vars))
    }

    fn set_process_name<P>(self, name: P) -> OneShotRequest<C>
    where
        P: AsRef<OsStr>,
    {
        OneShotRequest::start_with_args(self, b"setprocname", name.as_ref().as_bytes())
    }

    fn set_umask(self, mask: u32) -> OneShotRequest<C> {
        let mut args = BytesMut::with_capacity(mem::size_of_val(&mask));
        args.put_u32_be(mask);
        OneShotRequest::start_with_args(self, b"setumask2", args)
    }

    fn run_command_chg<I, P, H>(self, handler: H, args: I) -> ChgRunCommand<C, H>
    where
        I: IntoIterator<Item = P>,
        P: AsRef<OsStr>,
        H: SystemHandler,
    {
        ChgRunCommand::with_client(self, handler, message::pack_args_os(args))
    }

    fn validate<I, P>(self, args: I) -> OneShotQuery<C, fn(Bytes) -> io::Result<Vec<Instruction>>>
    where
        I: IntoIterator<Item = P>,
        P: AsRef<OsStr>,
    {
        OneShotQuery::start_with_args(
            self,
            b"validate",
            message::pack_args_os(args),
            message::parse_instructions,
        )
    }
}

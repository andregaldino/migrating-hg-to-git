// Copyright 2011, 2018 Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Utility for locating command-server process.

use futures::future::{self, Either, Loop};
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs::{self, DirBuilder};
use std::io;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::{Path, PathBuf};
use std::process::{self, Command};
use std::time::Duration;
use tokio::prelude::*;
use tokio_hglib::UnixClient;
use tokio_process::{Child, CommandExt};
use tokio_timer;

use super::clientext::ChgClientExt;
use super::message::ServerSpec;
use super::procutil;

const REQUIRED_SERVER_CAPABILITIES: &[&str] = &["attachio", "chdir", "runcommand"];

/// Helper to connect to and spawn a server process.
#[derive(Clone, Debug)]
pub struct Locator {
    hg_command: OsString,
    current_dir: PathBuf,
    env_vars: Vec<(OsString, OsString)>,
    process_id: u32,
    base_sock_path: PathBuf,
    timeout: Duration,
}

impl Locator {
    /// Creates locator capturing the current process environment.
    ///
    /// If no `$CHGSOCKNAME` is specified, the socket directory will be
    /// created as necessary.
    pub fn prepare_from_env() -> io::Result<Locator> {
        Ok(Locator {
            hg_command: default_hg_command(),
            current_dir: env::current_dir()?,
            env_vars: env::vars_os().collect(),
            process_id: process::id(),
            base_sock_path: prepare_server_socket_path()?,
            timeout: default_timeout(),
        })
    }

    /// Temporary socket path for this client process.
    fn temp_sock_path(&self) -> PathBuf {
        let src = self.base_sock_path.as_os_str().as_bytes();
        let mut buf = Vec::with_capacity(src.len() + 6); // "{src}.{pid}".len()
        buf.extend_from_slice(src);
        buf.extend_from_slice(format!(".{}", self.process_id).as_bytes());
        OsString::from_vec(buf).into()
    }

    /// Connects to the server.
    ///
    /// The server process will be spawned if not running.
    pub fn connect(self) -> impl Future<Item = (Self, UnixClient), Error = io::Error> {
        self.try_connect()
    }

    /// Tries to connect to the existing server, or spawns new if not running.
    fn try_connect(self) -> impl Future<Item = (Self, UnixClient), Error = io::Error> {
        debug!("try connect to {}", self.base_sock_path.display());
        UnixClient::connect(self.base_sock_path.clone())
            .then(|res| match res {
                Ok(client) => Either::A(future::ok((self, client))),
                Err(_) => Either::B(self.spawn_connect()),
            })
            .and_then(|(loc, client)| {
                check_server_capabilities(client.server_spec())?;
                Ok((loc, client))
            })
            .and_then(|(loc, client)| {
                client
                    .set_current_dir(&loc.current_dir)
                    .map(|client| (loc, client))
            })
    }

    /// Spawns new server process and connects to it.
    ///
    /// The server will be spawned at the current working directory, then
    /// chdir to "/", so that the server will load configs from the target
    /// repository.
    fn spawn_connect(self) -> impl Future<Item = (Self, UnixClient), Error = io::Error> {
        let sock_path = self.temp_sock_path();
        debug!("start cmdserver at {}", sock_path.display());
        Command::new(&self.hg_command)
            .arg("serve")
            .arg("--cmdserver")
            .arg("chgunix")
            .arg("--address")
            .arg(&sock_path)
            .arg("--daemon-postexec")
            .arg("chdir:/")
            .current_dir(&self.current_dir)
            .env_clear()
            .envs(self.env_vars.iter().cloned())
            .env("CHGINTERNALMARK", "")
            .spawn_async()
            .into_future()
            .and_then(|server| self.connect_spawned(server, sock_path))
            .and_then(|(loc, client, sock_path)| {
                debug!(
                    "rename {} to {}",
                    sock_path.display(),
                    loc.base_sock_path.display()
                );
                fs::rename(&sock_path, &loc.base_sock_path)?;
                Ok((loc, client))
            })
    }

    /// Tries to connect to the just spawned server repeatedly until timeout
    /// exceeded.
    fn connect_spawned(
        self,
        server: Child,
        sock_path: PathBuf,
    ) -> impl Future<Item = (Self, UnixClient, PathBuf), Error = io::Error> {
        debug!("try connect to {} repeatedly", sock_path.display());
        let connect = future::loop_fn(sock_path, |sock_path| {
            UnixClient::connect(sock_path.clone()).then(|res| {
                match res {
                    Ok(client) => Either::A(future::ok(Loop::Break((client, sock_path)))),
                    Err(_) => {
                        // try again with slight delay
                        let fut = tokio_timer::sleep(Duration::from_millis(10))
                            .map(|()| Loop::Continue(sock_path))
                            .map_err(|err| io::Error::new(io::ErrorKind::Other, err));
                        Either::B(fut)
                    }
                }
            })
        });

        // waits for either connection established or server failed to start
        connect
            .select2(server)
            .map_err(|res| res.split().0)
            .timeout(self.timeout)
            .map_err(|err| {
                err.into_inner().unwrap_or_else(|| {
                    io::Error::new(
                        io::ErrorKind::TimedOut,
                        "timed out while connecting to server",
                    )
                })
            })
            .and_then(|res| {
                match res {
                    Either::A(((client, sock_path), server)) => {
                        server.forget(); // continue to run in background
                        Ok((self, client, sock_path))
                    }
                    Either::B((st, _)) => Err(io::Error::new(
                        io::ErrorKind::Other,
                        format!("server exited too early: {}", st),
                    )),
                }
            })
    }
}

/// Determines the server socket to connect to.
///
/// If no `$CHGSOCKNAME` is specified, the socket directory will be created
/// as necessary.
fn prepare_server_socket_path() -> io::Result<PathBuf> {
    if let Some(s) = env::var_os("CHGSOCKNAME") {
        Ok(PathBuf::from(s))
    } else {
        let mut path = default_server_socket_dir();
        create_secure_dir(&path)?;
        path.push("server");
        Ok(path)
    }
}

/// Determines the default server socket path as follows.
///
/// 1. `$XDG_RUNTIME_DIR/chg`
/// 2. `$TMPDIR/chg$UID`
/// 3. `/tmp/chg$UID`
pub fn default_server_socket_dir() -> PathBuf {
    // XDG_RUNTIME_DIR should be ignored if it has an insufficient permission.
    // https://standards.freedesktop.org/basedir-spec/basedir-spec-latest.html
    if let Some(Ok(s)) = env::var_os("XDG_RUNTIME_DIR").map(check_secure_dir) {
        let mut path = PathBuf::from(s);
        path.push("chg");
        path
    } else {
        let mut path = env::temp_dir();
        path.push(format!("chg{}", procutil::get_effective_uid()));
        path
    }
}

/// Determines the default hg command.
pub fn default_hg_command() -> OsString {
    // TODO: maybe allow embedding the path at compile time (or load from hgrc)
    env::var_os("CHGHG")
        .or(env::var_os("HG"))
        .unwrap_or(OsStr::new("hg").to_owned())
}

fn default_timeout() -> Duration {
    let secs = env::var("CHGTIMEOUT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(60);
    Duration::from_secs(secs)
}

/// Creates a directory which the other users cannot access to.
///
/// If the directory already exists, tests its permission.
fn create_secure_dir<P>(path: P) -> io::Result<()>
where
    P: AsRef<Path>,
{
    DirBuilder::new()
        .mode(0o700)
        .create(path.as_ref())
        .or_else(|err| {
            if err.kind() == io::ErrorKind::AlreadyExists {
                check_secure_dir(path).map(|_| ())
            } else {
                Err(err)
            }
        })
}

fn check_secure_dir<P>(path: P) -> io::Result<P>
where
    P: AsRef<Path>,
{
    let a = fs::symlink_metadata(path.as_ref())?;
    if a.is_dir() && a.uid() == procutil::get_effective_uid() && (a.mode() & 0o777) == 0o700 {
        Ok(path)
    } else {
        Err(io::Error::new(io::ErrorKind::Other, "insecure directory"))
    }
}

fn check_server_capabilities(spec: &ServerSpec) -> io::Result<()> {
    let unsupported: Vec<_> = REQUIRED_SERVER_CAPABILITIES
        .iter()
        .cloned()
        .filter(|&s| !spec.capabilities.contains(s))
        .collect();
    if unsupported.is_empty() {
        Ok(())
    } else {
        let msg = format!(
            "insufficient server capabilities: {}",
            unsupported.join(", ")
        );
        Err(io::Error::new(io::ErrorKind::Other, msg))
    }
}

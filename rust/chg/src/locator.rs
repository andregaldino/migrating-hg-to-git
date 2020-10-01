// Copyright 2011, 2018 Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Utility for locating command-server process.

use log::debug;
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs::{self, DirBuilder};
use std::io;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::{Path, PathBuf};
use std::process::{self, Child, Command};
use std::time::{Duration, Instant};
use tokio::time;

use crate::clientext::ChgClient;
use crate::message::{Instruction, ServerSpec};
use crate::procutil;

const REQUIRED_SERVER_CAPABILITIES: &[&str] = &[
    "attachio",
    "chdir",
    "runcommand",
    "setenv",
    "setumask2",
    "validate",
];

/// Helper to connect to and spawn a server process.
#[derive(Clone, Debug)]
pub struct Locator {
    hg_command: OsString,
    hg_early_args: Vec<OsString>,
    current_dir: PathBuf,
    env_vars: Vec<(OsString, OsString)>,
    process_id: u32,
    base_sock_path: PathBuf,
    redirect_sock_path: Option<PathBuf>,
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
            hg_early_args: Vec::new(),
            current_dir: env::current_dir()?,
            env_vars: env::vars_os().collect(),
            process_id: process::id(),
            base_sock_path: prepare_server_socket_path()?,
            redirect_sock_path: None,
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

    /// Specifies the arguments to be passed to the server at start.
    pub fn set_early_args(
        &mut self,
        args: impl IntoIterator<Item = impl AsRef<OsStr>>,
    ) {
        self.hg_early_args =
            args.into_iter().map(|a| a.as_ref().to_owned()).collect();
    }

    /// Connects to the server.
    ///
    /// The server process will be spawned if not running.
    pub async fn connect(&mut self) -> io::Result<ChgClient> {
        for _cnt in 0..10 {
            let mut client = self.try_connect().await?;
            let instructions = client.validate(&self.hg_early_args).await?;
            let reconnect = self.run_instructions(&instructions)?;
            if !reconnect {
                return Ok(client);
            }
        }

        let msg = format!(
            concat!(
                "too many redirections.\n",
                "Please make sure {:?} is not a wrapper which ",
                "changes sensitive environment variables ",
                "before executing hg. If you have to use a ",
                "wrapper, wrap chg instead of hg.",
            ),
            self.hg_command
        );
        Err(io::Error::new(io::ErrorKind::Other, msg))
    }

    /// Runs instructions received from the server.
    ///
    /// Returns true if the client should try connecting to the other server.
    fn run_instructions(
        &mut self,
        instructions: &[Instruction],
    ) -> io::Result<bool> {
        let mut reconnect = false;
        for inst in instructions {
            debug!("instruction: {:?}", inst);
            match inst {
                Instruction::Exit(_) => {
                    // Just returns the current connection to run the
                    // unparsable command and report the error
                    return Ok(false);
                }
                Instruction::Reconnect => {
                    reconnect = true;
                }
                Instruction::Redirect(path) => {
                    if path.parent() != self.base_sock_path.parent() {
                        let msg = format!(
                            "insecure redirect instruction from server: {}",
                            path.display()
                        );
                        return Err(io::Error::new(
                            io::ErrorKind::InvalidData,
                            msg,
                        ));
                    }
                    self.redirect_sock_path = Some(path.to_owned());
                    reconnect = true;
                }
                Instruction::Unlink(path) => {
                    if path.parent() != self.base_sock_path.parent() {
                        let msg = format!(
                            "insecure unlink instruction from server: {}",
                            path.display()
                        );
                        return Err(io::Error::new(
                            io::ErrorKind::InvalidData,
                            msg,
                        ));
                    }
                    fs::remove_file(path).unwrap_or(()); // may race
                }
            }
        }

        Ok(reconnect)
    }

    /// Tries to connect to the existing server, or spawns new if not running.
    async fn try_connect(&mut self) -> io::Result<ChgClient> {
        let sock_path = self
            .redirect_sock_path
            .as_ref()
            .unwrap_or(&self.base_sock_path)
            .clone();
        debug!("try connect to {}", sock_path.display());
        let mut client = match ChgClient::connect(sock_path).await {
            Ok(client) => client,
            Err(_) => {
                // Prevent us from being re-connected to the outdated
                // master server: We were told by the server to redirect
                // to redirect_sock_path, which didn't work. We do not
                // want to connect to the same master server again
                // because it would probably tell us the same thing.
                if self.redirect_sock_path.is_some() {
                    fs::remove_file(&self.base_sock_path).unwrap_or(());
                    // may race
                }
                self.spawn_connect().await?
            }
        };
        check_server_capabilities(client.server_spec())?;
        // It's purely optional, and the server might not support this command.
        if client.server_spec().capabilities.contains("setprocname") {
            client
                .set_process_name(format!("chg[worker/{}]", self.process_id))
                .await?;
        }
        client.set_current_dir(&self.current_dir).await?;
        client
            .set_env_vars_os(self.env_vars.iter().cloned())
            .await?;
        Ok(client)
    }

    /// Spawns new server process and connects to it.
    ///
    /// The server will be spawned at the current working directory, then
    /// chdir to "/", so that the server will load configs from the target
    /// repository.
    async fn spawn_connect(&mut self) -> io::Result<ChgClient> {
        let sock_path = self.temp_sock_path();
        debug!("start cmdserver at {}", sock_path.display());
        let server = Command::new(&self.hg_command)
            .arg("serve")
            .arg("--cmdserver")
            .arg("chgunix")
            .arg("--address")
            .arg(&sock_path)
            .arg("--daemon-postexec")
            .arg("chdir:/")
            .args(&self.hg_early_args)
            .current_dir(&self.current_dir)
            .env_clear()
            .envs(self.env_vars.iter().cloned())
            .env("CHGINTERNALMARK", "")
            .spawn()?;
        let client = self.connect_spawned(server, &sock_path).await?;
        debug!(
            "rename {} to {}",
            sock_path.display(),
            self.base_sock_path.display()
        );
        fs::rename(&sock_path, &self.base_sock_path)?;
        Ok(client)
    }

    /// Tries to connect to the just spawned server repeatedly until timeout
    /// exceeded.
    async fn connect_spawned(
        &mut self,
        mut server: Child,
        sock_path: &Path,
    ) -> io::Result<ChgClient> {
        debug!("try connect to {} repeatedly", sock_path.display());
        // waits for either connection established or server failed to start
        let start_time = Instant::now();
        while start_time.elapsed() < self.timeout {
            if let Ok(client) = ChgClient::connect(&sock_path).await {
                // server handle is dropped here, but the detached process
                // will continue running in background
                return Ok(client);
            }

            if let Some(st) = server.try_wait()? {
                return Err(io::Error::new(
                    io::ErrorKind::Other,
                    format!("server exited too early: {}", st),
                ));
            }

            // try again with slight delay
            time::delay_for(Duration::from_millis(10)).await;
        }

        Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "timed out while connecting to server",
        ))
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
fn create_secure_dir(path: impl AsRef<Path>) -> io::Result<()> {
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
    if a.is_dir()
        && a.uid() == procutil::get_effective_uid()
        && (a.mode() & 0o777) == 0o700
    {
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

/// Collects arguments which need to be passed to the server at start.
pub fn collect_early_args(
    args: impl IntoIterator<Item = impl AsRef<OsStr>>,
) -> Vec<OsString> {
    let mut args_iter = args.into_iter();
    let mut early_args = Vec::new();
    while let Some(arg) = args_iter.next() {
        let argb = arg.as_ref().as_bytes();
        if argb == b"--" {
            break;
        } else if argb.starts_with(b"--") {
            let mut split = argb[2..].splitn(2, |&c| c == b'=');
            match split.next().unwrap() {
                b"traceback" => {
                    if split.next().is_none() {
                        early_args.push(arg.as_ref().to_owned());
                    }
                }
                b"config" | b"cwd" | b"repo" | b"repository" => {
                    if split.next().is_some() {
                        // --<flag>=<val>
                        early_args.push(arg.as_ref().to_owned());
                    } else {
                        // --<flag> <val>
                        args_iter.next().map(|val| {
                            early_args.push(arg.as_ref().to_owned());
                            early_args.push(val.as_ref().to_owned());
                        });
                    }
                }
                _ => {}
            }
        } else if argb.starts_with(b"-R") {
            if argb.len() > 2 {
                // -R<val>
                early_args.push(arg.as_ref().to_owned());
            } else {
                // -R <val>
                args_iter.next().map(|val| {
                    early_args.push(arg.as_ref().to_owned());
                    early_args.push(val.as_ref().to_owned());
                });
            }
        }
    }

    early_args
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn collect_early_args_some() {
        assert!(collect_early_args(&[] as &[&OsStr]).is_empty());
        assert!(collect_early_args(&["log"]).is_empty());
        assert_eq!(
            collect_early_args(&["log", "-Ra", "foo"]),
            os_string_vec_from(&[b"-Ra"])
        );
        assert_eq!(
            collect_early_args(&["log", "-R", "repo", "", "--traceback", "a"]),
            os_string_vec_from(&[b"-R", b"repo", b"--traceback"])
        );
        assert_eq!(
            collect_early_args(&["log", "--config", "diff.git=1", "-q"]),
            os_string_vec_from(&[b"--config", b"diff.git=1"])
        );
        assert_eq!(
            collect_early_args(&["--cwd=..", "--repository", "r", "log"]),
            os_string_vec_from(&[b"--cwd=..", b"--repository", b"r"])
        );
        assert_eq!(
            collect_early_args(&["log", "--repo=r", "--repos", "a"]),
            os_string_vec_from(&[b"--repo=r"])
        );
    }

    #[test]
    fn collect_early_args_orphaned() {
        assert!(collect_early_args(&["log", "-R"]).is_empty());
        assert!(collect_early_args(&["log", "--config"]).is_empty());
    }

    #[test]
    fn collect_early_args_unwanted_value() {
        assert!(collect_early_args(&["log", "--traceback="]).is_empty());
    }

    fn os_string_vec_from(v: &[&[u8]]) -> Vec<OsString> {
        v.iter().map(|s| OsStr::from_bytes(s).to_owned()).collect()
    }
}

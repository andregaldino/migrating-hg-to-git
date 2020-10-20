// Copyright 2018 Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Utility for parsing and building command-server messages.

use bytes::{BufMut, Bytes, BytesMut};
use std::error;
use std::ffi::{OsStr, OsString};
use std::io;
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;

pub use tokio_hglib::message::*; // re-exports

/// Shell command type requested by the server.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommandType {
    /// Pager should be spawned.
    Pager,
    /// Shell command should be executed to send back the result code.
    System,
}

/// Shell command requested by the server.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CommandSpec {
    pub command: OsString,
    pub current_dir: OsString,
    pub envs: Vec<(OsString, OsString)>,
}

/// Parses "S" channel request into command type and spec.
pub fn parse_command_spec(
    data: Bytes,
) -> io::Result<(CommandType, CommandSpec)> {
    let mut split = data.split(|&c| c == b'\0');
    let ctype = parse_command_type(
        split.next().ok_or(new_parse_error("missing type"))?,
    )?;
    let command = split.next().ok_or(new_parse_error("missing command"))?;
    let current_dir =
        split.next().ok_or(new_parse_error("missing current dir"))?;

    let mut envs = Vec::new();
    for l in split {
        let mut s = l.splitn(2, |&c| c == b'=');
        let k = s.next().unwrap();
        let v = s.next().ok_or(new_parse_error("malformed env"))?;
        envs.push((
            OsStr::from_bytes(k).to_owned(),
            OsStr::from_bytes(v).to_owned(),
        ));
    }

    let spec = CommandSpec {
        command: OsStr::from_bytes(command).to_owned(),
        current_dir: OsStr::from_bytes(current_dir).to_owned(),
        envs: envs,
    };
    Ok((ctype, spec))
}

fn parse_command_type(value: &[u8]) -> io::Result<CommandType> {
    match value {
        b"pager" => Ok(CommandType::Pager),
        b"system" => Ok(CommandType::System),
        _ => Err(new_parse_error(format!(
            "unknown command type: {}",
            decode_latin1(value)
        ))),
    }
}

/// Client-side instruction requested by the server.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Instruction {
    Exit(i32),
    Reconnect,
    Redirect(PathBuf),
    Unlink(PathBuf),
}

/// Parses validation result into instructions.
pub fn parse_instructions(data: Bytes) -> io::Result<Vec<Instruction>> {
    let mut instructions = Vec::new();
    for l in data.split(|&c| c == b'\0') {
        if l.is_empty() {
            continue;
        }
        let mut s = l.splitn(2, |&c| c == b' ');
        let inst = match (s.next().unwrap(), s.next()) {
            (b"exit", Some(arg)) => decode_latin1(arg)
                .parse()
                .map(Instruction::Exit)
                .map_err(|_| {
                    new_parse_error(format!("invalid exit code: {:?}", arg))
                })?,
            (b"reconnect", None) => Instruction::Reconnect,
            (b"redirect", Some(arg)) => {
                Instruction::Redirect(OsStr::from_bytes(arg).to_owned().into())
            }
            (b"unlink", Some(arg)) => {
                Instruction::Unlink(OsStr::from_bytes(arg).to_owned().into())
            }
            _ => {
                return Err(new_parse_error(format!(
                    "unknown command: {:?}",
                    l
                )));
            }
        };
        instructions.push(inst);
    }
    Ok(instructions)
}

// allocate large buffer as environment variables can be quite long
const INITIAL_PACKED_ENV_VARS_CAPACITY: usize = 4096;

/// Packs environment variables of platform encoding into bytes.
///
/// # Panics
///
/// Panics if key or value contains `\0` character, or key contains '='
/// character.
pub fn pack_env_vars_os(
    vars: impl IntoIterator<Item = (impl AsRef<OsStr>, impl AsRef<OsStr>)>,
) -> Bytes {
    let mut vars_iter = vars.into_iter();
    if let Some((k, v)) = vars_iter.next() {
        let mut dst =
            BytesMut::with_capacity(INITIAL_PACKED_ENV_VARS_CAPACITY);
        pack_env_into(&mut dst, k.as_ref(), v.as_ref());
        for (k, v) in vars_iter {
            dst.reserve(1);
            dst.put_u8(b'\0');
            pack_env_into(&mut dst, k.as_ref(), v.as_ref());
        }
        dst.freeze()
    } else {
        Bytes::new()
    }
}

fn pack_env_into(dst: &mut BytesMut, k: &OsStr, v: &OsStr) {
    assert!(!k.as_bytes().contains(&0), "key shouldn't contain NUL");
    assert!(!k.as_bytes().contains(&b'='), "key shouldn't contain '='");
    assert!(!v.as_bytes().contains(&0), "value shouldn't contain NUL");
    dst.reserve(k.as_bytes().len() + 1 + v.as_bytes().len());
    dst.put_slice(k.as_bytes());
    dst.put_u8(b'=');
    dst.put_slice(v.as_bytes());
}

fn decode_latin1(s: impl AsRef<[u8]>) -> String {
    s.as_ref().iter().map(|&c| c as char).collect()
}

fn new_parse_error(
    error: impl Into<Box<dyn error::Error + Send + Sync>>,
) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::ffi::OsStringExt;
    use std::panic;

    #[test]
    fn parse_command_spec_good() {
        let src = [
            b"pager".as_ref(),
            b"less -FRX".as_ref(),
            b"/tmp".as_ref(),
            b"LANG=C".as_ref(),
            b"HGPLAIN=".as_ref(),
        ]
        .join(&0);
        let spec = CommandSpec {
            command: os_string_from(b"less -FRX"),
            current_dir: os_string_from(b"/tmp"),
            envs: vec![
                (os_string_from(b"LANG"), os_string_from(b"C")),
                (os_string_from(b"HGPLAIN"), os_string_from(b"")),
            ],
        };
        assert_eq!(
            parse_command_spec(Bytes::from(src)).unwrap(),
            (CommandType::Pager, spec)
        );
    }

    #[test]
    fn parse_command_spec_too_short() {
        assert!(parse_command_spec(Bytes::from_static(b"")).is_err());
        assert!(parse_command_spec(Bytes::from_static(b"pager")).is_err());
        assert!(
            parse_command_spec(Bytes::from_static(b"pager\0less")).is_err()
        );
    }

    #[test]
    fn parse_command_spec_malformed_env() {
        assert!(parse_command_spec(Bytes::from_static(
            b"pager\0less\0/tmp\0HOME"
        ))
        .is_err());
    }

    #[test]
    fn parse_command_spec_unknown_type() {
        assert!(
            parse_command_spec(Bytes::from_static(b"paper\0less")).is_err()
        );
    }

    #[test]
    fn parse_instructions_good() {
        let src = [
            b"exit 123".as_ref(),
            b"reconnect".as_ref(),
            b"redirect /whatever".as_ref(),
            b"unlink /someother".as_ref(),
        ]
        .join(&0);
        let insts = vec![
            Instruction::Exit(123),
            Instruction::Reconnect,
            Instruction::Redirect(path_buf_from(b"/whatever")),
            Instruction::Unlink(path_buf_from(b"/someother")),
        ];
        assert_eq!(parse_instructions(Bytes::from(src)).unwrap(), insts);
    }

    #[test]
    fn parse_instructions_empty() {
        assert_eq!(parse_instructions(Bytes::new()).unwrap(), vec![]);
        assert_eq!(
            parse_instructions(Bytes::from_static(b"\0")).unwrap(),
            vec![]
        );
    }

    #[test]
    fn parse_instructions_malformed_exit_code() {
        assert!(parse_instructions(Bytes::from_static(b"exit foo")).is_err());
    }

    #[test]
    fn parse_instructions_missing_argument() {
        assert!(parse_instructions(Bytes::from_static(b"exit")).is_err());
        assert!(parse_instructions(Bytes::from_static(b"redirect")).is_err());
        assert!(parse_instructions(Bytes::from_static(b"unlink")).is_err());
    }

    #[test]
    fn parse_instructions_unknown_command() {
        assert!(parse_instructions(Bytes::from_static(b"quit 0")).is_err());
    }

    #[test]
    fn pack_env_vars_os_good() {
        assert_eq!(
            pack_env_vars_os(vec![] as Vec<(OsString, OsString)>),
            Bytes::new()
        );
        assert_eq!(
            pack_env_vars_os(vec![os_string_pair_from(b"FOO", b"bar")]),
            Bytes::from_static(b"FOO=bar")
        );
        assert_eq!(
            pack_env_vars_os(vec![
                os_string_pair_from(b"FOO", b""),
                os_string_pair_from(b"BAR", b"baz")
            ]),
            Bytes::from_static(b"FOO=\0BAR=baz")
        );
    }

    #[test]
    fn pack_env_vars_os_large_key() {
        let mut buf = vec![b'A'; INITIAL_PACKED_ENV_VARS_CAPACITY];
        let envs = vec![os_string_pair_from(&buf, b"")];
        buf.push(b'=');
        assert_eq!(pack_env_vars_os(envs), Bytes::from(buf));
    }

    #[test]
    fn pack_env_vars_os_large_value() {
        let mut buf = vec![b'A', b'='];
        buf.resize(INITIAL_PACKED_ENV_VARS_CAPACITY + 1, b'a');
        let envs = vec![os_string_pair_from(&buf[..1], &buf[2..])];
        assert_eq!(pack_env_vars_os(envs), Bytes::from(buf));
    }

    #[test]
    fn pack_env_vars_os_nul_eq() {
        assert!(panic::catch_unwind(|| {
            pack_env_vars_os(vec![os_string_pair_from(b"\0", b"")])
        })
        .is_err());
        assert!(panic::catch_unwind(|| {
            pack_env_vars_os(vec![os_string_pair_from(b"FOO", b"\0bar")])
        })
        .is_err());
        assert!(panic::catch_unwind(|| {
            pack_env_vars_os(vec![os_string_pair_from(b"FO=", b"bar")])
        })
        .is_err());
        assert_eq!(
            pack_env_vars_os(vec![os_string_pair_from(b"FOO", b"=ba")]),
            Bytes::from_static(b"FOO==ba")
        );
    }

    fn os_string_from(s: &[u8]) -> OsString {
        OsString::from_vec(s.to_vec())
    }

    fn os_string_pair_from(k: &[u8], v: &[u8]) -> (OsString, OsString) {
        (os_string_from(k), os_string_from(v))
    }

    fn path_buf_from(s: &[u8]) -> PathBuf {
        os_string_from(s).into()
    }
}

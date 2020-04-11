// Copyright 2018 Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Functions to send client-side fds over the command server channel.

use std::io;
use std::os::unix::io::AsRawFd;
use tokio_hglib::codec::ChannelMessage;
use tokio_hglib::{Connection, Protocol};

use crate::message;
use crate::procutil;

/// Sends client-side fds over the command server channel.
///
/// This works as follows:
/// 1. Client sends "attachio" request.
/// 2. Server sends back 1-byte input request.
/// 3. Client sends fds with 1-byte dummy payload in response.
/// 4. Server returns the number of the fds received.
///
/// The client-side fds may be dropped once duplicated to the server.
pub async fn attach_io(
    proto: &mut Protocol<impl Connection + AsRawFd>,
    stdin: &impl AsRawFd,
    stdout: &impl AsRawFd,
    stderr: &impl AsRawFd,
) -> io::Result<()> {
    proto.send_command("attachio").await?;
    loop {
        match proto.fetch_response().await? {
            ChannelMessage::Data(b'r', data) => {
                let fd_cnt = message::parse_result_code(data)?;
                if fd_cnt == 3 {
                    return Ok(());
                } else {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "unexpected attachio result",
                    ));
                }
            }
            ChannelMessage::Data(..) => {
                // just ignore data sent to uninteresting (optional) channel
            }
            ChannelMessage::InputRequest(1) => {
                // this may fail with EWOULDBLOCK in theory, but the
                // payload is quite small, and the send buffer should
                // be empty so the operation will complete immediately
                let sock_fd = proto.as_raw_fd();
                let ifd = stdin.as_raw_fd();
                let ofd = stdout.as_raw_fd();
                let efd = stderr.as_raw_fd();
                procutil::send_raw_fds(sock_fd, &[ifd, ofd, efd])?;
            }
            ChannelMessage::InputRequest(..)
            | ChannelMessage::LineRequest(..)
            | ChannelMessage::SystemRequest(..) => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "unsupported request while attaching io",
                ));
            }
        }
    }
}

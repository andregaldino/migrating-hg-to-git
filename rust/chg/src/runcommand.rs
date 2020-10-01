// Copyright 2018 Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! Functions to run Mercurial command in cHg-aware command server.

use bytes::Bytes;
use std::io;
use std::os::unix::io::AsRawFd;
use tokio_hglib::codec::ChannelMessage;
use tokio_hglib::{Connection, Protocol};

use crate::attachio;
use crate::message::{self, CommandType};
use crate::uihandler::SystemHandler;

/// Runs the given Mercurial command in cHg-aware command server, and
/// fetches the result code.
///
/// This is a subset of tokio-hglib's `run_command()` with the additional
/// SystemRequest support.
pub async fn run_command(
    proto: &mut Protocol<impl Connection + AsRawFd>,
    handler: &mut impl SystemHandler,
    packed_args: impl Into<Bytes>,
) -> io::Result<i32> {
    proto
        .send_command_with_args("runcommand", packed_args)
        .await?;
    loop {
        match proto.fetch_response().await? {
            ChannelMessage::Data(b'r', data) => {
                return message::parse_result_code(data);
            }
            ChannelMessage::Data(..) => {
                // just ignores data sent to optional channel
            }
            ChannelMessage::InputRequest(..)
            | ChannelMessage::LineRequest(..) => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "unsupported request",
                ));
            }
            ChannelMessage::SystemRequest(data) => {
                let (cmd_type, cmd_spec) = message::parse_command_spec(data)?;
                match cmd_type {
                    CommandType::Pager => {
                        // server spins new command loop while pager request is
                        // in progress, which can be terminated by "" command.
                        let pin = handler.spawn_pager(&cmd_spec).await?;
                        attachio::attach_io(proto, &io::stdin(), &pin, &pin)
                            .await?;
                        proto.send_command("").await?; // terminator
                    }
                    CommandType::System => {
                        let code = handler.run_system(&cmd_spec).await?;
                        let data = message::pack_result_code(code);
                        proto.send_data(data).await?;
                    }
                }
            }
        }
    }
}

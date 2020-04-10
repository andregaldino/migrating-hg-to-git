// Copyright 2018 Yuya Nishihara <yuya@tcha.org>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use chg::locator::{self, Locator};
use chg::procutil;
use chg::ChgUiHandler;
use std::env;
use std::io;
use std::io::Write;
use std::process;
use std::time::Instant;

struct DebugLogger {
    start: Instant,
}

impl DebugLogger {
    pub fn new() -> DebugLogger {
        DebugLogger {
            start: Instant::now(),
        }
    }
}

impl log::Log for DebugLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.target().starts_with("chg::")
    }

    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            // just make the output looks similar to chg of C
            let l = format!("{}", record.level()).to_lowercase();
            let t = self.start.elapsed();
            writeln!(
                io::stderr(),
                "chg: {}: {}.{:06} {}",
                l,
                t.as_secs(),
                t.subsec_micros(),
                record.args()
            )
            .unwrap_or(());
        }
    }

    fn flush(&self) {}
}

fn main() {
    if env::var_os("CHGDEBUG").is_some() {
        log::set_boxed_logger(Box::new(DebugLogger::new()))
            .expect("any logger should not be installed yet");
        log::set_max_level(log::LevelFilter::Debug);
    }

    // TODO: add loop detection by $CHGINTERNALMARK

    let umask = unsafe { procutil::get_umask() }; // not thread safe
    let code = run(umask).unwrap_or_else(|err| {
        writeln!(io::stderr(), "chg: abort: {}", err).unwrap_or(());
        255
    });
    process::exit(code);
}

#[tokio::main]
async fn run(umask: u32) -> io::Result<i32> {
    let mut loc = Locator::prepare_from_env()?;
    loc.set_early_args(locator::collect_early_args(env::args_os().skip(1)));
    let mut handler = ChgUiHandler::new();
    let mut client = loc.connect().await?;
    client
        .attach_io(&io::stdin(), &io::stdout(), &io::stderr())
        .await?;
    client.set_umask(umask).await?;
    let pid = client.server_spec().process_id.unwrap();
    let pgid = client.server_spec().process_group_id;
    procutil::setup_signal_handler_once(pid, pgid)?;
    let code = client
        .run_command_chg(&mut handler, env::args_os().skip(1))
        .await?;
    procutil::restore_signal_handler_once()?;
    handler.wait_pager().await?;
    Ok(code)
}

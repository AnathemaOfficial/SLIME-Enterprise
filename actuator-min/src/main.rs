#![cfg_attr(not(unix), allow(unused_imports, dead_code))]

#[cfg(not(unix))]
fn main() -> std::io::Result<()> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "actuator-min is supported only on Unix/Linux targets",
    ))
}

#[cfg(unix)]
use std::fs;
#[cfg(unix)]
use std::io::ErrorKind;
#[cfg(unix)]
use std::io::{Read, Write};
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
#[cfg(unix)]
use std::os::unix::net::UnixListener;
#[cfg(unix)]
use std::path::Path;
#[cfg(unix)]
use std::time::Duration;

#[cfg(unix)]
const SOCK_PATH: &str = "/run/slime/egress.sock";
#[cfg(unix)]
const RUN_DIR: &str = "/run/slime";
#[cfg(unix)]
const EVENT_LOG: &str = "/var/log/slime-actuator/events.log";
#[cfg(unix)]
const READ_TIMEOUT: Duration = Duration::from_secs(1);

#[cfg(unix)]
fn main() -> std::io::Result<()> {
    fs::create_dir_all(RUN_DIR)?;
    fs::set_permissions(RUN_DIR, fs::Permissions::from_mode(0o750))?;

    if Path::new(SOCK_PATH).exists() {
        fs::remove_file(SOCK_PATH)?;
    }

    let listener = UnixListener::bind(SOCK_PATH)?;
    fs::set_permissions(SOCK_PATH, fs::Permissions::from_mode(0o660))?;

    if let Some(parent) = Path::new(EVENT_LOG).parent() {
        let _ = fs::create_dir_all(parent);
        let _ = fs::set_permissions(parent, fs::Permissions::from_mode(0o750));
    }

    eprintln!("actuator-min: listening on {SOCK_PATH}");

    for stream in listener.incoming() {
        match stream {
            Ok(mut s) => {
                if let Err(e) = s.set_read_timeout(Some(READ_TIMEOUT)) {
                    eprintln!("actuator-min: set_read_timeout failed: {e}");
                    continue;
                }
                let mut buf = [0u8; 32];
                if let Err(e) = s.read_exact(&mut buf) {
                    if matches!(e.kind(), ErrorKind::TimedOut | ErrorKind::WouldBlock) {
                        eprintln!("actuator-min: read timeout; dropping connection");
                    } else {
                        eprintln!("actuator-min: read_exact failed: {e}");
                    }
                    continue;
                }

                let mut hex = String::with_capacity(64);
                for b in buf {
                    hex.push_str(&format!("{:02x}", b));
                }

                let line = format!("{hex}\n");
                eprint!("actuator-min event: {}", line);

                if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(EVENT_LOG) {
                    let _ = f.write_all(line.as_bytes());
                }
            }
            Err(e) => {
                eprintln!("actuator-min: accept error: {e}");
                return Err(e);
            }
        }
    }

    Ok(())
}

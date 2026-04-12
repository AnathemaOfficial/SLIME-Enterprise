#![cfg_attr(not(unix), allow(dead_code, unused_imports))]

use std::collections::HashSet;
use std::fmt::Write as _;
use std::fs::{self, File, OpenOptions};
use std::io::{self, ErrorKind, Read, Seek, SeekFrom, Write};
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
#[cfg(unix)]
use std::os::unix::net::UnixListener;
use std::path::{Path, PathBuf};
#[cfg(unix)]
use std::time::Duration;

const SOCK_PATH: &str = "/run/slime/egress.sock";
const RUN_DIR: &str = "/run/slime";
const EVENT_LOG: &str = "/var/log/slime-actuator/events.log";
const REPLAY_JOURNAL: &str = "/var/log/slime-actuator/replay-journal.bin";
const EVENT_LOG_PREFIX: &str = "FRAME_HEX=";

#[cfg(unix)]
const READ_TIMEOUT: Duration = Duration::from_secs(1);

#[cfg(not(unix))]
fn main() -> std::io::Result<()> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "actuator-min is supported only on Unix/Linux targets",
    ))
}

#[cfg(unix)]
fn main() -> std::io::Result<()> {
    ensure_dir(Path::new(RUN_DIR), 0o750)?;

    if Path::new(SOCK_PATH).exists() {
        fs::remove_file(SOCK_PATH)?;
    }

    let listener = UnixListener::bind(SOCK_PATH)?;
    set_mode(Path::new(SOCK_PATH), 0o660)?;

    if let Some(parent) = Path::new(EVENT_LOG).parent() {
        ensure_dir(parent, 0o750)?;
    }

    let mut journal = ReplayJournal::open(Path::new(REPLAY_JOURNAL))?;

    eprintln!("actuator-min: listening on {SOCK_PATH}");

    for stream in listener.incoming() {
        match stream {
            Ok(mut stream) => {
                if let Err(err) = stream.set_read_timeout(Some(READ_TIMEOUT)) {
                    eprintln!("actuator-min: set_read_timeout failed: {err}");
                    continue;
                }

                let mut frame = [0u8; 32];
                if let Err(err) = stream.read_exact(&mut frame) {
                    if matches!(err.kind(), ErrorKind::TimedOut | ErrorKind::WouldBlock) {
                        eprintln!("actuator-min: read timeout; dropping connection");
                    } else {
                        eprintln!("actuator-min: read_exact failed: {err}");
                    }
                    continue;
                }

                let token = token_from_frame(&frame);
                match journal.record_token(token) {
                    Ok(true) => {}
                    Ok(false) => continue,
                    Err(err) => {
                        eprintln!("actuator-min: replay journal failure: {err}");
                        return Err(err);
                    }
                }

                let line = format_frame_line(&frame);
                if let Err(err) = append_event_line(Path::new(EVENT_LOG), &line) {
                    eprintln!("actuator-min: event log append failed: {err}");
                    return Err(err);
                }
            }
            Err(err) => {
                eprintln!("actuator-min: accept error: {err}");
                return Err(err);
            }
        }
    }

    Ok(())
}

fn ensure_dir(path: &Path, mode: u32) -> io::Result<()> {
    fs::create_dir_all(path)?;
    set_mode(path, mode)?;
    Ok(())
}

#[cfg(unix)]
fn set_mode(path: &Path, mode: u32) -> io::Result<()> {
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
}

#[cfg(not(unix))]
fn set_mode(_path: &Path, _mode: u32) -> io::Result<()> {
    Ok(())
}

fn append_event_line(path: &Path, line: &str) -> io::Result<()> {
    let mut file = OpenOptions::new().create(true).append(true).open(path)?;
    file.write_all(line.as_bytes())?;
    file.flush()?;
    Ok(())
}

fn parse_journal_bytes(data: &[u8]) -> io::Result<HashSet<u128>> {
    if data.len() % 16 != 0 {
        return Err(io::Error::new(
            ErrorKind::InvalidData,
            "replay journal length is not a multiple of 16 bytes",
        ));
    }

    let mut seen_tokens = HashSet::with_capacity(data.len() / 16);
    for chunk in data.chunks_exact(16) {
        let mut token_bytes = [0u8; 16];
        token_bytes.copy_from_slice(chunk);
        let token = u128::from_le_bytes(token_bytes);
        if !seen_tokens.insert(token) {
            return Err(io::Error::new(
                ErrorKind::InvalidData,
                "replay journal contains duplicate tokens",
            ));
        }
    }

    Ok(seen_tokens)
}

fn token_from_frame(frame: &[u8; 32]) -> u128 {
    let mut token_bytes = [0u8; 16];
    token_bytes.copy_from_slice(&frame[16..32]);
    u128::from_le_bytes(token_bytes)
}

fn format_frame_line(frame: &[u8; 32]) -> String {
    let mut line = String::with_capacity(EVENT_LOG_PREFIX.len() + 64 + 1);
    line.push_str(EVENT_LOG_PREFIX);
    for byte in frame {
        let _ = write!(line, "{byte:02x}");
    }
    line.push('\n');
    line
}

struct ReplayJournal {
    file: File,
    seen_tokens: HashSet<u128>,
}

impl ReplayJournal {
    fn open(path: &Path) -> io::Result<Self> {
        if let Some(parent) = path.parent() {
            ensure_dir(parent, 0o750)?;
        }

        let mut file = OpenOptions::new()
            .read(true)
            .append(true)
            .create(true)
            .open(path)?;
        set_mode(path, 0o640)?;

        file.seek(SeekFrom::Start(0))?;
        let mut data = Vec::new();
        file.read_to_end(&mut data)?;
        let seen_tokens = parse_journal_bytes(&data)?;
        file.seek(SeekFrom::End(0))?;

        Ok(Self { file, seen_tokens })
    }

    fn record_token(&mut self, token: u128) -> io::Result<bool> {
        if self.seen_tokens.contains(&token) {
            return Ok(false);
        }

        self.file.write_all(&token.to_le_bytes())?;
        self.file.flush()?;
        self.file.sync_data()?;
        self.seen_tokens.insert(token);
        Ok(true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_temp_path(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock drift")
            .as_nanos();
        std::env::temp_dir()
            .join(format!("actuator-min-{name}-{nonce}"))
            .join("journal.bin")
    }

    #[test]
    fn format_frame_line_uses_frame_hex_prefix() {
        let frame = [0u8; 32];
        let expected = format!("{EVENT_LOG_PREFIX}{}\n", "00".repeat(32));
        assert_eq!(format_frame_line(&frame), expected);
    }

    #[test]
    fn parse_journal_rejects_misaligned_length() {
        let err = parse_journal_bytes(&[0u8; 15]).expect_err("misaligned journal should fail");
        assert_eq!(err.kind(), ErrorKind::InvalidData);
    }

    #[test]
    fn parse_journal_rejects_duplicate_tokens() {
        let token = 7u128.to_le_bytes();
        let mut journal = Vec::new();
        journal.extend_from_slice(&token);
        journal.extend_from_slice(&token);

        let err = parse_journal_bytes(&journal).expect_err("duplicate token should fail");
        assert_eq!(err.kind(), ErrorKind::InvalidData);
    }

    #[test]
    fn parse_journal_accepts_distinct_tokens() {
        let mut journal = Vec::new();
        journal.extend_from_slice(&7u128.to_le_bytes());
        journal.extend_from_slice(&9u128.to_le_bytes());

        let seen = parse_journal_bytes(&journal).expect("distinct tokens should load");
        assert!(seen.contains(&7));
        assert!(seen.contains(&9));
        assert_eq!(seen.len(), 2);
    }

    #[test]
    fn token_from_frame_reads_trailing_u128() {
        let mut frame = [0u8; 32];
        frame[16..32].copy_from_slice(&55u128.to_le_bytes());
        assert_eq!(token_from_frame(&frame), 55);
    }

    #[test]
    fn append_event_line_creates_log_file() {
        let path = unique_temp_path("event-log");
        let parent = path.parent().expect("log parent");
        fs::create_dir_all(parent).expect("create temp dir");

        append_event_line(&path, "FRAME_HEX=abcd\n").expect("append event");
        let contents = fs::read_to_string(&path).expect("read event log");
        assert_eq!(contents, "FRAME_HEX=abcd\n");

        fs::remove_file(&path).expect("remove event log");
        fs::remove_dir_all(parent).expect("remove temp dir");
    }

    #[test]
    fn replay_journal_open_rejects_corrupt_file() {
        let path = unique_temp_path("corrupt");
        let parent = path.parent().expect("journal parent");
        fs::create_dir_all(parent).expect("create temp dir");
        fs::write(&path, [1u8; 15]).expect("write corrupt journal");

        let err = ReplayJournal::open(&path).err().expect("corrupt journal should fail");
        assert_eq!(err.kind(), ErrorKind::InvalidData);

        fs::remove_file(&path).expect("remove corrupt journal");
        fs::remove_dir_all(parent).expect("remove temp dir");
    }

    #[test]
    fn replay_journal_reloads_and_drops_duplicates() {
        let path = unique_temp_path("replay");
        let parent = path.parent().expect("journal parent");
        fs::create_dir_all(parent).expect("create temp dir");

        {
            let mut journal = ReplayJournal::open(&path).expect("open journal");
            assert!(journal.record_token(42).expect("record first token"));
            assert!(!journal.record_token(42).expect("drop duplicate token"));
        }

        {
            let mut reopened = ReplayJournal::open(&path).expect("reopen journal");
            assert!(!reopened.record_token(42).expect("persisted token should replay-drop"));
            assert!(reopened.record_token(99).expect("record second token"));
        }

        assert_eq!(fs::metadata(&path).expect("journal metadata").len(), 32);

        fs::remove_file(&path).expect("remove journal");
        fs::remove_dir_all(parent).expect("remove temp dir");
    }
}

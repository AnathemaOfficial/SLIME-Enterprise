#![cfg_attr(not(unix), allow(dead_code, unused_imports))]

use std::collections::{HashSet, VecDeque};
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
const REPLAY_MAX_TOKENS: usize = 65_536;

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

    let mut journal = ReplayJournal::open(Path::new(REPLAY_JOURNAL), REPLAY_MAX_TOKENS)?;

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

fn parse_journal_bytes(data: &[u8]) -> io::Result<VecDeque<u128>> {
    if data.len() % 16 != 0 {
        return Err(io::Error::new(
            ErrorKind::InvalidData,
            "replay journal length is not a multiple of 16 bytes",
        ));
    }

    let mut ordered_tokens = VecDeque::with_capacity(data.len() / 16);
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
        ordered_tokens.push_back(token);
    }

    Ok(ordered_tokens)
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
    /// Canonical path kept so `rewrite_file` can do an atomic temp-file +
    /// rename rather than an in-place truncate. Closes Copilot audit
    /// finding H-2: the prior `set_len(0)` + in-place rewrite lost the
    /// full journal on crash between `set_len(0)` and `sync_data`,
    /// allowing replay of every previously-seen token on recovery.
    path: PathBuf,
    seen_tokens: HashSet<u128>,
    order: VecDeque<u128>,
    max_entries: usize,
}

impl ReplayJournal {
    fn open(path: &Path, max_entries: usize) -> io::Result<Self> {
        if let Some(parent) = path.parent() {
            ensure_dir(parent, 0o750)?;
        }

        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .open(path)?;
        set_mode(path, 0o640)?;

        file.seek(SeekFrom::Start(0))?;
        let mut data = Vec::new();
        file.read_to_end(&mut data)?;
        let order = parse_journal_bytes(&data)?;
        let mut seen_tokens = HashSet::with_capacity(order.len());
        for token in &order {
            seen_tokens.insert(*token);
        }

        let mut journal = Self {
            file,
            path: path.to_path_buf(),
            seen_tokens,
            order,
            max_entries,
        };

        journal.compact_if_needed()?;
        journal.file.seek(SeekFrom::End(0))?;

        Ok(journal)
    }

    fn record_token(&mut self, token: u128) -> io::Result<bool> {
        if self.seen_tokens.contains(&token) {
            return Ok(false);
        }

        let requires_compaction = self.order.len() >= self.max_entries;
        if requires_compaction {
            if let Some(oldest) = self.order.pop_front() {
                self.seen_tokens.remove(&oldest);
            }
        }

        self.order.push_back(token);
        self.seen_tokens.insert(token);
        if requires_compaction {
            self.rewrite_file()?;
        } else {
            self.file.seek(SeekFrom::End(0))?;
            self.file.write_all(&token.to_le_bytes())?;
            self.file.flush()?;
            self.file.sync_data()?;
        }
        Ok(true)
    }

    fn compact_if_needed(&mut self) -> io::Result<()> {
        if self.order.len() <= self.max_entries {
            return Ok(());
        }

        while self.order.len() > self.max_entries {
            if let Some(oldest) = self.order.pop_front() {
                self.seen_tokens.remove(&oldest);
            }
        }

        self.rewrite_file()
    }

    fn rewrite_file(&mut self) -> io::Result<()> {
        // Copilot audit finding H-2: atomic rewrite via temp + rename.
        // Previously the journal was truncated with `set_len(0)` and then
        // rewritten in place — a crash between the truncate and the final
        // `sync_data` left an empty journal on disk, so on the next boot
        // every previously-seen replay token could be re-accepted.
        //
        // We now write the full new journal to a temp file, fsync it, and
        // atomically rename it over the canonical path. POSIX `rename`
        // on the same filesystem is atomic: the journal always points
        // to either the fully-written new content or the untouched old
        // content, never to a zero-length transient state.
        let tmp_path = self.path.with_extension("bin.tmp");
        // Best-effort removal of a stale tmp from a prior crash.
        let _ = fs::remove_file(&tmp_path);
        {
            let mut tmp_file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&tmp_path)?;
            for token in &self.order {
                tmp_file.write_all(&token.to_le_bytes())?;
            }
            tmp_file.flush()?;
            tmp_file.sync_data()?;
        }
        #[cfg(unix)]
        set_mode(&tmp_path, 0o640)?;
        fs::rename(&tmp_path, &self.path)?;
        // The rename replaced the inode we held open — re-open to track
        // the live file and restore the append position for later writes.
        self.file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(false)
            .open(&self.path)?;
        Ok(())
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

        let ordered = parse_journal_bytes(&journal).expect("distinct tokens should load");
        assert_eq!(ordered.len(), 2);
        assert_eq!(ordered[0], 7);
        assert_eq!(ordered[1], 9);
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

        let err = ReplayJournal::open(&path, 4)
            .err()
            .expect("corrupt journal should fail");
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
            let mut journal = ReplayJournal::open(&path, 4).expect("open journal");
            assert!(journal.record_token(42).expect("record first token"));
            assert!(!journal.record_token(42).expect("drop duplicate token"));
        }

        {
            let mut reopened = ReplayJournal::open(&path, 4).expect("reopen journal");
            assert!(!reopened.record_token(42).expect("persisted token should replay-drop"));
            assert!(reopened.record_token(99).expect("record second token"));
        }

        assert_eq!(fs::metadata(&path).expect("journal metadata").len(), 32);

        fs::remove_file(&path).expect("remove journal");
        fs::remove_dir_all(parent).expect("remove temp dir");
    }

    #[test]
    fn replay_journal_compacts_on_open_when_file_exceeds_capacity() {
        let path = unique_temp_path("compact-open");
        let parent = path.parent().expect("journal parent");
        fs::create_dir_all(parent).expect("create temp dir");

        let mut raw = Vec::new();
        for token in [1u128, 2, 3, 4, 5] {
            raw.extend_from_slice(&token.to_le_bytes());
        }
        fs::write(&path, raw).expect("seed journal");

        let reopened = ReplayJournal::open(&path, 3).expect("open compacted journal");
        assert_eq!(reopened.order.iter().copied().collect::<Vec<_>>(), vec![3, 4, 5]);
        assert_eq!(fs::metadata(&path).expect("journal metadata").len(), 48);

        fs::remove_file(&path).expect("remove journal");
        fs::remove_dir_all(parent).expect("remove temp dir");
    }

    #[test]
    fn replay_journal_evicts_oldest_token_when_capacity_is_reached() {
        let path = unique_temp_path("compact-insert");
        let parent = path.parent().expect("journal parent");
        fs::create_dir_all(parent).expect("create temp dir");

        let mut journal = ReplayJournal::open(&path, 2).expect("open journal");
        assert!(journal.record_token(10).expect("record first token"));
        assert!(journal.record_token(20).expect("record second token"));
        assert!(journal.record_token(30).expect("record third token"));
        assert_eq!(journal.order.iter().copied().collect::<Vec<_>>(), vec![20, 30]);
        assert!(!journal.record_token(20).expect("drop existing token"));
        assert!(journal.record_token(10).expect("oldest evicted token can re-enter"));

        fs::remove_file(&path).expect("remove journal");
        fs::remove_dir_all(parent).expect("remove temp dir");
    }
}

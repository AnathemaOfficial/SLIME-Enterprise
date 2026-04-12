#!/usr/bin/env python3
"""
SLIME Dashboard — Read-Only Observation Server + AI Analyst
noncanon/enterprise/dashboard — NOT part of the law-layer.

Serves a web dashboard on port 8081 showing:
  - Decoded actuator event log (last 50 authorized actions)
  - systemd service status (slime.service, actuator.service)
  - FP-1 seal file integrity status
  - Runner health check (non-invasive IMPOSSIBLE probe)
  - AI Analyst endpoint (multi-provider LLM, read-only decision interpreter)

No feedback into SLIME execution. Read-only by construction.
"""

import json
import logging
import os
import re
import shutil
import socket
import struct
import subprocess  # noqa: S404 — needed for systemctl queries
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

import urllib.request  # noqa: S310 — used for local Ollama API only
import urllib.error

# AI Analyst dependencies (graceful degradation if absent)
try:
    import anthropic
    _HAS_ANTHROPIC = True
except ImportError:
    anthropic = None
    _HAS_ANTHROPIC = False

try:
    import openai
    _HAS_OPENAI = True
except ImportError:
    openai = None
    _HAS_OPENAI = False

import analyst_context

logger = logging.getLogger("slime-dashboard")

# Resolve absolute path for systemctl once at import time.
SYSTEMCTL_BIN = shutil.which("systemctl") or "/usr/bin/systemctl"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

HOST = "127.0.0.1"
PORT = 8081
LOG_PATH = "/var/log/slime-actuator/events.log"
SEAL_PATH = "/usr/lib/slime/fireplank.seal"
RUNNER_HOST = "127.0.0.1"
RUNNER_PORT = 8080
MAX_EVENTS = 50

# Domain table — mirrors runner's compile-time DOMAIN_TABLE.
# Must be kept in sync manually. This is noncanon observation convenience.
DOMAIN_TABLE = {0: "test", 1: "payment", 2: "deploy", 3: "db_prod"}

DASHBOARD_HTML = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dashboard.html")

# ---------------------------------------------------------------------------
# AI Analyst configuration — Multi-provider LLM
# ---------------------------------------------------------------------------
#
# Supported providers (set via ANALYST_PROVIDER env var):
#   anthropic  — Claude API     (requires: pip install anthropic)
#   openai     — OpenAI GPT API (requires: pip install openai)
#   kimi       — Moonshot Kimi  (requires: pip install openai)
#   ollama     — Local Ollama   (requires: ollama running, no pip dependency)
#
# Environment variables per provider:
#   anthropic: ANTHROPIC_API_KEY, ANTHROPIC_MODEL (default: claude-sonnet-4-20250514)
#   openai:    OPENAI_API_KEY,    OPENAI_MODEL    (default: gpt-4o)
#   kimi:      KIMI_API_KEY,      KIMI_MODEL      (default: moonshot-v1-8k)
#   ollama:    OLLAMA_HOST,       OLLAMA_MODEL    (default: qwen2.5:14b)
#

ANALYST_PROVIDER = os.environ.get("ANALYST_PROVIDER", "ollama")

PROVIDER_DEFAULTS = {
    "anthropic": {"model": "claude-sonnet-4-20250514"},
    "openai":    {"model": "gpt-4o"},
    "kimi":      {"model": "moonshot-v1-8k", "base_url": "https://api.moonshot.cn/v1"},
    "ollama":    {"model": "qwen2.5:14b", "host": "http://localhost:11434"},
}

FRAME_HEX_RE = re.compile(r"FRAME_HEX=([0-9a-f]{64})")
RAW_HEX_RE = re.compile(r"^[0-9a-f]{64}$")

CHAT_MAX_TOKENS = 1024
CHAT_RATE_LIMIT_SECONDS = 2
CHAT_MAX_BODY_BYTES = 4096
CHAT_MAX_MESSAGE_CHARS = 2000

# System prompt: role and behavior ONLY — no data, no rules.
# Rules come from analyst_rules.py via analyst_context.build_static_context().
ANALYST_SYSTEM_PROMPT = """\
You are the SLIME AI Analyst — a read-only decision interpreter for the \
Sealed Law-layer Execution Environment (SLIME Enterprise).

You do NOT control SLIME. You do NOT send commands. You EXPLAIN decisions.

DISCIPLINE OF UNCERTAINTY:
- Always distinguish: observed fact / known rule / probable inference
- Never state a cause as certain unless explicitly present in the context
- Use "probable cause", "based on known rules", "most plausible interpretation"
- If context is insufficient, say so clearly

RESPONSE FORMAT:
- Be concise: 120-250 words maximum
- Use structured format when explaining verdicts (bullet points)
- State the verdict first, then the reasoning
- Cite specific rules when applicable

You receive two context blocks:
<static_rules> = versioned SYF rules (source of truth for analyst)
<live_state> = current system state (events, services, seal, health)

Base your analysis strictly on these two blocks. Do not invent data.\
"""

# Rate limiter state (thread-safe)
_chat_rate_lock = threading.Lock()
_chat_last_request: dict[str, float] = {}


# ---------------------------------------------------------------------------
# LLM Provider Abstraction
# ---------------------------------------------------------------------------

def _get_analyst_model() -> str:
    """Return the model name for the active provider."""
    provider = ANALYST_PROVIDER
    env_key = f"{provider.upper()}_MODEL"
    return os.environ.get(env_key, PROVIDER_DEFAULTS.get(provider, {}).get("model", ""))


def _analyst_available() -> tuple[bool, str]:
    """Check if the analyst is available. Returns (available, reason)."""
    provider = ANALYST_PROVIDER
    if provider == "ollama":
        host = os.environ.get("OLLAMA_HOST", PROVIDER_DEFAULTS["ollama"]["host"]).rstrip("/")
        try:
            with urllib.request.urlopen(f"{host}/api/tags", timeout=2) as resp:
                if resp.status < 200 or resp.status >= 300:
                    return False, f"ollama returned HTTP {resp.status}"
        except Exception as exc:
            return False, f"ollama unavailable ({exc})"
        return True, "ok"
    if provider == "anthropic":
        if not _HAS_ANTHROPIC:
            return False, "anthropic package not installed"
        if not os.environ.get("ANTHROPIC_API_KEY"):
            return False, "missing ANTHROPIC_API_KEY"
    elif provider == "openai":
        if not _HAS_OPENAI:
            return False, "openai package not installed"
        if not os.environ.get("OPENAI_API_KEY"):
            return False, "missing OPENAI_API_KEY"
    elif provider == "kimi":
        if not _HAS_OPENAI:
            return False, "openai package not installed (required for Kimi)"
        if not os.environ.get("KIMI_API_KEY"):
            return False, "missing KIMI_API_KEY"
    elif provider == "ollama":
        pass  # No dependency check — uses urllib (stdlib)
    else:
        return False, f"unknown provider: {provider}"
    return True, "ok"


def _call_llm(system_prompt: str, user_content: str) -> str:
    """Call the configured LLM provider and return the response text.

    Raises Exception on failure (caller handles error response).
    """
    provider = ANALYST_PROVIDER
    model = _get_analyst_model()

    if provider == "anthropic":
        client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
        response = client.messages.create(
            model=model,
            max_tokens=CHAT_MAX_TOKENS,
            system=system_prompt,
            messages=[{"role": "user", "content": user_content}],
        )
        return response.content[0].text

    elif provider in ("openai", "kimi"):
        kwargs = {"api_key": os.environ.get("OPENAI_API_KEY")}
        if provider == "kimi":
            kwargs["api_key"] = os.environ["KIMI_API_KEY"]
            kwargs["base_url"] = PROVIDER_DEFAULTS["kimi"]["base_url"]
        client = openai.OpenAI(**kwargs)
        response = client.chat.completions.create(
            model=model,
            max_tokens=CHAT_MAX_TOKENS,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
        )
        return response.choices[0].message.content

    elif provider == "ollama":
        host = os.environ.get("OLLAMA_HOST", PROVIDER_DEFAULTS["ollama"]["host"])
        url = f"{host}/api/chat"
        payload = json.dumps({
            "model": model,
            "stream": False,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
        }).encode()
        req = urllib.request.Request(
            url, data=payload,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        return data["message"]["content"]

    else:
        raise ValueError(f"Unknown provider: {provider}")


def _check_rate_limit(client_ip: str) -> bool:
    """Return True if the request is allowed, False if rate-limited."""
    now = time.time()
    with _chat_rate_lock:
        last = _chat_last_request.get(client_ip, 0)
        if now - last < CHAT_RATE_LIMIT_SECONDS:
            return False
        _chat_last_request[client_ip] = now
        # Periodic cleanup
        if len(_chat_last_request) > 100:
            cutoff = now - 60
            stale = [k for k, v in _chat_last_request.items() if v < cutoff]
            for k in stale:
                del _chat_last_request[k]
        return True


# ---------------------------------------------------------------------------
# Event log decoder
# ---------------------------------------------------------------------------

def extract_hex(line: str) -> str | None:
    """Extract 64-char hex from a log line.

    Handles two formats produced by the actuator:
      - Raw hex:        <64 hex chars>
      - Tagged line:    ... FRAME_HEX=<64 hex chars>
    """
    line = line.strip()
    tagged = FRAME_HEX_RE.search(line)
    if tagged is not None:
        return tagged.group(1)
    if RAW_HEX_RE.fullmatch(line):
        return line
    return None


def decode_event(hex_line: str) -> dict | None:
    """Decode a log line into a structured event dict."""
    hex_str = extract_hex(hex_line)
    if hex_str is None:
        return None
    try:
        raw = bytes.fromhex(hex_str)
    except ValueError:
        return None
    domain_id, magnitude = struct.unpack_from("<QQ", raw, 0)
    token_lo, token_hi = struct.unpack_from("<QQ", raw, 16)
    token = token_lo | (token_hi << 64)
    return {
        "domain_id": domain_id,
        "domain": DOMAIN_TABLE.get(domain_id, f"unknown({domain_id})"),
        "magnitude": magnitude,
        "token": f"{token:032x}",
    }


def read_log():
    """Read event log. Returns (recent_events[], total_count, domain_counts{})."""
    try:
        with open(LOG_PATH, "r") as f:
            lines = f.readlines()
    except (FileNotFoundError, PermissionError):
        return [], 0, {}

    valid = [l for l in lines if extract_hex(l) is not None]
    total = len(valid)

    # Domain counters from all events
    domain_counts = {}
    for line in valid:
        d = decode_event(line)
        if d:
            name = d["domain"]
            domain_counts[name] = domain_counts.get(name, 0) + 1

    # Decode only recent for display
    recent = []
    for line in valid[-MAX_EVENTS:]:
        d = decode_event(line)
        if d:
            recent.append(d)
    recent.reverse()  # newest first

    return recent, total, domain_counts


# ---------------------------------------------------------------------------
# Systemd service status
# ---------------------------------------------------------------------------

def get_service_status(name: str) -> dict:
    """Query systemd for a service's status."""
    try:
        r = subprocess.run(
            [SYSTEMCTL_BIN, "is-active", name],
            capture_output=True, text=True, timeout=3,
        )
        active = r.stdout.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        logger.warning("systemctl is-active %s failed: %s", name, exc)
        active = "unknown"

    pid, since = "", ""
    try:
        r = subprocess.run(
            [SYSTEMCTL_BIN, "show", name,
             "--property=MainPID,ActiveEnterTimestamp"],
            capture_output=True, text=True, timeout=3,
        )
        for line in r.stdout.strip().splitlines():
            if line.startswith("MainPID="):
                pid = line.split("=", 1)[1]
            elif line.startswith("ActiveEnterTimestamp="):
                since = line.split("=", 1)[1]
    except (OSError, subprocess.TimeoutExpired) as exc:
        logger.warning("systemctl show %s failed: %s", name, exc)

    return {"name": name, "active": active, "pid": pid, "since": since}


# ---------------------------------------------------------------------------
# FP-1 seal file
# ---------------------------------------------------------------------------

def get_seal_status() -> dict:
    """Read the FirePlank boot-integrity seal file."""
    try:
        with open(SEAL_PATH, "r") as f:
            content = f.read()
        seal = {}
        for line in content.splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                seal[k.strip()] = v.strip()
        return {
            "present": True,
            "actuator_hash": seal.get("ACTUATOR_BIN_HASH", "")[:16] + "...",
            "runner_hash": seal.get("RUNNER_BIN_HASH", "")[:16] + "...",
            "generated": seal.get("Generated", ""),
        }
    except (FileNotFoundError, PermissionError):
        return {"present": False}


# ---------------------------------------------------------------------------
# Runner health probe
# ---------------------------------------------------------------------------

def ping_runner() -> dict:
    """Send a deliberately-impossible request to verify the runner responds."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect((RUNNER_HOST, RUNNER_PORT))
        body = b'{"domain":"__healthcheck__","magnitude":1}'
        req = (
            f"POST /action HTTP/1.1\r\n"
            f"Host: {RUNNER_HOST}:{RUNNER_PORT}\r\n"
            f"Content-Length: {len(body)}\r\n"
            f"Connection: close\r\n"
            f"\r\n"
        ).encode() + body
        s.sendall(req)
        # Signal done sending, wait for response
        s.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        s.close()
        text = b"".join(chunks).decode("utf-8", errors="replace")
        if "status" in text:
            return {"reachable": True, "status": "responding"}
        else:
            return {"reachable": True, "status": "unexpected"}
    except Exception as e:
        return {"reachable": False, "error": str(e)}


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------

class DashboardHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            self._serve_html()
        elif self.path == "/api/events":
            self._serve_events()
        elif self.path == "/api/status":
            self._serve_status()
        elif self.path == "/api/health":
            self._serve_health()
        elif self.path == "/api/analyst/info":
            self._serve_analyst_info()
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/api/analyst":
            self._serve_analyst()
        else:
            self.send_error(404)

    def _serve_html(self):
        try:
            with open(DASHBOARD_HTML, "r") as f:
                html = f.read()
        except FileNotFoundError:
            html = "<h1>dashboard.html not found</h1>"
        self._send(200, "text/html; charset=utf-8", html.encode())

    def _serve_events(self):
        events, total, domain_counts = read_log()
        self._json({"events": events, "total": total, "by_domain": domain_counts})

    def _serve_status(self):
        self._json({
            "services": {
                "slime": get_service_status("slime.service"),
                "actuator": get_service_status("actuator.service"),
            },
            "seal": get_seal_status(),
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
        })

    def _serve_health(self):
        self._json({"runner": ping_runner()})

    def _serve_analyst_info(self):
        """Return analyst provider info (no secrets exposed)."""
        available, reason = _analyst_available()
        self._json({
            "available": available,
            "provider": ANALYST_PROVIDER,
            "model": _get_analyst_model() if available else None,
            "reason": reason if not available else None,
        })

    def _serve_analyst(self):
        """AI Analyst endpoint — read-only decision interpreter (multi-provider)."""
        # Rate limit
        client_ip = self.client_address[0]
        if not _check_rate_limit(client_ip):
            self._json_error(429, "Rate limited. Please wait before sending another message.")
            return

        # Check provider availability
        available, reason = _analyst_available()
        if not available:
            self._json_error(503, f"AI Analyst not available ({reason})")
            return

        # Read and validate body
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0 or content_length > CHAT_MAX_BODY_BYTES:
            self._json_error(400, "Invalid request body")
            return

        raw_body = self.rfile.read(content_length)
        try:
            data = json.loads(raw_body)
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._json_error(400, "Invalid JSON")
            return

        message = data.get("message", "").strip()
        if not message:
            self._json_error(400, "Empty message")
            return
        if len(message) > CHAT_MAX_MESSAGE_CHARS:
            self._json_error(400, f"Message too long (max {CHAT_MAX_MESSAGE_CHARS} chars)")
            return

        # Build context
        try:
            static_ctx = analyst_context.build_static_context()
        except Exception as exc:
            logger.error("Failed to build static context: %s", exc)
            static_ctx = "(static rules unavailable)"

        try:
            live_ctx = analyst_context.build_live_context(
                read_log, get_service_status, get_seal_status, ping_runner,
            )
        except Exception as exc:
            logger.error("Failed to build live context: %s", exc)
            live_ctx = "(live state unavailable)"

        user_content = (
            f"<static_rules>\n{static_ctx}\n</static_rules>\n\n"
            f"<live_state>\n{live_ctx}\n</live_state>\n\n"
            f"Operator question: {message}"
        )

        # Call LLM
        try:
            answer = _call_llm(ANALYST_SYSTEM_PROMPT, user_content)
        except Exception as exc:
            logger.error("Analyst LLM call failed (%s): %s", ANALYST_PROVIDER, exc)
            self._json_error(502, "AI Analyst temporarily unavailable")
            return

        self._json({"response": answer})

    # helpers
    def _json(self, data):
        body = json.dumps(data).encode()
        self._send(200, "application/json", body)

    def _json_error(self, code, message):
        body = json.dumps({"error": message}).encode()
        self._send(code, "application/json", body)

    def _send(self, code, content_type, body):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # suppress per-request logging


# ---------------------------------------------------------------------------
# Threaded server (non-blocking)
# ---------------------------------------------------------------------------

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    server = ThreadedHTTPServer((HOST, PORT), DashboardHandler)
    print(f"[slime-dashboard] listening on http://{HOST}:{PORT}")
    print(f"[slime-dashboard] event log: {LOG_PATH}")
    print(f"[slime-dashboard] seal file: {SEAL_PATH}")
    available, reason = _analyst_available()
    if available:
        print(f"[slime-dashboard] AI Analyst: enabled (provider={ANALYST_PROVIDER}, model={_get_analyst_model()})")
    else:
        print(f"[slime-dashboard] AI Analyst: disabled ({reason})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[slime-dashboard] shutting down")
        server.shutdown()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
SLIME Dashboard — Read-Only Observation Server
noncanon/enterprise/dashboard — NOT part of the law-layer.

Serves a web dashboard on port 8081 showing:
  - Decoded actuator event log (last 50 authorized actions)
  - systemd service status (slime.service, actuator.service)
  - FP-1 seal file integrity status
  - Runner health check (non-invasive IMPOSSIBLE probe)

No feedback into SLIME execution. Read-only by construction.
"""

import json
import os
import socket
import struct
import subprocess
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

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
# Event log decoder
# ---------------------------------------------------------------------------

def extract_hex(line: str) -> str | None:
    """Extract 64-char hex from a log line.

    Handles two formats produced by the actuator:
      - Raw hex:        <64 hex chars>
      - Sed-piped:      FRAME_HEX=<64 hex chars>
    """
    line = line.strip()
    if line.startswith("FRAME_HEX="):
        line = line[len("FRAME_HEX="):]
    if len(line) == 64:
        try:
            bytes.fromhex(line)
            return line
        except ValueError:
            pass
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
            ["systemctl", "is-active", name],
            capture_output=True, text=True, timeout=3,
        )
        active = r.stdout.strip()
    except Exception:
        active = "unknown"

    pid, since = "", ""
    try:
        r = subprocess.run(
            ["systemctl", "show", name,
             "--property=MainPID,ActiveEnterTimestamp"],
            capture_output=True, text=True, timeout=3,
        )
        for line in r.stdout.strip().splitlines():
            if line.startswith("MainPID="):
                pid = line.split("=", 1)[1]
            elif line.startswith("ActiveEnterTimestamp="):
                since = line.split("=", 1)[1]
    except Exception:
        pass

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

    # helpers
    def _json(self, data):
        body = json.dumps(data).encode()
        self._send(200, "application/json", body)

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
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[slime-dashboard] shutting down")
        server.shutdown()


if __name__ == "__main__":
    main()

import contextlib
import http.client
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock


DASHBOARD_DIR = Path(__file__).resolve().parents[1]
if str(DASHBOARD_DIR) not in sys.path:
    sys.path.insert(0, str(DASHBOARD_DIR))

import analyst_context  # noqa: E402
import server  # noqa: E402


def make_frame_hex(domain_id: int, magnitude: int, token: int) -> str:
    return (
        domain_id.to_bytes(8, "little")
        + magnitude.to_bytes(8, "little")
        + token.to_bytes(16, "little")
    ).hex()


@contextlib.contextmanager
def running_server():
    httpd = server.ThreadedHTTPServer(("127.0.0.1", 0), server.DashboardHandler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield httpd.server_address[1]
    finally:
        httpd.shutdown()
        thread.join(timeout=2)
        httpd.server_close()


def request_json(method: str, path: str, body=None):
    payload = None
    headers = {}
    if body is not None:
        payload = json.dumps(body)
        headers["Content-Type"] = "application/json"

    with running_server() as port:
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        conn.request(method, path, body=payload, headers=headers)
        response = conn.getresponse()
        raw = response.read().decode()
        conn.close()
    return response.status, json.loads(raw)


class ExtractHexTests(unittest.TestCase):
    def test_extract_hex_accepts_raw_hex_line(self):
        raw = "ab" * 32
        self.assertEqual(server.extract_hex(raw), raw)

    def test_extract_hex_accepts_timestamped_frame_hex_line(self):
        raw = "cd" * 32
        line = f"2026-03-01T12:00:00Z FRAME_HEX={raw}"
        self.assertEqual(server.extract_hex(line), raw)

    def test_extract_hex_rejects_invalid_lines(self):
        self.assertIsNone(server.extract_hex("FRAME_HEX=not-hex"))
        self.assertIsNone(server.extract_hex("garbage"))


class DecodeAndLogTests(unittest.TestCase):
    def test_decode_event_maps_known_domain(self):
        frame_hex = make_frame_hex(domain_id=0, magnitude=7, token=1234)
        decoded = server.decode_event(frame_hex)
        self.assertEqual(decoded["domain"], "test")
        self.assertEqual(decoded["magnitude"], 7)
        self.assertEqual(decoded["token"], f"{1234:032x}")

    def test_decode_event_uses_unknown_label_for_unmapped_domain(self):
        frame_hex = make_frame_hex(domain_id=99, magnitude=3, token=9)
        decoded = server.decode_event(frame_hex)
        self.assertEqual(decoded["domain"], "unknown(99)")

    def test_read_log_ignores_invalid_lines_and_counts_domains(self):
        valid_test = make_frame_hex(domain_id=0, magnitude=1, token=1)
        valid_deploy = make_frame_hex(domain_id=2, magnitude=2, token=2)

        with tempfile.TemporaryDirectory() as tmpdir:
            log_path = Path(tmpdir) / "events.log"
            log_path.write_text(
                "\n".join(
                    [
                        "noise",
                        f"FRAME_HEX={valid_test}",
                        f"2026-03-01T12:00:00Z FRAME_HEX={valid_deploy}",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            with mock.patch.object(server, "LOG_PATH", str(log_path)):
                events, total, domain_counts = server.read_log()

        self.assertEqual(total, 2)
        self.assertEqual(domain_counts, {"test": 1, "deploy": 1})
        self.assertEqual([event["domain"] for event in events], ["deploy", "test"])


class AnalystAvailabilityTests(unittest.TestCase):
    def test_openai_provider_requires_api_key(self):
        with mock.patch.object(server, "ANALYST_PROVIDER", "openai"), \
             mock.patch.object(server, "_HAS_OPENAI", True), \
             mock.patch.dict(server.os.environ, {}, clear=True):
            available, reason = server._analyst_available()

        self.assertFalse(available)
        self.assertIn("OPENAI_API_KEY", reason)

    def test_unknown_provider_is_reported(self):
        with mock.patch.object(server, "ANALYST_PROVIDER", "mystery"):
            available, reason = server._analyst_available()

        self.assertFalse(available)
        self.assertIn("unknown provider", reason)

    def test_ollama_provider_checks_reachability(self):
        with mock.patch.object(server, "ANALYST_PROVIDER", "ollama"), \
             mock.patch("server.urllib.request.urlopen", side_effect=TimeoutError("timed out")):
            available, reason = server._analyst_available()

        self.assertFalse(available)
        self.assertIn("ollama unavailable", reason)

    def test_ollama_provider_accepts_successful_probe(self):
        response = mock.MagicMock()
        response.__enter__.return_value.status = 200

        with mock.patch.object(server, "ANALYST_PROVIDER", "ollama"), \
             mock.patch("server.urllib.request.urlopen", return_value=response):
            available, reason = server._analyst_available()

        self.assertTrue(available)
        self.assertEqual(reason, "ok")


class AnalystContextTests(unittest.TestCase):
    def test_build_static_context_contains_key_sections(self):
        context = analyst_context.build_static_context()
        self.assertIn("Domain Table", context)
        self.assertIn("AUTHORIZED", context)
        self.assertIn("IMPOSSIBLE", context)

    def test_build_live_context_contains_events_services_and_seal(self):
        context = analyst_context.build_live_context(
            lambda: ([{"domain": "test", "domain_id": 0, "magnitude": 5, "token": "1234"}], 1, {"test": 1}),
            lambda name: {"name": name, "active": "active", "pid": "42", "since": "now"},
            lambda: {"present": True, "actuator_hash": "aaaa", "runner_hash": "bbbb", "generated": "today"},
            lambda: {"reachable": True, "status": "responding"},
        )
        self.assertIn("Total events recorded: 1", context)
        self.assertIn("slime.service: active", context)
        self.assertIn("Status: PRESENT", context)
        self.assertIn("Status: REACHABLE", context)


class HandlerTests(unittest.TestCase):
    def test_events_endpoint_returns_serialized_events(self):
        payload = ([{"domain": "test", "domain_id": 0, "magnitude": 1, "token": "01"}], 1, {"test": 1})
        with mock.patch.object(server, "read_log", return_value=payload):
            status, body = request_json("GET", "/api/events")

        self.assertEqual(status, 200)
        self.assertEqual(body["total"], 1)
        self.assertEqual(body["by_domain"], {"test": 1})

    def test_status_endpoint_returns_services_and_seal(self):
        with mock.patch.object(server, "get_service_status", side_effect=lambda name: {"name": name, "active": "active", "pid": "1", "since": "now"}), \
             mock.patch.object(server, "get_seal_status", return_value={"present": True, "actuator_hash": "a", "runner_hash": "b", "generated": "today"}):
            status, body = request_json("GET", "/api/status")

        self.assertEqual(status, 200)
        self.assertEqual(body["services"]["slime"]["active"], "active")
        self.assertTrue(body["seal"]["present"])

    def test_health_endpoint_returns_runner_status(self):
        with mock.patch.object(server, "ping_runner", return_value={"reachable": True, "status": "responding"}):
            status, body = request_json("GET", "/api/health")

        self.assertEqual(status, 200)
        self.assertTrue(body["runner"]["reachable"])

    def test_analyst_info_reports_unavailable_provider(self):
        with mock.patch.object(server, "_analyst_available", return_value=(False, "missing key")):
            status, body = request_json("GET", "/api/analyst/info")

        self.assertEqual(status, 200)
        self.assertFalse(body["available"])
        self.assertEqual(body["reason"], "missing key")

    def test_analyst_post_rejects_rate_limited_requests(self):
        with mock.patch.object(server, "_check_rate_limit", return_value=False):
            status, body = request_json("POST", "/api/analyst", {"message": "hello"})

        self.assertEqual(status, 429)
        self.assertIn("Rate limited", body["error"])

    def test_analyst_post_rejects_when_provider_unavailable(self):
        with mock.patch.object(server, "_check_rate_limit", return_value=True), \
             mock.patch.object(server, "_analyst_available", return_value=(False, "missing key")):
            status, body = request_json("POST", "/api/analyst", {"message": "hello"})

        self.assertEqual(status, 503)
        self.assertIn("missing key", body["error"])

    def test_analyst_post_rejects_invalid_json(self):
        with running_server() as port, \
             mock.patch.object(server, "_check_rate_limit", return_value=True), \
             mock.patch.object(server, "_analyst_available", return_value=(True, "ok")):
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/api/analyst", body="{bad json", headers={"Content-Type": "application/json"})
            response = conn.getresponse()
            body = json.loads(response.read().decode())
            conn.close()

        self.assertEqual(response.status, 400)
        self.assertEqual(body["error"], "Invalid JSON")

    def test_analyst_post_rejects_empty_message(self):
        with mock.patch.object(server, "_check_rate_limit", return_value=True), \
             mock.patch.object(server, "_analyst_available", return_value=(True, "ok")):
            status, body = request_json("POST", "/api/analyst", {"message": "   "})

        self.assertEqual(status, 400)
        self.assertEqual(body["error"], "Empty message")

    def test_analyst_post_returns_502_when_llm_call_fails(self):
        with mock.patch.object(server, "_check_rate_limit", return_value=True), \
             mock.patch.object(server, "_analyst_available", return_value=(True, "ok")), \
             mock.patch.object(server.analyst_context, "build_static_context", return_value="static"), \
             mock.patch.object(server.analyst_context, "build_live_context", return_value="live"), \
             mock.patch.object(server, "_call_llm", side_effect=RuntimeError("boom")):
            status, body = request_json("POST", "/api/analyst", {"message": "hello"})

        self.assertEqual(status, 502)
        self.assertEqual(body["error"], "AI Analyst temporarily unavailable")

    def test_analyst_post_returns_response_on_success(self):
        with mock.patch.object(server, "_check_rate_limit", return_value=True), \
             mock.patch.object(server, "_analyst_available", return_value=(True, "ok")), \
             mock.patch.object(server.analyst_context, "build_static_context", return_value="static"), \
             mock.patch.object(server.analyst_context, "build_live_context", return_value="live"), \
             mock.patch.object(server, "_call_llm", return_value="verdict"):
            status, body = request_json("POST", "/api/analyst", {"message": "hello"})

        self.assertEqual(status, 200)
        self.assertEqual(body["response"], "verdict")


if __name__ == "__main__":
    unittest.main()

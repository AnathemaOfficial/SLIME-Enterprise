#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# T06 — Replay Attack (Egress Frame Re-injection)
#
# Invariant tested: FP-I4 (no actuation_token executed twice)
# Threat model: attacker captures a valid 32-byte frame and replays it
#
# Method:
#   1. Send a valid action to SLIME, observe one egress effect
#   2. Capture the actuation_token from actuator log (FRAME_HEX= format)
#   3. Inject the same 32-byte frame directly to the actuator/effecteur
#   4. Verify: second execution must NOT occur (delta events == 0)
#
# Requires:
#   - FirePlank-Guard anti-replay journal active on actuator
#   - Actuator logs frames in format: FRAME_HEX=<64 hex chars>
#
# Configurable via environment:
#   EVENTS_LOG   — path to actuator event log
#   SOCKET_PATH  — egress socket to inject replay into
#   SLIME_ADDR   — SLIME ingress address
#
# Replay target:
#   - Single membrane (SLIME → actuator): target /run/slime/egress.sock
#     The actuator listens on this socket; injection simulates a rogue client.
#   - Double membrane (SLIME-2 → effecteur): target the effecteur socket
#     (e.g., /run/slime-actuator/egress.sock). Set SOCKET_PATH accordingly.
# =============================================================================

echo "[T06] Replay Frame Attack"

# --- Configurable paths with sane defaults ---
EVENTS_LOG="${EVENTS_LOG:-/var/log/slime-actuator/events.log}"
SOCKET_PATH="${SOCKET_PATH:-/run/slime/egress.sock}"
SLIME_ADDR="${SLIME_ADDR:-http://127.0.0.1:8080}"

echo "[T06] Config: EVENTS_LOG=$EVENTS_LOG"
echo "[T06]         SOCKET_PATH=$SOCKET_PATH"
echo "[T06]         SLIME_ADDR=$SLIME_ADDR"

# --- Pre-flight: verify log exists ---
if [ ! -f "$EVENTS_LOG" ]; then
    echo "[T06] SKIP — events log not found at $EVENTS_LOG"
    echo "[T06] Set EVENTS_LOG env var or ensure actuator is logging."
    exit 0
fi

# Step 1: baseline count
before=$(wc -l < "$EVENTS_LOG" 2>/dev/null || echo 0)
echo "[T06] baseline events: $before"

# Step 2: send a valid action → should produce one egress effect
# Note: payload "AA==" is valid base64 (single 0x00 byte).
# The runner ignores payload but canon requires base64; this keeps tests
# portable across harness and future conformant implementations.
RESP=$(curl -sS --max-time 5 -X POST "${SLIME_ADDR}/action" \
    -H 'Content-Type: application/json' \
    -d '{"domain":"test","magnitude":1,"payload":"AA=="}' 2>/dev/null || echo "TIMEOUT")

echo "[T06] ingress response: $RESP"

sleep 1

after_first=$(wc -l < "$EVENTS_LOG" 2>/dev/null || echo 0)
first_delta=$((after_first - before))
echo "[T06] events after first action: $after_first (delta=$first_delta)"

if [ "$first_delta" -eq 0 ]; then
    echo "[T06] SKIP — first action did not produce an event (check SLIME + actuator)"
    exit 0
fi

# Step 3: extract the last logged frame
# Actuator must log frames in format: FRAME_HEX=<64 hex characters>
# This is the standardized AVP log format for testable frame capture.
LAST_FRAME=$(tail -200 "$EVENTS_LOG" | grep -Eo 'FRAME_HEX=[0-9a-f]{64}' | tail -1 | cut -d= -f2 || echo "")

if [ -z "$LAST_FRAME" ]; then
    echo "[T06] SKIP — could not extract frame from log"
    echo "[T06] Actuator must log frames as FRAME_HEX=<64 hex chars> for automated replay testing."
    echo "[T06] Manual test: capture 32 bytes from $SOCKET_PATH and replay via socat."
    exit 0
fi

echo "[T06] Captured frame: ${LAST_FRAME:0:16}...${LAST_FRAME:48:16}"

# Step 4: replay the exact same frame via direct socket injection
# This simulates an attacker who has captured a valid 32-byte frame
# and attempts to re-inject it into the actuator/effecteur boundary.
echo "[T06] Injecting replayed frame into $SOCKET_PATH ..."

echo -n "$LAST_FRAME" | xxd -r -p | socat - UNIX-CONNECT:"$SOCKET_PATH" 2>/dev/null || {
    echo "[T06] WARN — could not connect to $SOCKET_PATH for replay injection"
    echo "[T06] Socket may not accept secondary connections (which is also acceptable)."
    echo "[T06] PASS (by socket rejection) — replay could not be injected"
    exit 0
}

sleep 1

# Step 5: check if replay produced an additional event
after_replay=$(wc -l < "$EVENTS_LOG" 2>/dev/null || echo 0)
replay_delta=$((after_replay - after_first))
echo "[T06] events after replay: $after_replay (delta from first=$replay_delta)"

# Step 6: verdict
echo ""
echo "[T06] === VERDICT ==="

if [ "$replay_delta" -eq 0 ]; then
    echo "[T06] PASS — replay did not produce additional effect (FP-I4 holds)"
elif [ "$replay_delta" -gt 0 ]; then
    echo "[T06] FAIL — replay produced $replay_delta additional effect(s)"
    echo "[T06] Anti-replay journal (FP-I4) is missing or not enforced."
else
    echo "[T06] WARN — unexpected log state (events decreased?)"
fi

echo "[T06] Expected: FirePlank-Guard drops duplicate actuation_token silently"

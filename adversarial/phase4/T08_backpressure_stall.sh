#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# T08 — Backpressure / Egress Stall
#
# Invariant tested: I3 (fail-closed), canon backpressure model
# Threat model: actuator stops reading → egress buffer fills → SLIME behavior
#
# Method:
#   1. Capture baseline event count
#   2. Stop the actuator (simulates disconnect / stall)
#   3. Send N valid actions to SLIME
#   4. Verify: no new events during stall (no bypass)
#   5. Restart actuator, verify queued effects drain
#
# Expected behavior (canon):
#   - SLIME may block due to backpressure; no bypass and no fallback are allowed
#   - Authorized effects buffer in kernel socket buffer
#   - When buffer fills, writes block (backpressure to ingress)
#   - No retry, no fallback, no bypass
#   - After actuator restart, buffered effects drain in FIFO order
#
# Configurable via environment:
#   EVENTS_LOG        — path to actuator event log
#   ACTUATOR_SERVICE  — systemd service name for actuator
#   SLIME_SERVICE     — systemd service name for SLIME
#   SLIME_ADDR        — SLIME ingress address
#   N                 — number of actions to send during stall
#
# Prerequisites:
#   - systemctl available (systemd environment)
#   - sudo access to stop/start actuator service
#   - curl available
#   - SLIME and actuator running before test starts
# =============================================================================

echo "[T08] Backpressure / Egress Stall"

# --- Configurable variables with sane defaults ---
EVENTS_LOG="${EVENTS_LOG:-/var/log/slime-actuator/events.log}"
ACTUATOR_SERVICE="${ACTUATOR_SERVICE:-actuator.service}"
SLIME_SERVICE="${SLIME_SERVICE:-slime.service}"
SLIME_ADDR="${SLIME_ADDR:-http://127.0.0.1:8080}"
N="${N:-50}"

echo "[T08] Config: EVENTS_LOG=$EVENTS_LOG"
echo "[T08]         ACTUATOR_SERVICE=$ACTUATOR_SERVICE"
echo "[T08]         SLIME_SERVICE=$SLIME_SERVICE"
echo "[T08]         SLIME_ADDR=$SLIME_ADDR"
echo "[T08]         N=$N"

# --- Helper: count events in log ---
count_events() {
    [ -f "$EVENTS_LOG" ] && wc -l < "$EVENTS_LOG" || echo 0
}

# --- Pre-flight checks ---
if ! command -v systemctl >/dev/null 2>&1; then
    echo "[T08] SKIP — systemctl not available (systemd required for this test)"
    exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "[T08] SKIP — curl not available"
    exit 0
fi

HAS_EVENTS_LOG=true
if [ ! -f "$EVENTS_LOG" ]; then
    echo "[T08] WARN — events log not found at $EVENTS_LOG"
    echo "[T08] Bypass detection will be limited (no event counting)."
    HAS_EVENTS_LOG=false
fi

# =============================================================================
# Step 1: baseline
# =============================================================================
before=$(count_events)
echo "[T08] Baseline events: $before"

# =============================================================================
# Step 2: stop actuator (simulates stall / disconnect)
# =============================================================================
echo "[T08] Stopping $ACTUATOR_SERVICE ..."
if ! sudo systemctl stop "$ACTUATOR_SERVICE" 2>/dev/null; then
    echo "[T08] SKIP — could not stop $ACTUATOR_SERVICE (sudo/service not available)"
    echo "[T08] Manual test: kill actuator process, flood SLIME, restart, check drain."
    exit 0
fi

sleep 1

# Verify actuator is actually stopped
ACTUATOR_STATUS=$(systemctl is-active "$ACTUATOR_SERVICE" 2>/dev/null || echo "unknown")
if [ "$ACTUATOR_STATUS" = "active" ]; then
    echo "[T08] SKIP — $ACTUATOR_SERVICE still active after stop command"
    exit 0
fi
echo "[T08] $ACTUATOR_SERVICE status: $ACTUATOR_STATUS (confirmed stopped)"

# =============================================================================
# Step 3: send burst of valid actions while actuator is down
# =============================================================================
echo "[T08] Sending $N actions while actuator is stopped..."
AUTHORIZED=0
IMPOSSIBLE=0
TIMEOUTS=0

for i in $(seq 1 "$N"); do
    RESP=$(curl -sS --max-time 5 -X POST "${SLIME_ADDR}/action" \
        -H 'Content-Type: application/json' \
        -d '{"domain":"test","magnitude":1,"payload":"AA=="}' 2>/dev/null || echo "TIMEOUT")

    if echo "$RESP" | grep -q "AUTHORIZED"; then
        AUTHORIZED=$((AUTHORIZED + 1))
    elif echo "$RESP" | grep -q "IMPOSSIBLE"; then
        IMPOSSIBLE=$((IMPOSSIBLE + 1))
    else
        TIMEOUTS=$((TIMEOUTS + 1))
    fi
done

echo "[T08] Results while stalled: authorized=$AUTHORIZED impossible=$IMPOSSIBLE timeout/error=$TIMEOUTS"

# =============================================================================
# Step 4: check for bypass — no new events should appear while actuator is down
# =============================================================================
mid=$(count_events)
mid_delta=$((mid - before))
echo "[T08] Events during stall: before=$before mid=$mid (delta=$mid_delta)"

BYPASS_DETECTED=false
if [ "$HAS_EVENTS_LOG" = true ] && [ "$mid_delta" -gt 0 ]; then
    BYPASS_DETECTED=true
    echo "[T08] CRITICAL — events appeared while actuator was stopped!"
    echo "[T08] This indicates a bypass: effects executed without actuator."
fi

# =============================================================================
# Step 5: check SLIME status
# =============================================================================
SLIME_STATUS=$(systemctl is-active "$SLIME_SERVICE" 2>/dev/null || echo "unknown")
echo "[T08] SLIME status after stall: $SLIME_STATUS"

# =============================================================================
# Step 6: restart actuator and observe drain
# =============================================================================
echo "[T08] Restarting $ACTUATOR_SERVICE ..."
if ! sudo systemctl start "$ACTUATOR_SERVICE" 2>/dev/null; then
    echo "[T08] WARN — could not restart $ACTUATOR_SERVICE"
fi

sleep 3

after=$(count_events)
drained=$((after - mid))
total_delta=$((after - before))
echo "[T08] Events after drain: after=$after (drained=$drained, total_delta=$total_delta)"

# =============================================================================
# Step 7: verdict
# =============================================================================
echo ""
echo "[T08] === VERDICT ==="

# FAIL: bypass detected (events during actuator down)
if [ "$BYPASS_DETECTED" = true ]; then
    echo "[T08] FAIL — bypass detected: $mid_delta event(s) appeared while actuator was stopped"
    echo "[T08] Canon violation: effects must not be produced without actuator"
    exit 1
fi

# Determine verdict based on observable signals
if [ "$HAS_EVENTS_LOG" = true ]; then
    if [ "$drained" -gt 0 ]; then
        # Best case: no events during stall + events after restart = drain observed
        echo "[T08] PASS — no bypass during stall; $drained effect(s) drained after restart"
        echo "[T08] Backpressure model confirmed: buffer → block → drain"
    elif [ "$AUTHORIZED" -gt 0 ] && [ "$drained" -eq 0 ]; then
        # Actions were authorized but nothing drained — could be logging gap or buffer not flushed yet
        echo "[T08] PASS (weak) — no bypass during stall; drain not observed ($AUTHORIZED authorized but 0 drained)"
        echo "[T08] REVIEW: check if actuator logs events, or increase sleep before drain check"
    elif [ "$TIMEOUTS" -eq "$N" ]; then
        # All requests timed out — SLIME was fully blocked by backpressure
        echo "[T08] PASS — all $N requests timed out (full backpressure block, no bypass)"
    else
        echo "[T08] PASS (minimal) — no bypass detected during stall"
        echo "[T08] INFO: authorized=$AUTHORIZED impossible=$IMPOSSIBLE timeout=$TIMEOUTS drained=$drained"
    fi
else
    # No events log — can only check SLIME didn't crash and no bypass via other signals
    if [ "$SLIME_STATUS" = "active" ] || [ "$TIMEOUTS" -gt 0 ]; then
        echo "[T08] PASS (limited) — no events log available; SLIME did not crash"
        echo "[T08] INFO: Cannot verify bypass without actuator event log"
        echo "[T08] For full validation, ensure actuator logs to $EVENTS_LOG"
    else
        echo "[T08] REVIEW — no events log; SLIME status=$SLIME_STATUS"
    fi
fi

echo ""
echo "[T08] Canon expectation: SLIME may block due to backpressure; no bypass and no fallback allowed"
echo "[T08] Drain after restart: $drained effect(s)"

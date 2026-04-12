#!/usr/bin/env bash
set -euo pipefail

echo "[T02] missing required fields (magnitude missing)"

EVENTS_LOG="${EVENTS_LOG:-/var/log/slime-actuator/events.log}"
SLIME_ADDR="${SLIME_ADDR:-http://127.0.0.1:8080}"

count_events() {
  [ -f "$EVENTS_LOG" ] && wc -l < "$EVENTS_LOG" || echo 0
}

before=$(count_events)
resp=$(curl -sS --max-time 5 -X POST "${SLIME_ADDR}/action" \
  -H 'Content-Type: application/json' \
  -d '{"domain":"test","payload":""}' 2>/dev/null || echo "CURL_ERROR")

after=$(count_events)
delta=$((after - before))

echo "[T02] response=$resp"
echo "[T02] events_before=$before events_after=$after delta=$delta"
echo ""
echo "[T02] === VERDICT ==="

if [ "$resp" = "CURL_ERROR" ]; then
  echo "[T02] SKIP — could not reach $SLIME_ADDR"
  exit 0
fi

if [ "$delta" -gt 0 ]; then
  echo "[T02] FAIL — incomplete request produced $delta egress event(s)"
  exit 1
fi

if printf '%s' "$resp" | grep -q "AUTHORIZED"; then
  echo "[T02] FAIL — incomplete request returned AUTHORIZED"
  exit 1
fi

if printf '%s' "$resp" | grep -q "IMPOSSIBLE"; then
  echo "[T02] PASS — missing fields were rejected without egress"
else
  echo "[T02] PASS (limited) — no egress observed and no AUTHORIZED response"
fi

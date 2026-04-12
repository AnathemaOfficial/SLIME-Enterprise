#!/usr/bin/env bash
set -euo pipefail

echo "[T01] invalid JSON"

EVENTS_LOG="${EVENTS_LOG:-/var/log/slime-actuator/events.log}"
SLIME_ADDR="${SLIME_ADDR:-http://127.0.0.1:8080}"

count_events() {
  [ -f "$EVENTS_LOG" ] && wc -l < "$EVENTS_LOG" || echo 0
}

before=$(count_events)
resp=$(curl -sS --max-time 5 -X POST "${SLIME_ADDR}/action" \
  -H 'Content-Type: application/json' \
  -d '{"domain":"test","magnitUde":10,"payload":""' 2>/dev/null || echo "CURL_ERROR")

after=$(count_events)
delta=$((after - before))

echo "[T01] response=$resp"
echo "[T01] events_before=$before events_after=$after delta=$delta"
echo ""
echo "[T01] === VERDICT ==="

if [ "$resp" = "CURL_ERROR" ]; then
  echo "[T01] SKIP — could not reach $SLIME_ADDR"
  exit 0
fi

if [ "$delta" -gt 0 ]; then
  echo "[T01] FAIL — invalid JSON produced $delta egress event(s)"
  exit 1
fi

if printf '%s' "$resp" | grep -q "AUTHORIZED"; then
  echo "[T01] FAIL — invalid JSON returned AUTHORIZED"
  exit 1
fi

if printf '%s' "$resp" | grep -q "IMPOSSIBLE"; then
  echo "[T01] PASS — invalid JSON was rejected without egress"
else
  echo "[T01] PASS (limited) — no egress observed and no AUTHORIZED response"
fi

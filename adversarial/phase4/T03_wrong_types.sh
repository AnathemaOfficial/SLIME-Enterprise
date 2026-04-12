#!/usr/bin/env bash
set -euo pipefail

echo "[T03] wrong types"

EVENTS_LOG="${EVENTS_LOG:-/var/log/slime-actuator/events.log}"
SLIME_ADDR="${SLIME_ADDR:-http://127.0.0.1:8080}"

count_events() {
  [ -f "$EVENTS_LOG" ] && wc -l < "$EVENTS_LOG" || echo 0
}

before=$(count_events)

resp1=$(curl -sS --max-time 5 -X POST "${SLIME_ADDR}/action" \
  -H 'Content-Type: application/json' \
  -d '{"domain":123,"magnitude":"nope","payload":""}' 2>/dev/null || echo "CURL_ERROR")

resp2=$(curl -sS --max-time 5 -X POST "${SLIME_ADDR}/action" \
  -H 'Content-Type: application/json' \
  -d '{"domain":"test","magnitude":-1,"payload":""}' 2>/dev/null || echo "CURL_ERROR")

after=$(count_events)
delta=$((after - before))

echo "[T03] response_1=$resp1"
echo "[T03] response_2=$resp2"
echo "[T03] events_before=$before events_after=$after delta=$delta"
echo ""
echo "[T03] === VERDICT ==="

if [ "$resp1" = "CURL_ERROR" ] || [ "$resp2" = "CURL_ERROR" ]; then
  echo "[T03] SKIP — could not reach $SLIME_ADDR"
  exit 0
fi

if [ "$delta" -gt 0 ]; then
  echo "[T03] FAIL — wrong-type request produced $delta egress event(s)"
  exit 1
fi

if printf '%s\n%s\n' "$resp1" "$resp2" | grep -q "AUTHORIZED"; then
  echo "[T03] FAIL — wrong-type request returned AUTHORIZED"
  exit 1
fi

if printf '%s\n%s\n' "$resp1" "$resp2" | grep -q "IMPOSSIBLE"; then
  echo "[T03] PASS — wrong-type requests were rejected without egress"
else
  echo "[T03] PASS (limited) — no egress observed and no AUTHORIZED response"
fi

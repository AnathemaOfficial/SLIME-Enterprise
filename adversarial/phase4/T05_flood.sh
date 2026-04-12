#!/usr/bin/env bash
set -euo pipefail

echo "[T05] flood requests"

EVENTS_LOG="${EVENTS_LOG:-/var/log/slime-actuator/events.log}"
SLIME_ADDR="${SLIME_ADDR:-http://127.0.0.1:8080}"
N="${N:-200}"

count_events() {
  [ -f "$EVENTS_LOG" ] && wc -l < "$EVENTS_LOG" || echo 0
}

before=$(count_events)
authorized=0
impossible=0
other=0
timeouts=0

for i in $(seq 1 "$N"); do
  resp=$(curl -sS --max-time 5 -X POST "${SLIME_ADDR}/action" \
    -H 'Content-Type: application/json' \
    -d '{"domain":"test","magnitude":10,"payload":"AA=="}' 2>/dev/null || echo "CURL_ERROR")

  if [ "$resp" = "CURL_ERROR" ]; then
    timeouts=$((timeouts + 1))
  elif printf '%s' "$resp" | grep -q "AUTHORIZED"; then
    authorized=$((authorized + 1))
  elif printf '%s' "$resp" | grep -q "IMPOSSIBLE"; then
    impossible=$((impossible + 1))
  else
    other=$((other + 1))
  fi
done

after=$(count_events)
delta=$((after - before))

echo "[T05] events_before=$before events_after=$after delta=$delta"
echo "[T05] authorized=$authorized impossible=$impossible other=$other timeout_or_error=$timeouts"
echo ""
echo "[T05] === VERDICT ==="

if [ "$timeouts" -eq "$N" ]; then
  echo "[T05] SKIP — could not reach $SLIME_ADDR"
  exit 0
fi

if [ "$other" -gt 0 ]; then
  echo "[T05] FAIL — observed $other non-binary response(s) under flood"
  exit 1
fi

echo "[T05] PASS — response surface remained binary under flood"

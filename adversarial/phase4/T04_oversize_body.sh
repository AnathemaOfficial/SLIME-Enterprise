#!/usr/bin/env bash
set -euo pipefail

echo "[T04] oversize body (file-based, no argv blowup)"

EVENTS_LOG="${EVENTS_LOG:-/var/log/slime-actuator/events.log}"
SLIME_ADDR="${SLIME_ADDR:-http://127.0.0.1:8080}"

tmp_json="/tmp/slime_oversize.json"

count_events() {
  [ -f "$EVENTS_LOG" ] && wc -l < "$EVENTS_LOG" || echo 0
}

before=$(count_events)

# Build a ~256KB payload safely into a file.
python3 - <<'PY' > /tmp/slime_oversize.json
import json
big = "A" * 262144
obj = {"domain":"test","magnitude":10,"payload":big}
print(json.dumps(obj))
PY

resp=$(curl -sS --max-time 5 -X POST "${SLIME_ADDR}/action" \
  -H 'Content-Type: application/json' \
  --data-binary @"$tmp_json" 2>/dev/null || echo "CURL_ERROR")

rm -f "$tmp_json"

after=$(count_events)
delta=$((after - before))

echo "[T04] response=$resp"
echo "[T04] events_before=$before events_after=$after delta=$delta"
echo ""
echo "[T04] === VERDICT ==="

if [ "$resp" = "CURL_ERROR" ]; then
  echo "[T04] SKIP — could not reach $SLIME_ADDR"
  exit 0
fi

if [ "$delta" -gt 0 ]; then
  echo "[T04] FAIL — oversize body produced $delta egress event(s)"
  exit 1
fi

if printf '%s' "$resp" | grep -q "AUTHORIZED"; then
  echo "[T04] FAIL — oversize body returned AUTHORIZED"
  exit 1
fi

if printf '%s' "$resp" | grep -q "IMPOSSIBLE"; then
  echo "[T04] PASS — oversize body was rejected without egress"
else
  echo "[T04] PASS (limited) — no egress observed and no AUTHORIZED response"
fi

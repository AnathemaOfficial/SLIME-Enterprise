#!/usr/bin/env bash
set -euo pipefail
echo "[T05] flood 200 requests"
before=$(wc -l < /data/repos/SLIME/enterprise/actuator/logs/events.log 2>/dev/null || echo 0)

for i in $(seq 1 200); do
  curl -sS -o /dev/null -X POST http://127.0.0.1:8080/action \
    -H 'Content-Type: application/json' \
    -d '{"domain":"test","magnitude":10,"payload":""}' || true
done

after=$(wc -l < /data/repos/SLIME/enterprise/actuator/logs/events.log 2>/dev/null || echo 0)
echo "[T05] events_before=$before events_after=$after (delta=$((after-before)))"

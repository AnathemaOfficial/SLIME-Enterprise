#!/usr/bin/env bash
set -euo pipefail
echo "[T01] invalid JSON"
before=$(wc -l < /data/repos/SLIME/enterprise/actuator/logs/events.log 2>/dev/null || echo 0)

curl -sS -o /dev/null -w "code=%{http_code}\n" -X POST http://127.0.0.1:8080/action \
  -H 'Content-Type: application/json' \
  -d '{"domain":"test","magnitUde":10,"payload":""' || true

after=$(wc -l < /data/repos/SLIME/enterprise/actuator/logs/events.log 2>/dev/null || echo 0)
echo "[T01] events_before=$before events_after=$after"

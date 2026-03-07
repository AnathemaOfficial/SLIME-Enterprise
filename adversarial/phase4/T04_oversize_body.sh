#!/usr/bin/env bash
set -euo pipefail
echo "[T04] oversize body (file-based, no argv blowup)"
before=$(wc -l < /data/repos/SLIME/enterprise/actuator/logs/events.log 2>/dev/null || echo 0)

tmp_json="/tmp/slime_oversize.json"

# Build a ~256KB payload safely into a file.
python3 - <<'PY' > /tmp/slime_oversize.json
import json
big = "A" * 262144
obj = {"domain":"test","magnitude":10,"payload":big}
print(json.dumps(obj))
PY

curl -sS -o /dev/null -w "code=%{http_code}\n" -X POST http://127.0.0.1:8080/action \
  -H 'Content-Type: application/json' \
  --data-binary @"$tmp_json" || true

rm -f "$tmp_json"

after=$(wc -l < /data/repos/SLIME/enterprise/actuator/logs/events.log 2>/dev/null || echo 0)
echo "[T04] events_before=$before events_after=$after"

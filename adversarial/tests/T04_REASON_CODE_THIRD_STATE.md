# AVP T04 — Reason-Code / Third-State Injection Attempt

## Invariant attacked
**I1 — Binary Verdict Invariant**  
**I4 — No Reason-Code Invariant**

**Definition:**
SLIME emits only:
- AUTHORIZED (32-byte payload)
- IMPOSSIBLE (non-event)

It must not emit:
- reason codes
- textual explanations
- extra structured fields
- any third state

## Threat model
Local operator with the ability to:
- query SLIME endpoints (ingress)
- inspect HTTP responses
- observe actuator logs

No source modification. No debug builds.

## Attack vector
Attempt to provoke:
- reason-code output
- structured error details
- intermediate states
by submitting malformed/hostile ingress requests.

## Setup (baseline)
Ensure services are active:

```bash
systemctl is-active actuator.service slime.service
```

Identify ingress endpoint (default):
- `127.0.0.1:8080`

## Procedure

1) Send malformed requests (examples)

```bash
# empty body
curl -s -i -X POST http://127.0.0.1:8080/action

# invalid JSON
curl -s -i -X POST http://127.0.0.1:8080/action -H 'Content-Type: application/json' --data '{bad json'

# wrong content-type
curl -s -i -X POST http://127.0.0.1:8080/action -H 'Content-Type: text/plain' --data 'hello'

# oversized body (example 1MB of 'A')
python3 - <<'PY'
import requests
requests.post("http://127.0.0.1:8080/action", data=b"A"*1024*1024).raise_for_status()
PY
```

2) Inspect responses (headers + body)

3) Check actuator logs for any emission

```bash
sudo journalctl -u actuator.service -n 50 --no-pager
```

## Expected invariant behavior

- HTTP responses may indicate failure, but must not leak:
  - reason codes (semantic labels)
  - “why” explanations
  - effect identifiers
- For malformed requests, SLIME must result in:
  - IMPOSSIBLE (non-event) => no 32-byte emission
- No third state must appear in egress.

## Observed result
Fill after execution:

- Did any response contain semantic reason codes?:
- Did any response contain detailed explanations?:
- Did actuator log any event for malformed inputs?:

## Verdict
- **HELD** if malformed inputs produce no egress events and no reason-codes are emitted.
- **VIOLATED** if reason codes / third state / extra structured emissions appear.

## Proof artifacts
Capture:
- `curl -i` outputs (status + headers + body)
- actuator log tail after malformed calls

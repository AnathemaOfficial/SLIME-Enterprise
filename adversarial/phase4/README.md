# SLIME — Phase 4.4 Adversarial Validation Protocol (AVP)

Goal: attempt to force non-canonical behavior.
Observation is external only — no instrumentation inside SLIME.

---

## Environment Variables

All T06–T08 tests accept the following environment variables for portability:

| Variable | Default | Used by |
|---|---|---|
| `EVENTS_LOG` | `/var/log/slime-actuator/events.log` | T06, T08 |
| `SOCKET_PATH` | `/run/slime/egress.sock` | T06 |
| `SLIME_ADDR` | `http://127.0.0.1:8080` | T06, T08 |
| `REGISTRY` | `/etc/slime/domain-registry.json` | T07 |
| `ACTUATOR_SERVICE` | `actuator.service` | T08 |
| `SLIME_SERVICE` | `slime.service` | T08 |
| `N` | `50` | T08 |

**Example (custom paths):**
```bash
EVENTS_LOG=/data/repos/SLIME/enterprise/actuator/logs/events.log \
SOCKET_PATH=/run/slime/egress.sock \
SLIME_ADDR=http://127.0.0.1:8080 \
  ./T06_replay_frame.sh
```

---

## Prerequisites

| Tool | Required by | Purpose |
|---|---|---|
| `curl` | T06, T08 | Send ingress requests to SLIME |
| `socat` | T06 | Inject replayed frame into socket |
| `xxd` | T06 | Convert hex frame to binary |
| `python3` | T07 | Parse domain registry / compute hashes |
| `systemctl` | T08 | Stop/start actuator service |
| `sudo` | T08 | Privileged service control |

Tests gracefully SKIP if their prerequisites are missing.

---

## Actuator Log Format (AVP Standard)

For automated frame capture (T06), the actuator must log received frames in this format:

```
FRAME_HEX=<64 lowercase hex characters>
```

Example:
```
2026-03-01T12:00:00Z FRAME_HEX=a1b2c3d4e5f6a7b8000000000000000100000000000000020000000000000003
```

If the actuator does not log in this format, T06 will SKIP with instructions for manual testing.

---

## Verdict Codes

All tests use consistent verdict output:

| Code | Meaning |
|---|---|
| **PASS** | Invariant holds; test conclusive |
| **PASS (weak)** | No violation detected, but signal is incomplete (e.g., drain not observed) |
| **PASS (limited)** | Prerequisite missing; partial validation only |
| **FAIL** | Invariant violated; canon breach detected |
| **SKIP** | Prerequisites not met; test cannot run |
| **REVIEW** | Ambiguous result; manual inspection recommended |

---

## Ingress Tests (T01–T05)

Invariant: invalid requests must not produce egress effects.

Run order:
1) T01_invalid_json.sh
2) T02_missing_fields.sh
3) T03_wrong_types.sh
4) T04_oversize_body.sh
5) T05_flood.sh

---

## Egress / Actuator Tests (T06–T08)

Invariant: actuator integrity and canon egress behavior under adversarial conditions.

These tests validate FirePlank-Guard invariants (see `enterprise/ACTUATOR_TCB.md`)
and canon backpressure model.

### T06 — Replay Frame Attack

- **Invariant:** FP-I4 (no actuation_token executed twice)
- **Requires:** SLIME running, actuator logging `FRAME_HEX=`, `socat`, `xxd`, `curl`
- **Method:** Send valid action → capture frame from log → replay via socket → verify no second effect
- **Replay target:** Single membrane targets `/run/slime/egress.sock`; double membrane targets effecteur socket (set `SOCKET_PATH`)

### T07 — Domain ID Collision Detection

- **Invariant:** FP-I3 (no domain_id collision in registry)
- **Requires:** `python3`; domain registry at `$REGISTRY` for authoritative check
- **Method:** Parse registry → check for duplicate `domain_id` values
- **Offline:** Does not require SLIME or network; runs against static registry file
- **Without registry:** SKIP with informational FNV-1a hash computation for sample domains

### T08 — Backpressure / Egress Stall

- **Invariant:** I3 (fail-closed under egress stall)
- **Requires:** `systemctl`, `sudo`, `curl`; SLIME and actuator running
- **Method:** Stop actuator → flood SLIME → verify no events during stall → restart → verify drain
- **FAIL condition:** Events appear in actuator log while actuator is stopped (bypass)
- **PASS condition:** No bypass during stall; drain observed after restart

Run order:
6) T06_replay_frame.sh
7) T07_domain_collision.sh
8) T08_backpressure_stall.sh

---

## Regression Guards (Post AB-S Hardening)

### T09 — Domain ID Non-Truncation (proposed)

- **Invariant:** No component in the pipeline truncates `domain_id` below 64 bits
- **Background:** AB-S `Domain` was widened from `u16` to `u64`. SLIME egress ABI has always been `u64`. This test guards against regression where an intermediate layer silently casts to `u16` or `u32`.
- **Method:** Send an action with `domain_id` > 65535 (e.g., `"domain": "large_domain_test_value_that_hashes_above_65535"`) → verify the egress frame contains the full 64-bit `domain_id` (not a truncated value)
- **FAIL condition:** Egress `domain_id` differs from `hash64(domain) & 0xFFFFFFFF` (canon mask) or has been further truncated to 16 bits
- **Scope:** Guards SLIME runner, ingress proxy, and any enterprise middleware

---

## Notes

- All tests use `"payload":"AA=="` (valid base64) for ingress requests
- T01–T05 are ingress-only and do not depend on the environment variables above
- T06–T08 are enterprise-only tests; they validate noncanon deployment hardening
- No test modifies SLIME canon or the 32-byte ABI
- Dashboard observation (if deployed): `http://127.0.0.1:8081/`

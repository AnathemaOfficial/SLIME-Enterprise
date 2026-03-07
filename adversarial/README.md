# Enterprise Adversarial Suite (Option C)

Goal: produce practical evidence that SLIME cannot be coerced into emitting anything outside:

- AUTHORIZED (32-byte egress payload)
- IMPOSSIBLE (non-event)

This suite is not a "security checklist".
It is a closure proof attempt: tests attempt to force SLIME to violate its invariants.

---

## Scope

This suite validates **appliance-level invariants**:

- fail-closed boot dependency (actuator socket required)
- fixed ABI length (32 bytes)
- no reason codes / no third state
- local-only egress behavior (unix socket)
- permission and tamper resistance at the point-of-effect boundary

---

## Test Format

Each test provides:
- Setup
- Steps
- Expected result
- Proof artifacts to capture (commands + outputs)

---

## Run Target

Recommended target: `syf-node` (Ubuntu Server 24.04+, systemd), with Enterprise v0.1 installed.

---

## Tests

- T01: Boot without actuator (fail-closed)
- T02: Socket permission tamper
- T03: Egress size violation attempt (must remain 32 bytes)
- T04: Reason-code / third-state injection attempt
- T05: Restart ordering / crash recovery (still fail-closed)

See `tests/` for procedures.

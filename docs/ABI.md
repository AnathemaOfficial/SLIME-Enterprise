# ABI (Enterprise Appliance v0.1)

This document defines the **fixed egress ABI** emitted by `slime-runner` to the external actuator via the Unix socket:

- Path: `/run/slime/egress.sock`
- Direction: **SLIME (client) -> Actuator (server)**
- Payload: **exactly 32 bytes**
- Semantics: **AUTHORIZED-only payload** (binary law-layer).  
  If the verdict is IMPOSSIBLE, **no payload must be emitted** (non-event).

---

## Invariants

- **Fixed length:** 32 bytes exactly.
- **No additional framing:** no length prefix, no JSON, no headers.
- **No reason codes:** actuator must not expect explanations.
- **Fail-closed:** if the socket is absent/unavailable, SLIME must not run (boot dependency).
- **Interpretation outside SLIME:** logging/decoding/meaning belongs to the actuator layer.

---

## Payload Layout (32 bytes)

Name: `AuthorizedEffect`  
Encoding: **little-endian** for all integer fields.

| Offset | Size | Type  | Field            | Notes |
|-------:|-----:|------:|------------------|-------|
| 0      | 8    | u64   | `domain_id`      | Action domain identifier |
| 8      | 8    | u64   | `magnitude`      | Domain-defined magnitude |
| 16     | 16   | u128  | `actuation_token`| Opaque token (capability/nonce/lease-id), interpretation external |

Total: 8 + 8 + 16 = **32 bytes**

---

## Byte Diagram

```
0                        8                        16                               32
|-------- u64 -----------|-------- u64 -----------|------------- u128 --------------|
|      domain_id         |       magnitude        |         actuation_token          |
```

---

## Determinism Rules

- `domain_id` and `magnitude` are **unsigned** 64-bit integers.
- `actuation_token` is an **opaque** 128-bit value.  
  SLIME does not expose meaning; the actuator decides how it maps to a point-of-effect.
- Endianness is **always little-endian**.
- The actuator must treat any read that is not 32 bytes as invalid (drop / ignore).

---

## Actuator Reference Behavior (non-normative)

- Read exactly 32 bytes from the accepted Unix socket connection.
- Log as hex (64 hex chars) per event.
- Do not send responses to SLIME.
- Any interpretation (mapping, dashboards, human-readable labels) is outside SLIME.

Example log line (hex):
`<64 hex chars>`

---

## Compatibility

This ABI is **frozen for Enterprise Appliance v0.1**.
Any future changes must be versioned explicitly (v0.2, v1.0, etc.) and must never be “silent”.

# FAQ (Enterprise Appliance v0.1)

This FAQ clarifies architectural decisions and invariants.

---

## Why is there no configuration file?

SLIME is a **law-layer**, not a policy engine.

Configuration introduces:
- state variability
- drift
- override risk
- misconfiguration attack surface

The appliance is intentionally minimal and deterministic.

If behavior must change, it must be versioned.

---

## Why only 32 bytes on egress?

Because:

- Fixed-size ABI eliminates framing ambiguity.
- No JSON, no parsing, no schema drift.
- Deterministic contract.
- Easier auditability.

A variable-length payload increases complexity and attack surface.

---

## Why no reason codes?

SLIME emits only:
- AUTHORIZED (32-byte payload)
- IMPOSSIBLE (non-event)

Reasoning belongs outside the law-layer.

Explanations are:
- interpretive
- contextual
- mutable

The law-layer must remain binary and deterministic.

---

## Why fail-closed?

If the actuator (egress socket) is unavailable,
SLIME must not run.

This guarantees:

- No silent bypass
- No fallback mode
- No degraded behavior
- No implicit unsafe execution

The system either operates correctly, or not at all.

---

## Where are logs stored?

SLIME itself does not log semantic events.

The reference actuator logs:
- raw 32-byte payloads (hex)

Interpretation and dashboards are external responsibilities.

---

## Can we extend the ABI?

Not silently.

Any ABI modification must:
- be versioned explicitly
- increment the appliance version
- update documentation
- never break existing deployments implicitly

---

## Can SLIME send data back to the actuator?

No.

The egress channel is unidirectional.

SLIME writes.
Actuator reads.

No bidirectional negotiation.

---

## Is this a firewall?

No.

SLIME is not:
- a firewall
- a monitoring system
- a policy engine
- an authorization server

It is a deterministic membrane at the point-of-effect.

---

## What happens if the actuator crashes?

- The Unix socket disappears.
- SLIME cannot emit.
- Boot/start fails.
- System remains fail-closed.

No partial operation.

---

## Why not use TCP instead of Unix socket?

Unix socket:
- local-only
- no network exposure
- minimal surface
- no routing ambiguity

Enterprise deployments may wrap the actuator externally,
but the law-layer remains local.

---

## Is this production-ready?

Enterprise v0.1 guarantees:

- deterministic ABI
- systemd integration
- reboot stability
- fail-closed behavior
- documented contract

Future versions may extend packaging and validation tooling.

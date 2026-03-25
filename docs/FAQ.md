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

- fixed-size ABI eliminates framing ambiguity
- no JSON, no parsing, no schema drift
- deterministic contract
- easier auditability

A variable-length payload increases complexity and attack surface.

---

## Why no reason codes?

SLIME emits only:
- AUTHORIZED (32-byte payload)
- IMPOSSIBLE (non-event)

Reasoning belongs outside the law-layer.

The law-layer must remain binary and deterministic.

---

## Why fail-closed?

If the actuator (egress socket) is unavailable,
SLIME must not run.

This guarantees:

- no silent bypass
- no fallback mode
- no degraded behavior
- no implicit unsafe execution

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

It is a deterministic membrane at the point of effect.

---

## What happens if the actuator crashes?

- the Unix socket disappears
- SLIME cannot emit
- boot/start fails
- system remains fail-closed

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

Not yet as an unconditional claim.

The current appliance provides:

- deterministic ABI
- systemd integration
- boot integrity floor
- fail-closed service dependency
- documented contract

It should be treated as an **appliance-grade build candidate**.
Before calling it fully ready-to-ship, release provenance, installer e2e
validation, and packaging discipline should be sealed alongside the bundle.

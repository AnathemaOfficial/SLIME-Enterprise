# SLIME v0 — Double Membrane Pattern (Lifeguard)

**Status:** Noncanon (architectural pattern)
**Authority:** This document does not modify canon. Specs/ remains sole authority for SLIME law.

---

## The Lifeguard Analogy

> SLIME-1 is the police officer watching the street.
> SLIME-2 is the lifeguard watching the swimmers.
>
> The police officer does not care about the pool.
> The lifeguard does not care about the street.
>
> The swimmers are the actuator.
> If they respect the rules, everything works.
> If something goes wrong, the lifeguard says: no.
>
> Double law. Double impossibility.

---

## Problem

The standard SLIME architecture has a single membrane:

```
Client/IA → SLIME → Actuator → Effect
```

SLIME guarantees that unauthorized actions produce silence (non-events).
But once SLIME authorizes and emits a 32-byte frame, the actuator is trusted to execute correctly.

**The actuator becomes a single point of trust.**

If the actuator is compromised, confused, or overprivileged, the law is bypassed at the point of effect — regardless of how pure the verdict layer is.

FirePlank-Guard (see ACTUATOR_TCB.md) addresses integrity, replay, and privilege.
But it does not provide a **second law** at the execution boundary.

---

## Solution: Double Membrane

Add a second SLIME instance dedicated to the actuator's execution scope:

```
Client/IA
    │
    ↓
┌──────────────────────────────────┐
│  SLIME-1  (Global Law)           │
│  Scope: ingress → verdict → egress│
│  Metaphor: Police of the street  │
└──────────────────────────────────┘
    │
    │  32-byte frame (/run/slime/egress.sock — canon)
    ↓
┌──────────────────────────────────┐
│  Actuator Gateway                │
│  Role: Transport only            │
│  No logic, no decisions          │
│  Forwards frame to SLIME-2       │
└──────────────────────────────────┘
    │
    │  ActionRequest (domain_id + magnitude)
    ↓
┌──────────────────────────────────┐
│  SLIME-2  (Actuator Law)         │
│  Scope: actuator primitives only │
│  Metaphor: Lifeguard at the pool │
└──────────────────────────────────┘
    │
    │  32-byte frame (SLIME-2 egress — noncanon path)
    ↓
┌──────────────────────────────────┐
│  Effecteur / Drivers             │
│  Role: Mechanical execution only │
│  No decisions, no feedback       │
└──────────────────────────────────┘
    │
    ↓
  Real-world effect
```

**Socket paths:** SLIME-1 remains at the canon path `/run/slime/egress.sock`. SLIME-2 uses an analogous hardcoded path in its own scope (e.g., `/run/slime-actuator/egress.sock`). Paths shown in the diagram are illustrative; only SLIME-1's path is canon.

---

## What SLIME-2 Is

SLIME-2 is **not a new concept**. It is the same SLIME — same binary verdict, same silence, same fail-closed — applied to a different scope.

| Property | SLIME-1 | SLIME-2 |
|---|---|---|
| **Scope** | External actions (ingress) | Actuator primitives (execution) |
| **Observes** | Client/IA requests | Actuator primitive requests (domain_id, magnitude) |
| **Ignores** | The actuator | External ingress, business context |
| **Verdict** | AUTHORIZED / IMPOSSIBLE | AUTHORIZED / IMPOSSIBLE |
| **On impossibility** | Silence (no egress write) | Silence (no effect) |
| **ABI** | 32 bytes | 32 bytes |
| **Feedback** | None | None |
| **Reason codes** | None | None |
| **Configuration** | None | None |

**SLIME-2 is SLIME. Same law, different jurisdiction.**

---

## What SLIME-2 Protects Against

### Scenario 1: Compromised Gateway
The gateway is transport-only. If compromised, it can forward, drop, delay, replay, reorder, or flood requests.
- If it forges frames → SLIME-2 rejects (domain/magnitude not in its sealed law)
- If it drops frames → fail-closed (no effect, acceptable)
- If it replays frames → FirePlank-Guard anti-replay catches it at the effecteur boundary
- If it floods → backpressure applies (fail-closed); system may stall but cannot bypass
- If it reorders → SLIME-2 evaluates each frame independently; reorder has no semantic impact because the law is stateless

SLIME-2 ensures unauthorized primitives remain impossible. FirePlank-Guard covers replay and integrity.

### Scenario 2: Overprivileged Actuator
Without SLIME-2, the actuator maps `domain_id → action` and executes.
With SLIME-2, the actuator can only execute what SLIME-2 authorizes.
- Unauthorized primitives → silence (structurally impossible)
- Magnitude outside bounds → silence

### Scenario 3: Lateral Movement
An attacker gains access to the actuator process.
Without SLIME-2: they can trigger any mapped action.
With SLIME-2: they can only trigger actions that pass the local law.
The blast radius is constrained by the lifeguard's jurisdiction.

---

## SLIME-2 Sealed Law (Actuator Primitives)

SLIME-2's AB-S core contains a sealed mapping of **actuator primitives**.

In SLIME-2, primitives are defined as domains with sealed bounds. Each primitive domain string is hashed using the same normalization approach as canon (`hash64(domain) & 0xFFFFFFFF`), producing a `domain_id`:

```
domain string    →  domain_id (hash)       →  primitive action
────────────────────────────────────────────────────────────────
"open_valve"     →  hash64("open_valve")   →  open_valve
"close_valve"    →  hash64("close_valve")  →  close_valve
"write_db"       →  hash64("write_db")     →  write_db_record
"trigger_deploy" →  hash64("trigger_deploy") → trigger_deploy
```

Each primitive has:
- **Maximum magnitude** (hard-coded, non-configurable)
- **Admission rule** (binary: admitted or impossible)

This mapping is sealed at compile-time (CoreSpec pattern from V1_INVARIANTS). Domain strings are hashed into `domain_id` values at seal time; the sealed registry is verified at boot (FirePlank-Guard FP-3 collision check applies here too).
No runtime configuration. No dynamic registration. No exceptions.

---

## Primitive Design Guidelines

SLIME-2 constrains the actuator to authorized primitives. But if a primitive is too powerful, the authorized space itself contains danger. The lifeguard cannot protect swimmers from a pool filled with acid — even if no unauthorized person enters.

### The Risk: Meta-Primitives

A primitive like `"execute_script"` or `"call_api"` is a **meta-power**: it encodes an unbounded action space within a single authorized domain. An attacker who stays within authorized bounds can still produce catastrophic effects.

**Bad primitives** (meta-powers):
```
"write_db"         →  can write anything to any table
"execute_script"   →  can run arbitrary code
"call_api"         →  can reach any external endpoint
"send_message"     →  can send to any recipient with any content
```

**Good primitives** (atomic, bounded):
```
"open_valve_A"     →  opens one specific valve, magnitude = duration
"close_valve_A"    →  closes one specific valve
"deploy_service_X" →  deploys one specific service (magnitude = version tag)
"process_payment"  →  processes payment in domain "payments", magnitude = amount in cents
```

### Design Rules for Primitives

1. **Atomic** — each primitive does exactly one thing. No composition, no branching.
2. **Non-escalating** — no primitive can be used to gain capabilities beyond its own scope.
3. **Magnitude-bounded** — `magnitude` must have a hard ceiling sealed at compile time. A primitive with `max_magnitude = u64::MAX` is effectively unbounded.
4. **Domain-specific** — the primitive name encodes the target, not just the verb. `"open_valve_A"` not `"open_valve"`.
5. **No indirection** — primitives must not accept references to other resources (file paths, URLs, query strings). The primitive **is** the resource.

### Primitive Power Audit

Before sealing SLIME-2's law, audit each primitive:

| Question | If "yes" → |
|---|---|
| Can this primitive affect resources outside its stated scope? | Split into per-resource primitives |
| Can magnitude encode an unbounded action? | Add hard ceiling, or split by magnitude range |
| Can two authorized primitives compose into an unauthorized effect? | Add cross-domain invariant or split further |
| Would an attacker with unlimited calls to this primitive (but nothing else) cause damage? | Reduce scope or add rate invariant to magnitude |

**Canonical position:** SLIME-2 enforces the law. The deployer defines the law. If the law is too permissive, SLIME-2 faithfully enforces a permissive law. Primitive design is the deployer's responsibility; SLIME-2 provides the enforcement substrate.

---

## What SLIME-2 Does NOT Do

- **Does not parse ingress** — it only sees what the gateway forwards
- **Does not interpret business logic** — it checks structural bounds
- **Does not provide feedback** — silence is the only denial
- **Does not add reason codes** — same principle as SLIME-1
- **Does not become a policy engine** — binary verdict, nothing else
- **Does not communicate with SLIME-1** — they are independent membranes
- **Does not add configuration** — law is sealed at compile-time

---

## FirePlank Integration

FirePlank-Guard (ACTUATOR_TCB.md) wraps both SLIME-2 and the effecteur.

**Anti-replay boundary:** Anti-replay is enforced at the effecteur/actuator boundary (FirePlank-Guard runtime journal — FP-I4), not inside SLIME-2. SLIME-2 is stateless law; it does not maintain journals, counters, or any replay detection. This prevents SLIME-2 from drifting into a stateful policy engine.

```
SLIME-1
    │
    ↓
Gateway
    │
    ↓
┌─────────────────────────────────────┐
│  FirePlank-Guard                    │
│  ├── FP-1: SLIME-2 binary integrity│
│  ├── FP-2: Effecteur binary integrity│
│  ├── FP-3: Replay journal          │
│  ├── FP-4: Domain collision check  │
│  └── FP-5: Privilege sandbox       │
│                                     │
│  ┌───────────────┐                 │
│  │   SLIME-2     │                 │
│  │   (lifeguard) │                 │
│  └───────┬───────┘                 │
│          │                         │
│  ┌───────▼───────┐                 │
│  │  Effecteur    │                 │
│  │  (mechanical) │                 │
│  └───────────────┘                 │
└─────────────────────────────────────┘
```

---

## Failure Modes

| Failure | Behavior | Rationale |
|---|---|---|
| SLIME-2 down | Effecteur cannot act (fail-closed) | No law = no action |
| Gateway down | No frames reach SLIME-2 (fail-closed) | No transport = no action |
| Effecteur down | SLIME-2 writes frames, kernel buffers fill, backpressure | Same as SLIME-1 backpressure model |
| SLIME-1 + SLIME-2 both down | Nothing happens | Double fail-closed |
| Gateway compromised | Can flood/delay/reorder/inject; SLIME-2 blocks unauthorized primitives; FirePlank-Guard catches replay | Lifeguard doesn't trust the street |

**No failure mode produces an unauthorized effect.**

---

## Operational Cost

The double membrane adds:
- One additional process (SLIME-2)
- One additional socket (SLIME-2 egress, noncanon path)
- One additional sealed binary
- Additional failure modes (deadlock, cascading backpressure)

**Mitigation:**
- SLIME-2 is minimal (same codebase, different sealed law)
- Watchdog monitoring for liveness (systemd `WatchdogSec`)
- Backpressure is already the canon model (no new failure class)

---

## Deployment Topology (Illustrative)

The following topology is **illustrative**, not prescriptive. Actual user/group naming and service dependencies may vary by environment. This does not modify canon; SLIME-1 service configuration remains as defined in EGRESS_SOCKET_SPEC.md.

```ini
# actuator-gateway.service
[Unit]
Description=SLIME Actuator Gateway (transport-only)
After=slime.service
Requires=slime.service

[Service]
Type=simple
User=gateway
Group=slime-actuator
ExecStart=/usr/local/bin/actuator-gateway
NoNewPrivileges=yes
RestrictAddressFamilies=AF_UNIX

# slime-actuator.service (SLIME-2)
[Unit]
Description=SLIME-2 Actuator Law (lifeguard)
After=effecteur.service
Requires=effecteur.service

[Service]
Type=simple
User=slime-actuator
Group=slime-actuator
ExecStart=/usr/local/bin/slime-actuator
NoNewPrivileges=yes
ProtectSystem=strict
RestrictAddressFamilies=AF_UNIX

# effecteur.service
[Unit]
Description=SLIME Effecteur (mechanical execution)

[Service]
Type=simple
User=effecteur
Group=slime-actuator
RuntimeDirectory=slime-actuator
ExecStart=/usr/local/bin/effecteur
NoNewPrivileges=yes
ProtectSystem=strict
RestrictAddressFamilies=AF_UNIX
```

**Illustrative boot order:** effecteur → SLIME-2 → gateway → SLIME-1
**Each component:** different user, minimal privileges, AF_UNIX only.

**Note:** Boot order shown is illustrative. In production, SLIME-1 depends on its canon socket (`/run/slime/egress.sock`); if the double membrane changes the dependency chain, service ordering must be adjusted accordingly. User names with hyphens (e.g., `slime-actuator`) are valid on Linux but may create friction on some distributions.

---

## Relationship to SYF Ecosystem

| SYF Concept | Double Membrane Role |
|---|---|
| **SyFF** (R = F*E/K) | The law that defines what is structurally impossible |
| **FirePlank** | Continuity floor protecting SLIME-2 + effecteur integrity |
| **Anathema-Breaker** `resolve_action()` | Pattern: `Ok(Effect) \| Err(Impossibility)` — same binary verdict |
| **SYF-Shield** EngagementToken | Pattern: non-Copy, non-Clone, consumed once — anti-replay model |
| **SYF-Gate** 10 invariants | Pattern: fail-closed, deterministic, no oracle, no feedback |
| **SLIME** | The law-layer instantiation — SLIME-1 and SLIME-2 are the same law |

**Everything comes from SYF-Core. The pieces already exist.**

---

## Canonical Definition

> SLIME-2 is not an ingress policy.
> It is a local impossibility membrane that constrains the actuator itself.
> It observes only actuator primitives, and can only authorize (emit) or make impossible (silence).
>
> The lifeguard watches the swimmers.
> The police watches the street.
> Neither interferes with the other's jurisdiction.
> Both enforce the same kind of law: structural impossibility.

---

**END — DOUBLE MEMBRANE PATTERN (LIFEGUARD)**

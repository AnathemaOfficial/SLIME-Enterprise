# SLIME v0 — Actuator as Trusted Computing Base

**Status:** Noncanon (enterprise integration guidance)
**Authority:** This document does not modify canon. Specs/ remains sole authority for SLIME law.

---

## Problem Statement

SLIME guarantees structural impossibility at the verdict layer:
- Binary verdict (AUTHORIZED or silence)
- Fixed 32-byte ABI
- Fail-closed
- No feedback
- Unidirectional egress

**But SLIME does not guarantee the integrity of what executes after the verdict.**

The actuator — the component that reads 32-byte frames and maps them to real-world effects — becomes the **Trusted Computing Base (TCB)** of the execution chain.

If the actuator is:
- Compromised (binary replaced)
- Confused (domain_id collision)
- Replayed (same frame injected twice)
- Overprivileged (excessive system access)

...then the SLIME law is bypassed at the point of effect, regardless of how pure the verdict layer is.

---

## FirePlank-Guard: Continuity Floor for the Actuator

FirePlank in SYF-Core is a **continuity constraint** — a structural floor that prevents total system collapse without introducing recovery, reward, or bypass.

Applied to the actuator, FirePlank becomes an **integrity floor**: a set of non-negotiable checks that ensure the actuator cannot act outside its defined envelope.

**FirePlank-Guard is not:**
- A policy engine
- A permission system
- A filter or proxy
- A feedback channel
- A debug interface

**FirePlank-Guard is:**
- A boot-time integrity check
- A replay prevention floor
- A domain collision guard
- A privilege reduction boundary

---

## The Four Roles of FirePlank-Guard

### FP-1: Integrity Floor (Boot Verification)

Before the actuator starts, verify its identity:

```
sha256(actuator-binary) == SEALED_HASH
sha256(domain-registry) == SEALED_REGISTRY_HASH
socket permissions == 0660
socket owner == actuator:slime-actuator
```

**If any mismatch:** actuator does not start. Fail-closed.

This addresses the **toolchain compromise** risk identified in V1_INVARIANTS (explicitly out of SLIME's threat model, but within FirePlank-Guard's scope).

**Implementation:**

Sealed hashes live in a **read-only file**, not in the script itself.
If the script contained the hashes, an attacker who modifies the script could also change the expected values.

**Seal file:** `/usr/lib/slime/fireplank.seal` (owned by `root:slime-actuator`, permissions `0440`)
```
# fireplank.seal — generated at deploy time, read-only after installation
ACTUATOR_BIN_HASH=<sha256-of-actuator-binary>
RUNNER_BIN_HASH=<sha256-of-runner-binary>
```

**Guard script:**
```bash
#!/bin/sh
# fireplank-guard-boot.sh — run as ExecStartPre in actuator.service

SEAL_FILE="/usr/lib/slime/fireplank.seal"

# Seal file must exist and be readable
if [ ! -r "$SEAL_FILE" ]; then
    echo "FIREPLANK: seal file missing or unreadable" >&2
    exit 1
fi

ACTUATOR_BIN_HASH=$(grep '^ACTUATOR_BIN_HASH=' "$SEAL_FILE" | cut -d= -f2)
RUNNER_BIN_HASH=$(grep '^RUNNER_BIN_HASH=' "$SEAL_FILE" | cut -d= -f2)

ACTUAL_BIN_HASH=$(sha256sum /usr/local/bin/actuator-min | cut -d' ' -f1)
ACTUAL_RUNNER_HASH=$(sha256sum /usr/local/bin/slime-runner | cut -d' ' -f1)

if [ "$ACTUAL_BIN_HASH" != "$ACTUATOR_BIN_HASH" ]; then
    echo "FIREPLANK: actuator binary integrity FAILED" >&2
    exit 1
fi

if [ "$ACTUAL_RUNNER_HASH" != "$RUNNER_BIN_HASH" ]; then
    echo "FIREPLANK: runner binary integrity FAILED" >&2
    exit 1
fi

echo "FIREPLANK: integrity OK"
```

**Note:** The seal file is generated once at deploy time and must not be modified in production. It is parsed as data, never sourced as shell. If either binary changes, a new seal file must be generated and deployed (full redeploy cycle).

### FP-2: Replay Floor (Anti-Injection)

Prevent the same 32-byte frame from being executed twice:

- Actuator maintains an **append-only journal** of seen `actuation_token` values (journal must be fsync-safe or crash-consistent; a crash must not re-authorize a previously seen token)
- If a token has been seen before: **drop** (no execution, no feedback)
- If the journal is unavailable or corrupted: **actuator enters sealed state** — no frames are executed, no new effects are produced, until the journal is restored and the actuator is restarted

**Properties:**
- No feedback to SLIME (unidirectional preserved)
- No modification to the 32-byte ABI
- Journal is local to the actuator, invisible to SLIME
- Monotonic counter alternative: if token scheme evolves to include sequence numbers
- Journal loss = full stop, not degraded operation

**Note:** This does not modify SLIME. The anti-replay lives entirely within the actuator's execution boundary.

### FP-3: Domain Collision Floor (Registry Verification)

Canon normalizes domains via `hash64(domain) & 0xFFFFFFFF` (32-bit mask).
This creates a non-negligible collision probability at scale.

FirePlank-Guard mitigates this:

- **Sealed domain registry:** static mapping `domain_id → action_name`, verified at boot
- **Collision check at boot:** if any two distinct domains produce the same `domain_id`, abort
- **No dynamic registration:** registry is immutable after deployment; changes require full redeploy (new hash, new seal, new boot verification)

```json
{
  "domains": [
    {"name": "payments", "domain_id": 2847391045, "action": "process_payment"},
    {"name": "deploy",   "domain_id": 1938274610, "action": "trigger_deploy"}
  ]
}
```

**Boot check:** iterate all pairs, verify no `domain_id` collision. If collision detected: fail-closed, actuator does not start.

### FP-4: Privilege Reduction (Sandboxed Execution)

The actuator runs with **minimal privileges**, reducing the blast radius if compromised:

```ini
# In actuator.service (systemd hardening)
[Service]
User=actuator
Group=slime-actuator
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_UNIX
RestrictNamespaces=yes
RestrictRealtime=yes
SystemCallFilter=@system-service
MemoryDenyWriteExecute=yes
```

**Key restrictions:**
- `AF_UNIX` only — no network access
- No new privileges — cannot escalate
- Read-only filesystem — cannot modify binaries
- Private /tmp — no cross-service data leaks

---

## FirePlank-Guard Invariants

| ID | Invariant | Violation Response |
|---|---|---|
| FP-I1 | Actuator binary hash matches sealed value | Abort (fail-closed) |
| FP-I2 | Domain registry hash matches sealed value | Abort (fail-closed) |
| FP-I3 | No domain_id collision exists in registry | Abort (fail-closed) |
| FP-I4 | No actuation_token is executed twice | Drop frame (silent) |
| FP-I5 | Journal integrity is verifiable | Actuator enters sealed state (no execution until restored + restarted) |
| FP-I6 | Actuator runs with minimal privileges | Enforced by systemd |

---

## What FirePlank-Guard Does NOT Do

- **Does not interpret frames** — it checks integrity, not semantics
- **Does not add reason codes** — silence is the only denial
- **Does not provide feedback to SLIME** — unidirectional preserved
- **Does not add configuration** — hashes are sealed at deployment
- **Does not add bypass** — not even for debug
- **Does not modify the 32-byte ABI** — frames pass through untouched
- **Does not become a policy engine** — it is a floor, not a decision maker

---

## Architecture Placement

```
SLIME (law-layer)
    │
    │  32-byte frame (egress.sock)
    ↓
FirePlank-Guard
    │  ├── FP-1: binary integrity check (boot)
    │  ├── FP-2: replay check (runtime)
    │  ├── FP-3: collision check (boot)
    │  └── FP-4: privilege boundary (systemd)
    ↓
Actuator (mechanical execution)
    │
    ↓
Real-world effect
```

**Critical:** FirePlank-Guard lives **outside** SLIME. It wraps the actuator, not the law.

---

## Relationship to SYF-Core FirePlank

In SYF-Core, FirePlank is defined as:

> A mathematical continuity constraint that prevents total system collapse
> by maintaining a minimum coherence threshold without introducing recovery,
> reward, or beneficiary.

Applied here:
- **Continuity** = actuator integrity is preserved across restarts
- **No recovery** = if integrity fails, system stops (no self-heal)
- **No beneficiary** = no component gains power from the check
- **Minimum threshold** = the hash either matches or it doesn't (binary)

This is FirePlank applied to the execution boundary — the same principle, different substrate.

---

## Payload Correlation (Actuator Responsibility)

### The Problem

The 32-byte `AuthorizedEffect` frame contains only:
- `domain_id` (u64)
- `magnitude` (u64)
- `actuation_token` (u128)

**Payload data is not in the frame.** Canon spec (INGRESS_API_SPEC) accepts a `payload` field (base64, up to 64KB), but SLIME does not pass it through egress. The 32-byte ABI is fixed.

This creates a **correlation problem**: when the actuator receives a frame, how does it know which payload belongs to that effect?

### Why This Matters

If 10 actions arrive concurrently, SLIME authorizes 7, and 7 frames appear on egress:
- Two frames may share the same `domain_id` and `magnitude` (same domain, same amount)
- The actuator must know which original payload goes with which frame
- **Wrong correlation = wrong actuation** (right authorization, wrong data)

This is a real attack surface: an adversary who controls ingress timing could attempt to cause payload-effect mismatch.

### Correlation Strategies

The actuator bridge must choose **one** of these strategies. The choice is environment-specific and outside SLIME's scope.

#### Strategy A: Stateless (No Payload Needed)

If actuation depends only on `domain_id` + `magnitude`, no correlation is needed.

```
Effect = f(domain_id, magnitude)
```

This is the simplest and most SYF-aligned model. The payload is used only for logging/auditing at the ingress layer and never reaches the actuator.

**Best for:** IoT commands, circuit breakers, deployment triggers, binary operations.

#### Strategy B: Token-Keyed Correlation

Use `actuation_token` as a correlation key:

```
Ingress layer:
  1. Receive action (domain, magnitude, payload)
  2. Forward to SLIME
  3. Store payload in a correlation table: token → payload
     (token is known after SLIME authorizes, if the ingress proxy
      can observe egress, or if AB-S makes the token predictable
      from action inputs)

Actuator:
  1. Receive frame (domain_id, magnitude, token)
  2. Lookup token in correlation table → retrieve payload
  3. If no match → actuation without payload (or fail-closed)
```

**Challenge:** The token is only visible on the egress stream. The ingress layer does not know the token at request time. This requires either:
- The ingress proxy observes the egress stream (side-channel) to learn the token after authorization
- AB-S generates tokens deterministically from inputs (which makes them predictable — security tradeoff)
- A shared-memory correlation store between ingress proxy and actuator bridge (adds complexity)

**Best for:** Systems that need payload but can accept the complexity.

#### Strategy C: Ordered FIFO Correlation

Since SLIME writes effects in authorization order (FIFO), the actuator bridge can correlate by position:

```
Ingress proxy:
  1. Queue: action₁, action₂, action₃ → SLIME
  2. SLIME authorizes action₁ and action₃ (action₂ = IMPOSSIBLE)
  3. Proxy knows: effect₁ = action₁, effect₂ = action₃

Actuator:
  1. Read frame₁ → correlates to action₁'s payload
  2. Read frame₂ → correlates to action₃'s payload
```

**Challenge:** Strategy C only works in strictly serialized pipelines: single ingress stream, strict serialization, no retries, no parallel clients. Concurrent ingress invalidates the correlation entirely. The ingress proxy must track which actions were authorized (it sees the HTTP response) and maintain an ordered queue that the actuator bridge consumes in lockstep.

**Best for:** Batch/sequential processing, single-client systems. Not suitable for concurrent environments.

#### Strategy D: Domain Encodes Payload Reference

Encode a payload reference into the domain string itself:

```
Instead of: domain="payments", payload={...}
Use:        domain="payments:tx:abc123", payload={...}

The domain_id hash encodes the correlation.
The actuator resolves "payments:tx:abc123" from its own store.
```

**Challenge:** domain_id is a hash — the actuator needs a reverse mapping. The domain registry must be dynamic or comprehensive. This conflicts with sealed registries.

**Best for:** Systems where domains naturally carry identity.

### Recommended Default

**Strategy A (Stateless)** unless the use case specifically requires payload at the actuation layer.

Rationale:
- Eliminates the correlation problem entirely
- No new TCB surface
- Most aligned with SLIME's "minimal surface" philosophy
- If payload is needed, it belongs in a separate channel managed by the environment

### What SLIME Does NOT Do (Payload)

- **Does not forward payload through egress** — 32-byte ABI is fixed
- **Does not correlate payload to effect** — environment's responsibility
- **Does not guarantee payload integrity** — validation is actuator's job
- **Does not buffer payload** — SLIME is stateless

### Security Implications

| Threat | Mitigation |
|---|---|
| Payload substitution (swap payload between concurrent actions) | Strategy A eliminates this; Strategy B uses token as key |
| Payload replay (reuse old payload with new authorization) | FirePlank-Guard FP-I4 prevents token reuse |
| Payload injection (forge payload for valid frame) | Actuator must validate payload independently |
| Correlation desync (FIFO ordering lost) | Strategy C requires single-writer; Strategies A/B are order-independent |

**Canonical position:** Payload correlation is the actuator's problem. SLIME provides the authorization signal; the actuator provides the execution context.

---

## V1 Evolution: Channel Authenticity

### The Remaining Gap

FirePlank-Guard establishes **integrity** (binary not tampered, registry not modified, tokens not replayed). But integrity is not **authenticity**.

The current v0 model relies on Unix filesystem permissions (`0660`, `actuator:slime-actuator`) to restrict who can write to the egress socket. This is sufficient when the OS permission model holds. However:

- A process running in the correct user/group context can write arbitrary frames
- Unix sockets do not authenticate the logical identity of the sender
- If an attacker achieves code execution within the permitted context (without modifying binaries), they can forge frames that pass all v0 checks

**This is not a v0 bug** — the spec explicitly states "No Authentication beyond Unix permissions." It is a **known boundary** of the v0 threat model.

### V1 Path: MAC-Authenticated Frames

The natural evolution is to make each 32-byte frame **cryptographically authenticable**:

```
V0:  [domain_id: u64] [magnitude: u64] [actuation_token: u128]
     └── token is opaque metadata, not a proof of origin

V1:  [domain_id: u64] [magnitude: u64] [mac: u128]
     └── mac = HMAC-SHA256(key, domain_id || magnitude) truncated to 128 bits
     └── key is sealed at deploy time, known only to SLIME + effecteur
```

**Properties:**
- Frame size remains 32 bytes (ABI preserved)
- `actuation_token` field is repurposed as a MAC (no semantic change to the ABI structure)
- Key is sealed in a deploy-time secret (similar to `fireplank.seal`, but for a symmetric key)
- Effecteur verifies MAC before execution; invalid MAC = silent drop
- Anti-replay moves from token journal to MAC + monotonic nonce (if needed)

### What V1 Channel Authenticity Does NOT Do

- **Does not change the 32-byte ABI** — same wire format
- **Does not add feedback** — invalid MAC = silence
- **Does not add configuration** — key is sealed at deploy time
- **Does not replace FirePlank-Guard** — integrity + authenticity are complementary
- **Does not modify canon v0** — this is an evolution path, not a correction

### Relationship to FirePlank-Guard

| Layer | V0 | V1 |
|---|---|---|
| **Binary integrity** | FP-1 (hash check) | FP-1 (unchanged) |
| **Replay prevention** | FP-2 (token journal) | FP-2 (MAC + nonce) |
| **Domain collision** | FP-3 (boot check) | FP-3 (unchanged) |
| **Privilege sandbox** | FP-4 (systemd) | FP-4 (unchanged) |
| **Channel authenticity** | Unix permissions only | HMAC-SHA256 sealed key |

**FirePlank does not replace crypto. Crypto does not replace FirePlank. They compose.**

---

## AB-S ↔ SLIME Type Mapping

Anathema-Breaker (AB-S) is the formal law-layer that SLIME instantiates at runtime. The canonical type widths are:

| Concept | AB-S (Rust) | SLIME Egress ABI | Pipeline |
|---|---|---|---|
| **Domain** | `Domain(u16)` — private field | `domain_id: u64` | u16 → u64 (zero-extended) |
| **Magnitude** | `Magnitude(u32)` — private field | `magnitude: u64` | u32 → u64 (zero-extended) |
| **Token** | N/A (AB-S is stateless) | `actuation_token: u128` | SLIME-side metadata |
| **Budget** | `Budget { capacity: Capacity(u32), progression: Progression(u32) }` — private fields | N/A (not in ABI) | AB-S internal only |

**Critical constraints:**

- **No truncation:** No component may cast `domain_id` or `magnitude` to a smaller type than AB-S provides. The egress ABI uses `u64` fields; AB-S uses narrower types (`u16`, `u32`). The pipeline performs safe zero-extension only.
- **No budget exposure:** AB-S Budget fields are private. SLIME does not expose or forward budget state. Budget is constructed fresh per request from compile-time CoreSpec constants (V1 statelessness).
- **ABI is fixed:** The 32-byte egress frame (`u64 + u64 + u128`) is unchanged by AB-S integration. AB-S narrower types are zero-extended into the ABI fields without loss.
- **Domain resolution:** The runner uses a static compile-time table mapping domain strings to `Domain(u16)`, not a hash function. Unknown domains are structurally impossible. This is a deliberate divergence from the canon hash model, documented in `CONFORMANCE.md`.

---

**END — ACTUATOR TCB / FIREPLANK-GUARD**

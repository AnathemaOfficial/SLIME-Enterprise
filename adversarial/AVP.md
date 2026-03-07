# AVP-v1 — Adversarial Validation Protocol (SLIME Enterprise)

## Purpose

AVP-v1 is a hostile validation protocol designed to **falsify** SLIME invariants.
It does not attempt to “prove security”. It attempts to **force invariant violation**.

A run is successful if all invariants **hold** under adversarial conditions.

---

## System Under Test (SUT)

- Appliance: SLIME Enterprise v0.1
- Components:
  - `slime-runner` (systemd: `slime.service`)
  - `actuator-min` reference (systemd: `actuator.service`)
- Egress:
  - Unix socket: `/run/slime/egress.sock`
  - Fixed ABI: 32 bytes (`AuthorizedEffect`)
- Verdict model:
  - AUTHORIZED => 32-byte payload emitted
  - IMPOSSIBLE => non-event (no payload)

---

## Canonical Invariants (v0.1)

### I1 — Binary Verdict Invariant
SLIME emits only:
- AUTHORIZED (egress event), or
- IMPOSSIBLE (non-event)

No third state.

### I2 — Fixed Egress ABI Invariant
All emitted egress events are **exactly 32 bytes**.
No framing. No JSON. No metadata.

### I3 — Fail-Closed Boot Invariant
If the actuator socket owner is absent/unavailable, SLIME must not run.
No degraded mode.

### I4 — No Reason-Code Invariant
SLIME never emits explanations, codes, or semantic labels.
Interpretation must remain external.

### I5 — Unidirectional Egress Invariant
Egress is write-only from SLIME to actuator.
No bidirectional negotiation channel.

---

## Threat Model (AVP-v1)

Adversary capabilities are **local** (enterprise realistic):

- Has local shell access (operator / admin)
- Can stop/start systemd services
- Can reboot the machine
- Can modify filesystem permissions on `/run/*`
- Can attempt to tamper with socket permissions/ownership
- Can observe logs from actuator layer

Out of scope:
- kernel exploits
- physical attacks
- hypervisor compromise
- supply-chain attacks
- network MITM (egress is local unix socket)

---

## Test Structure

Each AVP test must include:

- Invariant attacked (I1..I5)
- Threat model (capabilities used)
- Attack vector (what is attempted)
- Expected invariant behavior
- Observed result (filled during execution)
- Verdict: **HELD** or **VIOLATED**
- Proof artifacts (command outputs / logs)

---

## Execution Rules

- Tests must be executed on a clean boot where possible.
- Any test that changes system configuration must restore baseline at the end,
  or explicitly declare required follow-up steps.
- Proof artifacts must be recorded verbatim (copy/paste outputs).

---

## Outcome

An AVP-v1 run produces:

- A set of test verdicts (HELD/VIOLATED)
- Captured proof artifacts
- A short final report summarizing invariant status

If any invariant is violated, the protocol is considered **FAILED** until fixed and re-run.

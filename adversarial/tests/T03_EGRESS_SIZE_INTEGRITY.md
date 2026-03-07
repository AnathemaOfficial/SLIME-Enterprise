# AVP T03 — Egress Size Integrity

## Invariant attacked
**I2 — Fixed Egress ABI Invariant**

**Definition:**  
All emitted egress events must be exactly 32 bytes.  
No framing. No metadata. No variable-length payload.

## Threat model
Local operator with the ability to:
- trigger authorized actions
- observe actuator logs
- attempt malformed interaction patterns

No modification of SLIME source code allowed.

## Attack vector
Attempt to observe or coerce SLIME into emitting:
- 31 bytes
- 33 bytes
- framed payload (JSON, prefix, suffix)
- reason-code or structured wrapper

## Setup (baseline)

Ensure services are running:

```bash
systemctl is-active actuator.service slime.service
```

Optionally tail actuator logs:

```bash
sudo journalctl -u actuator.service -f
```

## Procedure

1) Trigger a valid authorized action (domain-specific).

2) Observe actuator output.

3) For each event:
   - Confirm exactly 64 hex characters (representing 32 bytes).
   - Confirm no additional characters before or after.

4) Attempt malformed client-side manipulation if applicable
   (e.g., repeated triggers, rapid calls, boundary stress).

## Expected invariant behavior

- Every authorized event is exactly 32 bytes.
- Log output = 64 hex characters per event.
- No structured envelope.
- No additional metadata.
- No third-state emission.

## Observed result
Fill after execution:

- Sample hex line length:
- Any deviation observed?:
- Any non-32-byte emission?:

## Verdict
- **HELD** if all observed emissions are strictly 32 bytes.
- **VIOLATED** if any emission deviates in size or structure.

## Proof artifacts
Capture:
- actuator log samples
- manual hex-length confirmation
- any anomaly logs

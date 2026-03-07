# AVP T02 — Socket Permission Tamper

## Invariant attacked
**I5 — Unidirectional Egress Invariant** (boundary integrity)  
**I3 — Fail-Closed Boot Invariant** (indirectly, via socket integrity)

**Definition (relevant subset):**
- Egress is a local Unix socket owned by the actuator layer.
- Tampering with permissions must not create a bypass or degrade fail-closed behavior.

## Threat model
Local operator/admin with the ability to:
- modify filesystem permissions on `/run/*`
- restart systemd services

## Attack vector
Manually widen permissions on `/run/slime/egress.sock` and observe whether the system restores canonical permissions after actuator restart.

## Setup (baseline)
Confirm baseline state:

```bash
systemctl is-active actuator.service slime.service
ls -l /run/slime/egress.sock
```

Expected baseline:
- `active / active`
- socket owner: `actuator:slime-actuator`
- perms: `srw-rw----` (0660)

## Procedure

1) Tamper permissions (attempt)

```bash
sudo chmod 777 /run/slime/egress.sock
ls -l /run/slime/egress.sock
```

2) Restart actuator (socket owner)

```bash
sudo systemctl restart actuator.service
ls -l /run/slime/egress.sock
```

3) Confirm SLIME remains operational

```bash
systemctl is-active actuator.service slime.service
```

## Expected invariant behavior
- After actuator restart, the socket is recreated or reset to canonical state:
  - owner: `actuator:slime-actuator`
  - perms: `srw-rw----` (0660)
- No bypass mode appears.
- SLIME remains active only under the canonical socket-owner model.

## Observed result
Fill after execution:

- socket perms after chmod:
- socket perms after actuator restart:
- owner/group after restart:
- slime active?:

## Verdict
- **HELD** if canonical owner/perms are restored after restart, and SLIME remains in normal operation.
- **VIOLATED** if widened permissions persist through restart or allow unexpected behavior.

## Proof artifacts
Capture:
- `ls -l /run/slime/egress.sock` before tamper
- after chmod
- after actuator restart
- `systemctl is-active ...` outputs

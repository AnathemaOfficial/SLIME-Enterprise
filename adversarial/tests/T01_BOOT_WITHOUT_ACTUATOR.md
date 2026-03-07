# AVP T01 — Boot Without Actuator (Fail-Closed)

## Invariant attacked
**I3 — Fail-Closed Boot Invariant**

**Definition:** If the actuator socket owner is absent/unavailable, SLIME must not run.  
No degraded mode. No fallback.

## Threat model
Local operator/admin with the ability to:
- stop/start systemd services
- disable a unit
- reboot the machine

## Attack vector
Disable `actuator.service` before reboot to remove the socket owner at boot.

## Setup (baseline)
Enterprise Appliance installed.

Confirm baseline is healthy:

```bash
systemctl is-active actuator.service slime.service
ls -l /run/slime/egress.sock
```

Expected baseline:
- `active / active`
- socket exists with `actuator:slime-actuator` and perms `0660`

## Procedure

1) Stop both services

```bash
sudo systemctl stop slime.service actuator.service
sudo systemctl reset-failed slime.service actuator.service
```

2) Disable actuator (simulate missing owner at boot)

```bash
sudo systemctl disable actuator.service
sudo systemctl daemon-reload
```

3) Reboot

```bash
sudo reboot
```

4) After reboot, collect status/proof

```bash
systemctl is-enabled actuator.service || true
systemctl is-active actuator.service || true
systemctl is-active slime.service || true

systemctl status slime.service --no-pager -l || true
ls -l /run/slime/egress.sock || true
```

## Expected invariant behavior
- `actuator.service` is disabled and not running.
- `slime.service` must be **inactive/failed** (must not run without actuator).
- `/run/slime/egress.sock` must be absent.

## Observed result
Fill after execution:

- actuator enabled?:
- actuator active?:
- slime active?:
- socket present?:
- key log lines (slime.status):

## Verdict
- **HELD** if slime does not run and socket is absent.
- **VIOLATED** if slime runs, or if any bypass/degraded mode appears.

## Proof artifacts
Attach/capture:
- `systemctl status slime.service` output
- `ls -l /run/slime/egress.sock` output
- any relevant journal lines

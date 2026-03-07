# AVP T05 — Crash / Restart Ordering (Fail-Closed Under Instability)

## Invariant attacked
**I3 — Fail-Closed Boot Invariant**  
**I5 — Unidirectional Egress Invariant** (dependency boundary)

**Definition (relevant subset):**
If the actuator/socket owner is absent, SLIME must not run.
Restart ordering and transient failures must not create a bypass.

## Threat model
Local operator/admin with the ability to:
- stop/start/restart systemd services
- kill processes
- remove the socket file
- trigger rapid ordering/race conditions

## Attack vector
Induce instability:
- kill actuator process
- remove socket
- restart services in wrong order
Verify SLIME remains fail-closed.

## Setup (baseline)

```bash
systemctl is-active actuator.service slime.service
ls -l /run/slime/egress.sock
```

Expected baseline:
- active / active
- socket exists (actuator:slime-actuator, 0660)

## Procedure

### A) Kill actuator process
1) Get actuator PID:

```bash
systemctl show -p MainPID --value actuator.service
```

2) Kill it:

```bash
sudo kill -9 "$(systemctl show -p MainPID --value actuator.service)"
sleep 0.2
```

3) Observe state:

```bash
systemctl is-active actuator.service || true
ls -l /run/slime/egress.sock || true
```

4) Confirm SLIME does not bypass:

```bash
systemctl is-active slime.service || true
```

### B) Remove socket file (tamper)
```bash
sudo rm -f /run/slime/egress.sock
ls -l /run/slime/egress.sock || true
```

Then check SLIME health:

```bash
systemctl is-active slime.service || true
```

### C) Restart ordering (wrong order)
1) Stop both:

```bash
sudo systemctl stop slime.service actuator.service
sudo systemctl reset-failed slime.service actuator.service
```

2) Start slime first (should fail-closed):

```bash
sudo systemctl start slime.service || true
systemctl is-active slime.service || true
systemctl status slime.service --no-pager -l || true
```

3) Start actuator, then slime:

```bash
sudo systemctl start actuator.service
sudo systemctl start slime.service
systemctl is-active actuator.service slime.service
ls -l /run/slime/egress.sock
```

## Expected invariant behavior
- When actuator is killed or socket is absent:
  - SLIME must not enter a bypass mode.
  - If SLIME depends on socket, it should fail/stop or remain blocked.
- Starting slime without actuator must fail-closed.
- Normal operation resumes only when actuator is restored.

## Observed result
Fill after execution:

- After kill: actuator state? socket present?
- After rm socket: slime active?
- Start slime first: did it fail as expected?
- After proper order: did both become active?

## Verdict
- **HELD** if no bypass occurs under all instability steps.
- **VIOLATED** if SLIME runs without actuator/socket or emits unexpected behavior.

## Proof artifacts
Capture:
- `systemctl status slime.service` when started without actuator
- socket presence/permissions before/after
- relevant journal lines

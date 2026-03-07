# FAILURE_MODES

## Startup

- Cannot create `/run/slime`: terminate.
- Cannot apply `/run/slime` permissions: terminate.
- Stale `/run/slime/egress.sock` exists and cannot be removed: terminate.
- Cannot bind `/run/slime/egress.sock`: terminate.
- Cannot apply socket permissions: terminate.

## Accept loop

- `accept()` error: terminate (fail closed, unknown listener state).

## Per-connection read

- Exactly 32 bytes required.
- Read timeout before 32 bytes: drop connection.
- Other read error before 32 bytes: drop connection.

## Logging side effects

- `stderr` logging may fail without affecting actuator semantics.
- File logging is best-effort append-only; open/write failure does not change actuator decision path.

## Third-state avoidance

The actuator has only two operational outcomes for ingress:

1. Valid 32-byte frame consumed and logged.
2. Frame dropped (timeout/read failure).

No retry queue, no alternate transport, and no response channel to SLIME.

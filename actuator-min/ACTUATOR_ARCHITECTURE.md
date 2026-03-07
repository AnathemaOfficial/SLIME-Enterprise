# ACTUATOR_ARCHITECTURE

`actuator-min` is a one-way sink for SLIME egress.

## Boundaries

- Input only: `/run/slime/egress.sock` (Unix stream listener).
- No response path to SLIME. The actuator never writes back to the socket.
- Output side effect is local logging only (`stderr` and optional append to `/var/log/slime-actuator/events.log`).

## Fixed ABI

Each accepted message is exactly 32 bytes, little-endian layout:

- bytes `0..8`   -> `u64` domain_id
- bytes `8..16`  -> `u64` magnitude
- bytes `16..32` -> `u128` actuation_token

Any non-32-byte delivery is dropped by `read_exact` failure handling.

## Fail-closed posture

- Startup failures terminate the process.
- Stale socket removal failure terminates startup.
- Listener accept errors terminate the process.
- Per-connection read timeout drops the connection and continues.
- Logging to disk is best-effort and non-semantic.

## Ownership/permissions

- `/run/slime` mode: `0750`
- `/run/slime/egress.sock` mode: `0660`
- `/var/log/slime-actuator` mode target: `0750` (best effort)

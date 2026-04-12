# ACTUATOR_ARCHITECTURE

`actuator-min` is a one-way sink for SLIME egress with a local replay floor.

## Boundaries

- Input only: `/run/slime/egress.sock` (Unix stream listener).
- No response path to SLIME. The actuator never writes back to the socket.
- Output side effect is local logging only (`FRAME_HEX=...` lines appended to `/var/log/slime-actuator/events.log`).
- Replay protection is local to the actuator via an append-only token journal at `/var/log/slime-actuator/replay-journal.bin`.

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
- Replay-journal corruption or write failure terminates the process.
- Duplicate `actuation_token` values are dropped silently.

## Ownership/permissions

- `/run/slime` mode: `0750`
- `/run/slime/egress.sock` mode: `0660`
- `/var/log/slime-actuator` mode target: `0750` (best effort)

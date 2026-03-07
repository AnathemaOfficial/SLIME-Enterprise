# ARCHITECTURE (Enterprise Appliance v0.1)

## Components
- `slime-runner` (systemd: `slime.service`)
- `actuator-min` reference (systemd: `actuator.service`)
- egress unix socket: `/run/slime/egress.sock`

## Dataflow
Ingress (127.0.0.1:8080) -> SLIME -> Egress (/run/slime/egress.sock) -> Actuator

## Law properties
- Binary verdict only: AUTHORIZED or IMPOSSIBLE
- Fail-closed: if egress socket is absent, SLIME must not run
- No reason codes
- No effect ids
- No debug channels

## Egress ABI (fixed)

AuthorizedEffect = 32 bytes little-endian:
- u64 domain_id
- u64 magnitude
- u128 actuation_token

Actuator logs the raw 32 bytes (hex).
Interpretation is outside SLIME.

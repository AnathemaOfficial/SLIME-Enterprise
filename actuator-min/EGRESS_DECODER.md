# EGRESS_DECODER

`actuator-min` enforces a fixed egress frame size and treats the payload as a fixed little-endian ABI.

## Wire contract (non-negotiable)

Frame size is exactly 32 bytes:

1. `u64` little-endian (`domain_id`)
2. `u64` little-endian (`magnitude`)
3. `u128` little-endian (`actuation_token`)

Byte widths are fixed: `8 + 8 + 16 = 32`.

There is no header, length prefix, checksum, or version byte.

## Runtime behavior

- Reads use `read_exact([u8; 32])`.
- If the peer closes early or times out before 32 bytes, the frame is dropped.
- No partial-frame recovery is attempted.
- The actuator logs the received 32 raw bytes as lowercase hex.

This keeps the ABI fixed while avoiding any feedback channel to SLIME.

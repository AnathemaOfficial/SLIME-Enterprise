"""
SLIME AI Analyst — Versioned SYF Rules Mirror

This file is a READ-ONLY explanatory mirror of the runner-facing constants.
It is NOT an execution authority. It exists solely to feed the AI Analyst
with accurate, version-controlled knowledge about the SLIME law layer.

Any change to the runner's domain table, capacity, magnitude guards, or
ABI must be reflected here. This is a conscious maintenance obligation.

Source of truth for law execution: slime-runner/src/main.rs (compile-time sealed).
Source of truth for analyst explanation: this file.
"""

# -- Domain Table (mirrors DOMAIN_TABLE in slime-runner main.rs) --
DOMAIN_TABLE = {
    "test": 0,
    "payment": 1,
    "deploy": 2,
    "db_prod": 3,
}

# -- CoreSpec Constants (mirrors slime-runner Phase 6.3) --
CORESPEC_CAPACITY = 10_000
CORESPEC_PROGRESSION = 1

# -- Magnitude Guards --
MAX_MAGNITUDE = 2**32 - 1  # u32::MAX = 4,294,967,295

# -- Egress ABI --
EGRESS_FRAME_BYTES = 32
EGRESS_ENCODING = "little-endian"
EGRESS_FIELDS = [
    ("domain_id", "u64", "8 bytes", "offset 0"),
    ("magnitude", "u64", "8 bytes", "offset 8"),
    ("actuation_token", "u128", "16 bytes", "offset 16"),
]

# -- Services --
SERVICES = ["slime.service", "actuator.service"]
SEAL_PATH = "/usr/lib/slime/fireplank.seal"

# -- Impossibility Rules (exhaustive for stub resolver) --
IMPOSSIBILITY_RULES = [
    "Domain not in sealed table → IMPOSSIBLE (structural impossibility)",
    "Domain name is case-sensitive ('PAYMENT' ≠ 'payment') → IMPOSSIBLE",
    "Magnitude = 0 → IMPOSSIBLE (null-action guard)",
    "Magnitude > 4,294,967,295 (u32::MAX) → IMPOSSIBLE (u32 overflow guard)",
    "Magnitude > capacity (10,000 in stub resolver) → IMPOSSIBLE",
    "Egress socket absent at startup → process exit (fail-closed, not IMPOSSIBLE)",
]

# -- Verdict Model --
VERDICT_MODEL = {
    "AUTHORIZED": "32-byte egress frame emitted to actuator via Unix socket",
    "IMPOSSIBLE": "Silence — no egress write, no feedback, non-event",
}

"""
SLIME AI Analyst — Context Builder

Builds the two context blocks injected into the LLM prompt:
  - STATIC context: versioned rules from analyst_rules.py
  - LIVE context: current system state from dashboard server functions

Read-only by construction. No write operations. No feedback into SLIME.
"""

import json
import analyst_rules as rules


def build_static_context() -> str:
    """Build static rules context from versioned analyst_rules.py."""
    parts = []

    parts.append("## Domain Table (compile-time sealed, case-sensitive)")
    for name, did in rules.DOMAIN_TABLE.items():
        parts.append(f"  {name} → domain_id={did}")
    parts.append(f"  Any other domain name → IMPOSSIBLE")

    parts.append(f"\n## Budget (V1 Stateless — fresh per request)")
    parts.append(f"  Capacity: {rules.CORESPEC_CAPACITY}")
    parts.append(f"  Progression: {rules.CORESPEC_PROGRESSION}")
    parts.append(f"  Resolver: magnitude ≤ capacity → AUTHORIZED, else IMPOSSIBLE")

    parts.append(f"\n## Magnitude Guards")
    parts.append(f"  magnitude = 0 → IMPOSSIBLE")
    parts.append(f"  magnitude > {rules.MAX_MAGNITUDE:,} (u32::MAX) → IMPOSSIBLE")

    parts.append(f"\n## Egress ABI ({rules.EGRESS_FRAME_BYTES} bytes, {rules.EGRESS_ENCODING})")
    for field_name, field_type, size, offset in rules.EGRESS_FIELDS:
        parts.append(f"  {offset}: {field_name} ({field_type}, {size})")

    parts.append(f"\n## Verdict Model")
    for verdict, meaning in rules.VERDICT_MODEL.items():
        parts.append(f"  {verdict}: {meaning}")

    parts.append(f"\n## Impossibility Rules")
    for i, rule in enumerate(rules.IMPOSSIBILITY_RULES, 1):
        parts.append(f"  {i}. {rule}")

    return "\n".join(parts)


def build_live_context(read_log_fn, get_service_status_fn,
                       get_seal_status_fn, ping_runner_fn) -> str:
    """Build live system state context.

    Accepts the dashboard server functions as arguments to avoid
    circular imports and maintain clean dependency direction.
    """
    parts = []

    # Events
    try:
        events, total, domain_counts = read_log_fn()
        parts.append(f"## Events")
        parts.append(f"Total events recorded: {total}")
        parts.append(f"Events by domain: {json.dumps(domain_counts)}")
        if events:
            parts.append(f"Recent authorized actions (newest first, showing up to 20):")
            for e in events[:20]:
                parts.append(
                    f"  domain={e['domain']}(id={e['domain_id']}) "
                    f"magnitude={e['magnitude']} token={e['token'][:16]}..."
                )
            if len(events) > 20:
                parts.append(f"  ... and {len(events) - 20} more recent events")
        else:
            parts.append("No events recorded yet.")
    except Exception:
        parts.append("## Events\n(unavailable)")

    # Services
    try:
        parts.append(f"\n## Service Status")
        for svc_name in rules.SERVICES:
            svc = get_service_status_fn(svc_name)
            parts.append(
                f"  {svc['name']}: {svc['active']} "
                f"(PID={svc['pid']}, since={svc['since']})"
            )
    except Exception:
        parts.append("\n## Service Status\n(unavailable)")

    # Seal
    try:
        seal = get_seal_status_fn()
        parts.append(f"\n## FP-1 Seal")
        if seal.get("present"):
            parts.append(f"  Status: PRESENT (verified)")
            parts.append(f"  Actuator hash: {seal.get('actuator_hash', 'N/A')}")
            parts.append(f"  Runner hash: {seal.get('runner_hash', 'N/A')}")
            parts.append(f"  Generated: {seal.get('generated', 'N/A')}")
        else:
            parts.append(f"  Status: MISSING — integrity cannot be verified")
    except Exception:
        parts.append("\n## FP-1 Seal\n(unavailable)")

    # Runner health
    try:
        runner = ping_runner_fn()
        parts.append(f"\n## Runner Health")
        if runner.get("reachable"):
            parts.append(f"  Status: REACHABLE ({runner.get('status', 'unknown')})")
        else:
            parts.append(f"  Status: UNREACHABLE")
            if runner.get("error"):
                parts.append(f"  Error: {runner['error']}")
    except Exception:
        parts.append("\n## Runner Health\n(unavailable)")

    return "\n".join(parts)

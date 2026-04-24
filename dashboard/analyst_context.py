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

    # Codex adversarial audit: the prior label "compile-time sealed"
    # overstated the dashboard's relationship to the runner's real
    # domain table. The runner compiles its table at build time, but
    # this dashboard-side mirror (`analyst_rules.DOMAIN_TABLE`) is a
    # manual copy that must be kept in sync by an operator. A runner
    # binary update with a new domain ID would leave the dashboard
    # silently misreporting the active table to the LLM analyst. Honest
    # label: "manual mirror of the runner's compile-time table".
    parts.append("## Domain Table (manual mirror of runner's compile-time table, case-sensitive)")
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

    # Seal status — honest about what the dashboard can and cannot
    # attest. Codex adversarial audit: the prior code reported
    # "PRESENT (verified)" on any file that existed, without replicating
    # the boot guard's strict parse. That meant a seal with duplicate
    # entries or noise — which the guard REJECTS at ExecStartPre —
    # would still show as "verified" in the dashboard, hiding a live
    # break from the operator. The new `get_seal_status()` parses with
    # the guard's rules and exposes `verified: bool` + `parse_error`;
    # here we surface both states distinctly.
    try:
        seal = get_seal_status_fn()
        parts.append(f"\n## FP-1 Seal")
        if not seal.get("present"):
            parts.append(f"  Status: MISSING — integrity cannot be verified")
        elif seal.get("verified"):
            parts.append(f"  Status: PRESENT (parses under boot-guard rules)")
            parts.append(f"  Actuator hash: {seal.get('actuator_hash', 'N/A')}")
            parts.append(f"  Runner hash: {seal.get('runner_hash', 'N/A')}")
            parts.append(
                "  Note: the dashboard parses the seal with the same rules as "
                "the boot guard, but does NOT re-hash the running binaries. "
                "A match here means the file is well-formed, not that the "
                "binaries on disk match."
            )
        else:
            parse_error = seal.get("parse_error", "unknown parse failure")
            parts.append(
                f"  Status: PRESENT but REJECTED by boot-guard rules "
                f"({parse_error})"
            )
            parts.append(
                "  WARNING: the next actuator restart will fail-closed. "
                "This is a live integrity break."
            )
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


def redact_live_context_for_remote(live_ctx: str) -> str:
    """Strip high-sensitivity fields from a live context before shipping
    it to a remote LLM provider (Anthropic / OpenAI / Kimi).

    Codex + Ana adversarial audit: the full live context includes raw
    event frames, seal hashes, PIDs, and per-service status — enough
    for an operator-authorised prompt to exfiltrate meaningful appliance
    state via the LLM. For local Ollama the data never leaves the host
    and this function is bypassed. For remote providers, we keep the
    structural shape (so the analyst still sees "there was a service
    status block") but replace high-entropy or strongly-identifying
    values with `<redacted>`.

    Operators who explicitly want the full context on a remote provider
    can set `ANALYST_ALLOW_REMOTE_FULL_CONTEXT=1` — acknowledging the
    trade.
    """
    redacted: list[str] = []
    for raw_line in live_ctx.splitlines():
        stripped = raw_line.strip()
        if stripped.startswith("FRAME_HEX=") or stripped.startswith("  FRAME_HEX="):
            redacted.append("  FRAME_HEX=<redacted>")
            continue
        if stripped.startswith("Actuator hash:") or stripped.startswith("Runner hash:"):
            indent = raw_line[: len(raw_line) - len(raw_line.lstrip())]
            key = stripped.split(":", 1)[0]
            redacted.append(f"{indent}{key}: <redacted>")
            continue
        if "PID=" in raw_line:
            import re as _re
            redacted.append(_re.sub(r"PID=\d+", "PID=<redacted>", raw_line))
            continue
        redacted.append(raw_line)
    redacted.append("\n(Remote provider: some fields redacted. "
                    "Set ANALYST_ALLOW_REMOTE_FULL_CONTEXT=1 to disable redaction.)")
    return "\n".join(redacted)

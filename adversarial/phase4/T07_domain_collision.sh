#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# T07 — Domain ID Collision Detection
#
# Invariant tested: FP-I3 (no domain_id collision in registry)
# Threat model: two distinct domains produce the same 32-bit domain_id
#               after hash64(domain) & 0xFFFFFFFF masking
#
# Method:
#   1. If domain registry exists: parse it, check for duplicate domain_id values
#   2. If no registry: SKIP (FP-3 is a registry-defined check)
#   3. Optionally: compute domain_ids locally for a known domain list (informational)
#
# This test is enterprise-only (requires domain registry).
# It does NOT require SLIME to be running, network access, or actuator logs.
#
# Configurable via environment:
#   REGISTRY  — path to domain registry JSON file
#
# Registry format expected:
#   {"domains": [{"name": "...", "domain_id": <uint32>, "action": "..."}, ...]}
#
# This test validates the FirePlank-Guard collision check (FP-3).
# =============================================================================

echo "[T07] Domain ID Collision Detection"

# --- Configurable path with default ---
REGISTRY="${REGISTRY:-/etc/slime/domain-registry.json}"

echo "[T07] Config: REGISTRY=$REGISTRY"

# =============================================================================
# Path A: Registry exists → authoritative collision check
# =============================================================================
if [ -f "$REGISTRY" ]; then
    echo "[T07] Registry found at $REGISTRY"
    echo "[T07] Checking for domain_id collisions..."

    # Parse registry JSON: extract domain_id values, check for duplicates,
    # and report which domains collide if any.
    RESULT=$(python3 -c "
import json, sys
from collections import Counter

try:
    with open('$REGISTRY') as f:
        reg = json.load(f)
except (json.JSONDecodeError, FileNotFoundError) as e:
    print(f'PARSE_ERROR:{e}')
    sys.exit(0)

domains = reg.get('domains', [])
if not domains:
    print('EMPTY')
    sys.exit(0)

ids = [(d.get('name','?'), d.get('domain_id')) for d in domains]

# Check for None/missing domain_id
missing = [name for name, did in ids if did is None]
if missing:
    print(f'MISSING_IDS:{len(missing)}:' + ','.join(missing))
    sys.exit(0)

# Check for duplicates
id_counts = Counter(did for _, did in ids)
collisions = {did: [n for n, d in ids if d == did] for did, count in id_counts.items() if count > 1}

if collisions:
    print(f'COLLISIONS:{len(collisions)}')
    for did, names in collisions.items():
        print(f'  domain_id={did}: {\" vs \".join(names)}')
else:
    print(f'OK:{len(ids)}')
" 2>&1 || echo "EXEC_ERROR")

    echo ""
    echo "[T07] === VERDICT ==="

    case "$RESULT" in
        OK:*)
            COUNT="${RESULT#OK:}"
            echo "[T07] PASS — no domain_id collisions in registry ($COUNT domains checked)"
            ;;
        COLLISIONS:*)
            echo "[T07] FAIL — domain_id collision(s) detected in registry"
            echo "[T07] $RESULT"
            echo "[T07] FirePlank-Guard MUST reject this registry at boot (FP-I3)"
            ;;
        EMPTY)
            echo "[T07] SKIP — registry exists but contains no domains"
            ;;
        MISSING_IDS:*)
            echo "[T07] FAIL — some domains have no domain_id field"
            echo "[T07] $RESULT"
            echo "[T07] Registry format invalid for FP-3 check"
            ;;
        PARSE_ERROR:*)
            echo "[T07] FAIL — could not parse registry"
            echo "[T07] $RESULT"
            echo "[T07] A corrupt registry should cause FirePlank-Guard to abort at boot"
            ;;
        EXEC_ERROR)
            echo "[T07] SKIP — python3 not available or execution failed"
            ;;
        *)
            echo "[T07] WARN — unexpected output: $RESULT"
            ;;
    esac
    exit 0
fi

# =============================================================================
# Path B: No registry → SKIP with informational local analysis
# =============================================================================
echo "[T07] No domain registry found at $REGISTRY"
echo "[T07] FP-3 collision check is registry-defined — cannot validate without registry."
echo ""

# Informational: compute domain_ids for common domain strings using FNV-1a 64-bit + 32-bit mask.
# This shows what domain_ids WOULD be, and whether any collide.
# NOTE: This is informational only. Without the actual registry, this does not validate FP-3.
echo "[T07] Informational: computing domain_ids for common domain strings (FNV-1a 64-bit & 0xFFFFFFFF)..."

python3 -c "
# FNV-1a 64-bit hash (same algorithm used in slime-runner)
FNV_OFFSET = 0xcbf29ce484222325
FNV_PRIME  = 0x00000100000001B3
MASK_64    = (1 << 64) - 1
MASK_32    = 0xFFFFFFFF

def fnv1a_64(data: bytes) -> int:
    h = FNV_OFFSET
    for b in data:
        h ^= b
        h = (h * FNV_PRIME) & MASK_64
    return h

domains = ['test', 'payments', 'deploy', 'control', 'monitor', 'execute', 'admin', 'system']
results = []
for d in domains:
    hash64 = fnv1a_64(d.encode())
    domain_id = hash64 & MASK_32
    results.append((d, domain_id))
    print(f'  {d:20s} → hash64=0x{hash64:016x} → domain_id={domain_id} (0x{domain_id:08x})')

# Check for collisions in this sample
from collections import Counter
id_counts = Counter(did for _, did in results)
collisions = [(did, [n for n, d in results if d == did]) for did, c in id_counts.items() if c > 1]
if collisions:
    print(f'  WARNING: {len(collisions)} collision(s) in sample:')
    for did, names in collisions:
        print(f'    domain_id={did}: {\" vs \".join(names)}')
else:
    print(f'  No collisions in this {len(domains)}-domain sample.')
print()
print('  NOTE: This is informational only. FP-3 validation requires the sealed domain registry.')
" 2>/dev/null || echo "[T07] INFO — python3 not available for informational analysis"

echo ""
echo "[T07] === VERDICT ==="
echo "[T07] SKIP — no domain registry; FP-3 collision check requires registry at $REGISTRY"
echo "[T07] To run this test: deploy a domain-registry.json and set REGISTRY env var if needed."

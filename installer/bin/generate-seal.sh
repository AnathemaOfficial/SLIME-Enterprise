#!/bin/sh
# generate-seal.sh — Generate fireplank.seal from current deployed binaries
# Run once at deploy time. The seal file is data-only and read-only after installation.

set -eu

SEAL_FILE="${SEAL_FILE:-/usr/lib/slime/fireplank.seal}"
SEAL_DIR=$(dirname "$SEAL_FILE")
SEAL_OWNER="${SEAL_OWNER:-root}"
SEAL_GROUP="${SEAL_GROUP:-slime-actuator}"
SEAL_DIR_MODE="${SEAL_DIR_MODE:-0750}"
SEAL_FILE_MODE="${SEAL_FILE_MODE:-0440}"
ACTUATOR_BIN="${ACTUATOR_BIN:-/usr/local/bin/actuator-min}"
RUNNER_BIN="${RUNNER_BIN:-/usr/local/bin/slime-runner}"

die() {
    echo "FIREPLANK: $1" >&2
    exit 1
}

hash_file() {
    file="$1"
    [ -r "$file" ] || die "required binary missing or unreadable: $file"
    sha256sum "$file" | cut -d' ' -f1
}

install -d -m "$SEAL_DIR_MODE" -o "$SEAL_OWNER" -g "$SEAL_GROUP" "$SEAL_DIR"

ACTUATOR_HASH=$(hash_file "$ACTUATOR_BIN")
RUNNER_HASH=$(hash_file "$RUNNER_BIN")
TMP_SEAL=$(mktemp)
trap 'rm -f "$TMP_SEAL"' EXIT HUP INT TERM

cat > "$TMP_SEAL" << EOF
# fireplank.seal — generated at deploy time, data-only after installation
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
ACTUATOR_BIN_HASH=$ACTUATOR_HASH
RUNNER_BIN_HASH=$RUNNER_HASH
EOF

install -m "$SEAL_FILE_MODE" -o "$SEAL_OWNER" -g "$SEAL_GROUP" "$TMP_SEAL" "$SEAL_FILE"
rm -f "$TMP_SEAL"
trap - EXIT HUP INT TERM

echo "Seal file written to $SEAL_FILE"
echo "  ACTUATOR_BIN_HASH=$ACTUATOR_HASH"
echo "  RUNNER_BIN_HASH=$RUNNER_HASH"

#!/bin/sh
# generate-seal.sh — Generate fireplank.seal from current deployed binaries
# Run once at deploy time. The seal file is read-only after creation.

SEAL_FILE="/usr/lib/slime/fireplank.seal"
SEAL_DIR=$(dirname "$SEAL_FILE")

# Create directory if needed
mkdir -p "$SEAL_DIR"

ACTUATOR_HASH=$(sha256sum /usr/local/bin/actuator-min | cut -d' ' -f1)
RUNNER_HASH=$(sha256sum /usr/local/bin/slime-runner | cut -d' ' -f1)

cat > "$SEAL_FILE" << EOF
# fireplank.seal — generated at deploy time, read-only after installation
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
ACTUATOR_BIN_HASH=$ACTUATOR_HASH
RUNNER_BIN_HASH=$RUNNER_HASH
EOF

chmod 444 "$SEAL_FILE"
echo "Seal file written to $SEAL_FILE"
echo "  ACTUATOR_BIN_HASH=$ACTUATOR_HASH"
echo "  RUNNER_BIN_HASH=$RUNNER_HASH"

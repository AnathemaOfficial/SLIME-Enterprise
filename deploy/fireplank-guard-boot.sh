#!/bin/sh
# fireplank-guard-boot.sh — FP-1: Boot-time binary integrity verification
# Run as ExecStartPre in actuator.service
# If any check fails, actuator does not start (fail-closed).

SEAL_FILE="/usr/lib/slime/fireplank.seal"

# Seal file must exist and be readable
if [ ! -r "$SEAL_FILE" ]; then
    echo "FIREPLANK: seal file missing or unreadable" >&2
    exit 1
fi

. "$SEAL_FILE"

# Verify actuator binary
ACTUAL_BIN_HASH=$(sha256sum /usr/local/bin/actuator-min | cut -d' ' -f1)
if [ "$ACTUAL_BIN_HASH" != "$ACTUATOR_BIN_HASH" ]; then
    echo "FIREPLANK: actuator binary integrity FAILED" >&2
    echo "FIREPLANK:   expected=$ACTUATOR_BIN_HASH" >&2
    echo "FIREPLANK:   actual=$ACTUAL_BIN_HASH" >&2
    exit 1
fi

# Verify runner binary
ACTUAL_RUNNER_HASH=$(sha256sum /usr/local/bin/slime-runner | cut -d' ' -f1)
if [ "$ACTUAL_RUNNER_HASH" != "$RUNNER_BIN_HASH" ]; then
    echo "FIREPLANK: runner binary integrity FAILED" >&2
    echo "FIREPLANK:   expected=$RUNNER_BIN_HASH" >&2
    echo "FIREPLANK:   actual=$ACTUAL_RUNNER_HASH" >&2
    exit 1
fi

# Verify socket directory permissions
SOCK_DIR="/run/slime"
if [ -d "$SOCK_DIR" ]; then
    SOCK_PERMS=$(stat -c '%a' "$SOCK_DIR" 2>/dev/null)
    if [ "$SOCK_PERMS" != "755" ]; then
        echo "FIREPLANK: socket directory permissions unexpected: $SOCK_PERMS" >&2
        exit 1
    fi
fi

echo "FIREPLANK: integrity OK"

#!/bin/sh
# fireplank-guard-boot.sh — FP-1: Boot-time binary integrity verification
# Run as ExecStartPre in actuator.service
# If any check fails, actuator does not start (fail-closed).

set -eu

# MiniMax audit finding MED-02: the default systemd units never pass
# these variables via Environment= or EnvironmentFile=, so in the
# normal boot path there is no environment override to worry about.
# But if the guard is ever invoked from another wrapper (cron, shell
# login, operator debug script), a populated environment could redirect
# the integrity check at /usr/lib/slime/fireplank.seal to a different
# path the attacker controls. Explicitly unset the tunables so only
# the hard-coded defaults below are ever honoured, regardless of the
# caller's environment.
unset SEAL_FILE ACTUATOR_BIN RUNNER_BIN SOCK_DIR EXPECTED_SOCK_PERMS

SEAL_FILE="${SEAL_FILE:-/usr/lib/slime/fireplank.seal}"
ACTUATOR_BIN="${ACTUATOR_BIN:-/usr/local/bin/actuator-min}"
RUNNER_BIN="${RUNNER_BIN:-/usr/local/bin/slime-runner}"
SOCK_DIR="${SOCK_DIR:-/run/slime}"
EXPECTED_SOCK_PERMS="${EXPECTED_SOCK_PERMS:-750}"

die() {
    echo "FIREPLANK: $1" >&2
    exit 1
}

normalize_hash() {
    printf '%s' "$1" | tr 'A-F' 'a-f'
}

require_hex_hash() {
    value=$(normalize_hash "$1")
    case "$value" in
        ''|*[!0-9a-f]*)
            return 1
            ;;
    esac
    [ "${#value}" -eq 64 ] || return 1
    printf '%s' "$value"
}

parse_seal_file() {
    ACTUATOR_BIN_HASH=''
    RUNNER_BIN_HASH=''

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|\#*)
                continue
                ;;
            ACTUATOR_BIN_HASH=*)
                [ -z "$ACTUATOR_BIN_HASH" ] || die "seal file contains duplicate ACTUATOR_BIN_HASH"
                ACTUATOR_BIN_HASH=$(require_hex_hash "${line#ACTUATOR_BIN_HASH=}") \
                    || die "seal file contains invalid ACTUATOR_BIN_HASH"
                ;;
            RUNNER_BIN_HASH=*)
                [ -z "$RUNNER_BIN_HASH" ] || die "seal file contains duplicate RUNNER_BIN_HASH"
                RUNNER_BIN_HASH=$(require_hex_hash "${line#RUNNER_BIN_HASH=}") \
                    || die "seal file contains invalid RUNNER_BIN_HASH"
                ;;
            *)
                die "seal file contains unexpected entry"
                ;;
        esac
    done < "$SEAL_FILE"

    [ -n "$ACTUATOR_BIN_HASH" ] || die "seal file missing ACTUATOR_BIN_HASH"
    [ -n "$RUNNER_BIN_HASH" ] || die "seal file missing RUNNER_BIN_HASH"
}

hash_file() {
    file="$1"
    [ -r "$file" ] || die "required binary missing or unreadable: $file"
    sha256sum "$file" | cut -d' ' -f1
}

# Seal file must exist and be readable
[ -r "$SEAL_FILE" ] || die "seal file missing or unreadable"

parse_seal_file

# Verify actuator binary
ACTUAL_BIN_HASH=$(hash_file "$ACTUATOR_BIN")
if [ "$ACTUAL_BIN_HASH" != "$ACTUATOR_BIN_HASH" ]; then
    die "actuator binary integrity FAILED
FIREPLANK:   expected=$ACTUATOR_BIN_HASH
FIREPLANK:   actual=$ACTUAL_BIN_HASH"
fi

# Verify runner binary
ACTUAL_RUNNER_HASH=$(hash_file "$RUNNER_BIN")
if [ "$ACTUAL_RUNNER_HASH" != "$RUNNER_BIN_HASH" ]; then
    die "runner binary integrity FAILED
FIREPLANK:   expected=$RUNNER_BIN_HASH
FIREPLANK:   actual=$ACTUAL_RUNNER_HASH"
fi

# Verify socket directory permissions
if [ -d "$SOCK_DIR" ]; then
    SOCK_PERMS=$(stat -c '%a' "$SOCK_DIR" 2>/dev/null || true)
    if [ "$SOCK_PERMS" != "$EXPECTED_SOCK_PERMS" ]; then
        die "socket directory permissions unexpected: $SOCK_PERMS"
    fi
fi

echo "FIREPLANK: integrity OK"

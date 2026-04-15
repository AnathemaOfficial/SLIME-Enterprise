#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
GENERATE_SCRIPT="$INSTALLER_BIN_DIR/generate-seal.sh"
GUARD_SCRIPT="$INSTALLER_BIN_DIR/fireplank-guard-boot.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SEAL_DIR="$TMP_DIR/seal"
SEAL_FILE="$SEAL_DIR/fireplank.seal"
SOCK_DIR="$TMP_DIR/run/slime"
ACTUATOR_BIN="$TMP_DIR/actuator-min"
RUNNER_BIN="$TMP_DIR/slime-runner"
SEAL_OWNER="$(id -un)"
SEAL_GROUP="$(id -gn)"
EXPECTED_SOCK_PERMS="755"

mkdir -p "$SOCK_DIR"
chmod "$EXPECTED_SOCK_PERMS" "$SOCK_DIR"
printf 'actuator\n' > "$ACTUATOR_BIN"
printf 'runner\n' > "$RUNNER_BIN"
chmod 755 "$ACTUATOR_BIN" "$RUNNER_BIN"

env \
  SEAL_FILE="$SEAL_FILE" \
  SEAL_OWNER="$SEAL_OWNER" \
  SEAL_GROUP="$SEAL_GROUP" \
  SEAL_DIR_MODE="0750" \
  SEAL_FILE_MODE="0440" \
  ACTUATOR_BIN="$ACTUATOR_BIN" \
  RUNNER_BIN="$RUNNER_BIN" \
  "$GENERATE_SCRIPT"

test -f "$SEAL_FILE"
[ "$(stat -c '%a' "$SEAL_DIR")" = "750" ]
[ "$(stat -c '%a' "$SEAL_FILE")" = "440" ]

env \
  SEAL_FILE="$SEAL_FILE" \
  ACTUATOR_BIN="$ACTUATOR_BIN" \
  RUNNER_BIN="$RUNNER_BIN" \
  SOCK_DIR="$SOCK_DIR" \
  EXPECTED_SOCK_PERMS="$EXPECTED_SOCK_PERMS" \
  "$GUARD_SCRIPT"

MALICIOUS_MARKER="$TMP_DIR/owned"
chmod 640 "$SEAL_FILE"
cat > "$SEAL_FILE" <<EOF
ACTUATOR_BIN_HASH=$(sha256sum "$ACTUATOR_BIN" | cut -d' ' -f1)
RUNNER_BIN_HASH=$(sha256sum "$RUNNER_BIN" | cut -d' ' -f1)
EVIL=\$(touch "$MALICIOUS_MARKER")
EOF

if env \
  SEAL_FILE="$SEAL_FILE" \
  ACTUATOR_BIN="$ACTUATOR_BIN" \
  RUNNER_BIN="$RUNNER_BIN" \
  SOCK_DIR="$SOCK_DIR" \
  EXPECTED_SOCK_PERMS="$EXPECTED_SOCK_PERMS" \
  "$GUARD_SCRIPT"; then
    echo "guard accepted malicious seal unexpectedly" >&2
    exit 1
fi

test ! -e "$MALICIOUS_MARKER"
echo "fireplank script tests passed"

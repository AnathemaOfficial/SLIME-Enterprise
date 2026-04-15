#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/systemd"
DEPLOY_DIR="$(cd "$ROOT_DIR/.." && pwd)"
BIN_DIR="/usr/local/bin"
UNIT_DIR="/etc/systemd/system"
SEAL_DIR="/usr/lib/slime"
LOG_DIR="/var/log/slime-actuator"
LEGACY_BIN_DIR="/opt/slime/bin"

echo "[*] Installing systemd units from: $SRC_DIR"

# --- users / groups (idempotent) ---
if ! getent group slime-actuator >/dev/null; then
  groupadd slime-actuator
fi

if ! id -u actuator >/dev/null 2>&1; then
  useradd --system --create-home --shell /usr/sbin/nologin actuator
fi

if ! id -u slime >/dev/null 2>&1; then
  useradd --system --create-home --shell /usr/sbin/nologin slime
fi

usermod -aG slime-actuator actuator
usermod -aG slime-actuator slime

# --- binaries ---
install -d -m 0755 "$BIN_DIR"

if [ -x "$LEGACY_BIN_DIR/slime-runner" ] && [ ! -x "$BIN_DIR/slime-runner" ]; then
  install -m 0755 "$LEGACY_BIN_DIR/slime-runner" "$BIN_DIR/slime-runner"
fi

if [ -x "$LEGACY_BIN_DIR/actuator-binary" ] && [ ! -x "$BIN_DIR/actuator-min" ]; then
  install -m 0755 "$LEGACY_BIN_DIR/actuator-binary" "$BIN_DIR/actuator-min"
fi

test -x "$BIN_DIR/slime-runner"
test -x "$BIN_DIR/actuator-min"

# --- FirePlank scripts + seal ---
install -m 0755 "$DEPLOY_DIR/fireplank-guard-boot.sh" "$BIN_DIR/fireplank-guard-boot.sh"
install -m 0755 "$DEPLOY_DIR/generate-seal.sh" "$BIN_DIR/generate-seal.sh"
install -d -m 0750 -o root -g slime-actuator "$SEAL_DIR"
"$BIN_DIR/generate-seal.sh"

# --- log dir ---
install -d -m 0755 "$LOG_DIR"
chown actuator:slime-actuator "$LOG_DIR"

# --- install units ---
install -m 0644 "$SRC_DIR/actuator.service" "$UNIT_DIR/actuator.service"
install -m 0644 "$SRC_DIR/slime.service"    "$UNIT_DIR/slime.service"

install -d -m 0755 "$UNIT_DIR/actuator.service.d"
install -d -m 0755 "$UNIT_DIR/slime.service.d"
install -m 0644 "$ROOT_DIR/fp4-hardening-actuator.conf" "$UNIT_DIR/actuator.service.d/fp4-hardening.conf"
install -m 0644 "$ROOT_DIR/fp4-hardening-slime.conf" "$UNIT_DIR/slime.service.d/fp4-hardening.conf"

# --- reload + enable + restart ---
systemctl daemon-reload
systemctl enable actuator.service slime.service

systemctl restart actuator.service
systemctl restart slime.service

echo "[*] Done."
systemctl status actuator.service --no-pager || true
systemctl status slime.service --no-pager || true

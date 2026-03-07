#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/systemd"

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

# --- binaries (Option A: auto-copy if present) ---
mkdir -p /opt/slime/bin

if [ -x /usr/local/bin/slime-runner ] && [ ! -x /opt/slime/bin/slime-runner ]; then
  install -m 0755 /usr/local/bin/slime-runner /opt/slime/bin/slime-runner
fi

if [ -x /usr/local/bin/actuator-binary ] && [ ! -x /opt/slime/bin/actuator-binary ]; then
  install -m 0755 /usr/local/bin/actuator-binary /opt/slime/bin/actuator-binary
fi

# Fail if missing
test -x /opt/slime/bin/slime-runner
test -x /opt/slime/bin/actuator-binary

# --- runtime dir (safe) ---
mkdir -p /run/slime
chown actuator:slime-actuator /run/slime
chmod 0770 /run/slime

# --- install units ---
install -m 0644 "$SRC_DIR/actuator.service" /etc/systemd/system/actuator.service
install -m 0644 "$SRC_DIR/slime.service"    /etc/systemd/system/slime.service

mkdir -p /etc/systemd/system/actuator.service.d
install -m 0644 "$SRC_DIR/actuator.service.d/override.conf" /etc/systemd/system/actuator.service.d/override.conf

mkdir -p /etc/systemd/system/slime.service.d
install -m 0644 "$SRC_DIR/slime.service.d/override.conf" /etc/systemd/system/slime.service.d/override.conf

# --- reload + enable + restart ---
systemctl daemon-reload
systemctl enable actuator.service slime.service

systemctl restart actuator.service
systemctl restart slime.service

echo "[*] Done."
systemctl status actuator --no-pager || true
systemctl status slime --no-pager || true

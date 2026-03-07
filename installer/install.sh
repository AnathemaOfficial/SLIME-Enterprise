#!/usr/bin/env bash
# SLIME Appliance Installer — Phase 6 (law-complete + hardened)
# Installs: runner (AB-S real), actuator-min, FirePlank-Guard (FP-1 + FP-4)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="/usr/local/bin"
UNIT_DIR="/etc/systemd/system"
SEAL_DIR="/usr/lib/slime"
LOG_DIR="/var/log/slime-actuator"

echo "============================================"
echo "  SLIME Appliance — Phase 6 Installer"
echo "============================================"
echo ""

# --- [1/10] Users and groups ---
echo "[1/10] Users and groups"
sudo groupadd -f slime-actuator
id -u slime    >/dev/null 2>&1 || sudo useradd -r -s /usr/sbin/nologin -g slime-actuator slime
id -u actuator >/dev/null 2>&1 || sudo useradd -r -s /usr/sbin/nologin -g slime-actuator actuator

# --- [2/10] Install binaries ---
echo "[2/10] Install binaries"
sudo install -m 0755 "$SCRIPT_DIR/bin/slime-runner"   "$BIN_DIR/slime-runner"
sudo install -m 0755 "$SCRIPT_DIR/bin/actuator-min"   "$BIN_DIR/actuator-min"

# --- [3/10] Install FirePlank-Guard scripts (FP-1) ---
echo "[3/10] Install FirePlank-Guard scripts"
sudo install -m 0755 "$SCRIPT_DIR/bin/fireplank-guard-boot.sh" "$BIN_DIR/fireplank-guard-boot.sh"
sudo install -m 0755 "$SCRIPT_DIR/bin/generate-seal.sh"        "$BIN_DIR/generate-seal.sh"

# --- [4/10] Generate seal file (FP-1) ---
echo "[4/10] Generate seal file"
sudo mkdir -p "$SEAL_DIR"
sudo "$BIN_DIR/generate-seal.sh"

# --- [5/10] Create log directory ---
echo "[5/10] Create log directory"
sudo mkdir -p "$LOG_DIR"
sudo chown actuator:slime-actuator "$LOG_DIR"

# --- [6/10] Install systemd units ---
echo "[6/10] Install systemd units"
sudo install -m 0644 "$SCRIPT_DIR/systemd/actuator.service" "$UNIT_DIR/actuator.service"
sudo install -m 0644 "$SCRIPT_DIR/systemd/slime.service"    "$UNIT_DIR/slime.service"

# --- [7/10] Install systemd hardening drop-ins (FP-4) ---
echo "[7/10] Install hardening drop-ins (FP-4)"
sudo mkdir -p "$UNIT_DIR/actuator.service.d"
sudo mkdir -p "$UNIT_DIR/slime.service.d"
sudo install -m 0644 "$SCRIPT_DIR/systemd/fp4-hardening-actuator.conf" "$UNIT_DIR/actuator.service.d/fp4-hardening.conf"
sudo install -m 0644 "$SCRIPT_DIR/systemd/fp4-hardening-slime.conf"    "$UNIT_DIR/slime.service.d/fp4-hardening.conf"

# --- [8/10] Reload and enable ---
echo "[8/10] Reload and enable"
sudo systemctl daemon-reload
sudo systemctl enable actuator.service slime.service

# --- [9/10] Start services ---
echo "[9/10] Start services"
sudo systemctl restart actuator.service
sleep 1
sudo systemctl restart slime.service
sleep 1

# --- [10/10] Verify ---
echo "[10/10] Verify"
echo ""
sudo systemctl --no-pager status actuator.service || true
echo ""
sudo systemctl --no-pager status slime.service || true
echo ""
echo "--- Socket check ---"
ls -l /run/slime/egress.sock 2>/dev/null || echo "WARNING: egress socket not found"
echo ""
echo "--- Seal file ---"
cat "$SEAL_DIR/fireplank.seal" 2>/dev/null || echo "WARNING: seal file not found"
echo ""
echo "--- Live test ---"
RESULT=$(curl -sS -m 2 -X POST http://127.0.0.1:8080/action \
  -H "Content-Type: application/json" \
  -d '{"domain":"test","magnitude":1}' 2>/dev/null || echo "FAILED")
echo "POST domain=test magnitude=1 -> $RESULT"
echo ""

if echo "$RESULT" | grep -q "AUTHORIZED"; then
    echo "============================================"
    echo "  SLIME Appliance installed successfully"
    echo "  AB-S engine: REAL (Phase 6.3)"
    echo "  FirePlank-Guard: FP-1 + FP-4 ACTIVE"
    echo "============================================"
else
    echo "============================================"
    echo "  WARNING: Installation completed but"
    echo "  live test did not return AUTHORIZED."
    echo "  Check service logs."
    echo "============================================"
    exit 1
fi

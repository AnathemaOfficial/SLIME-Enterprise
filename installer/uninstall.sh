#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="/usr/local/bin"
UNIT_DIR="/etc/systemd/system"

echo "============================================"
echo "  SLIME Appliance - Uninstaller"
echo "============================================"
echo ""

echo "[1/8] Stop and disable services"
sudo systemctl stop slime.service actuator.service slime-dashboard.service 2>/dev/null || true
sudo systemctl disable slime.service actuator.service slime-dashboard.service 2>/dev/null || true

echo "[2/8] Remove systemd units and drop-ins"
sudo rm -f "$UNIT_DIR/slime.service" "$UNIT_DIR/actuator.service" "$UNIT_DIR/slime-dashboard.service"
sudo rm -rf "$UNIT_DIR/slime.service.d" "$UNIT_DIR/actuator.service.d"
sudo systemctl daemon-reload

echo "[3/8] Remove binaries"
sudo rm -f "$BIN_DIR/slime-runner" "$BIN_DIR/actuator-min"
sudo rm -f "$BIN_DIR/fireplank-guard-boot.sh" "$BIN_DIR/generate-seal.sh"

echo "[4/8] Remove seal file"
sudo rm -f /usr/lib/slime/fireplank.seal
sudo rmdir /usr/lib/slime 2>/dev/null || true

echo "[5/8] Remove runtime socket"
sudo rm -f /run/slime/egress.sock 2>/dev/null || true
sudo rmdir /run/slime 2>/dev/null || true

echo "[6/8] Remove log directory"
sudo rm -rf /var/log/slime-actuator 2>/dev/null || true

echo "[7/8] Remove dashboard assets"
sudo rm -rf /opt/slime/dashboard 2>/dev/null || true
sudo rmdir /opt/slime 2>/dev/null || true

echo "[8/8] Users and groups (kept - uncomment to remove)"
# sudo userdel slime 2>/dev/null || true
# sudo userdel actuator 2>/dev/null || true
# sudo groupdel slime-actuator 2>/dev/null || true

echo ""
echo "============================================"
echo "  SLIME Appliance uninstalled"
echo "============================================"

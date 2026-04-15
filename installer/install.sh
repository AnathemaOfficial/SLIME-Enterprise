#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="/usr/local/bin"
UNIT_DIR="/etc/systemd/system"
SEAL_DIR="/usr/lib/slime"
LOG_DIR="/var/log/slime-actuator"
DASH_DIR="/opt/slime/dashboard"

echo "============================================"
echo "  SLIME Appliance Installer"
echo "============================================"
echo ""

echo "[1/11] Users and groups"
sudo groupadd -f slime-actuator
id -u slime >/dev/null 2>&1 || sudo useradd -r -s /usr/sbin/nologin -g slime-actuator slime
id -u actuator >/dev/null 2>&1 || sudo useradd -r -s /usr/sbin/nologin -g slime-actuator actuator

echo "[2/11] Install binaries"
sudo install -m 0755 "$SCRIPT_DIR/bin/slime-runner" "$BIN_DIR/slime-runner"
sudo install -m 0755 "$SCRIPT_DIR/bin/actuator-min" "$BIN_DIR/actuator-min"

echo "[3/11] Install FirePlank scripts"
sudo install -m 0755 "$SCRIPT_DIR/bin/fireplank-guard-boot.sh" "$BIN_DIR/fireplank-guard-boot.sh"
sudo install -m 0755 "$SCRIPT_DIR/bin/generate-seal.sh" "$BIN_DIR/generate-seal.sh"

echo "[4/11] Generate seal file"
sudo install -d -m 0750 -o root -g slime-actuator "$SEAL_DIR"
sudo "$BIN_DIR/generate-seal.sh"

echo "[5/11] Create log directory"
sudo mkdir -p "$LOG_DIR"
sudo chown actuator:slime-actuator "$LOG_DIR"

echo "[6/11] Install systemd units"
sudo install -m 0644 "$SCRIPT_DIR/systemd/actuator.service" "$UNIT_DIR/actuator.service"
sudo install -m 0644 "$SCRIPT_DIR/systemd/slime.service" "$UNIT_DIR/slime.service"

echo "[7/11] Install optional dashboard assets"
HAS_DASHBOARD=0
if [ -f "$SCRIPT_DIR/systemd/slime-dashboard.service" ] && [ -f "$SCRIPT_DIR/../dashboard/server.py" ]; then
    HAS_DASHBOARD=1
    sudo mkdir -p "$DASH_DIR"
    sudo install -m 0755 "$SCRIPT_DIR/../dashboard/server.py" "$DASH_DIR/server.py"
    sudo install -m 0644 "$SCRIPT_DIR/../dashboard/dashboard.html" "$DASH_DIR/dashboard.html"
    sudo install -m 0644 "$SCRIPT_DIR/../dashboard/analyst_context.py" "$DASH_DIR/analyst_context.py"
    sudo install -m 0644 "$SCRIPT_DIR/../dashboard/analyst_rules.py" "$DASH_DIR/analyst_rules.py"
    sudo install -m 0644 "$SCRIPT_DIR/../dashboard/__init__.py" "$DASH_DIR/__init__.py"
    sudo install -m 0644 "$SCRIPT_DIR/systemd/slime-dashboard.service" "$UNIT_DIR/slime-dashboard.service"
else
    echo "Dashboard assets not found - skipping dashboard installation"
fi

echo "[8/11] Install hardening drop-ins"
sudo mkdir -p "$UNIT_DIR/actuator.service.d"
sudo mkdir -p "$UNIT_DIR/slime.service.d"
sudo install -m 0644 "$SCRIPT_DIR/systemd/fp4-hardening-actuator.conf" "$UNIT_DIR/actuator.service.d/fp4-hardening.conf"
sudo install -m 0644 "$SCRIPT_DIR/systemd/fp4-hardening-slime.conf" "$UNIT_DIR/slime.service.d/fp4-hardening.conf"

echo "[9/11] Reload and enable"
sudo systemctl daemon-reload
sudo systemctl enable actuator.service slime.service
if [ "$HAS_DASHBOARD" -eq 1 ]; then
    sudo systemctl enable slime-dashboard.service
fi

echo "[10/11] Start services"
sudo systemctl restart actuator.service
sleep 1
sudo systemctl restart slime.service
sleep 1
if [ "$HAS_DASHBOARD" -eq 1 ]; then
    sudo systemctl restart slime-dashboard.service
    sleep 1
fi

echo "[11/11] Verify"
echo ""
sudo systemctl --no-pager status actuator.service || true
echo ""
sudo systemctl --no-pager status slime.service || true
if [ "$HAS_DASHBOARD" -eq 1 ]; then
    echo ""
    sudo systemctl --no-pager status slime-dashboard.service || true
fi
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
    echo "  FirePlank-Guard: ACTIVE"
    if [ "$HAS_DASHBOARD" -eq 1 ]; then
        echo "  Dashboard: installed"
    fi
    echo "============================================"
else
    echo "============================================"
    echo "  WARNING: Installation completed but"
    echo "  live test did not return AUTHORIZED."
    echo "  Check service logs."
    echo "============================================"
    exit 1
fi
